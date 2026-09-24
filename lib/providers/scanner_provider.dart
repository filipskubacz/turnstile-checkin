import 'package:flutter/foundation.dart';
import '../models/app_settings.dart';
import '../models/registration.dart';
import '../services/graphql_service.dart';
import '../services/queue_service.dart';
import '../services/storage_service.dart';
import '../utils/m3_motion.dart';

enum ScanState {
  ready,
  validating,
  fetching,
  ticketFound,
  error,
}

class ScannerProvider extends ChangeNotifier {
  final GraphQLService graphQLService;
  final QueueService queueService;
  final StorageService? storageService;
  final AppSettings Function() getSettings;
  final Duration? onlineTimeoutThreshold;

  ScanState _state = ScanState.ready;
  String? _scannedCode;
  String? _errorTitle;
  String? _errorMessage;
  EventRegistration? _currentRegistration;
  bool _isEventMatched = true;
  String? _eventMatchMessage;
  DateTime? _lastScannedAt;
  String? _lastScannedUuid;
  String? _duplicateScanNotice;
  bool _isOfflineFallback = false;
  bool _isOnlineVerifying = false;
  int? _lastCheckedInCount;
  bool _wasAlreadyAttendedOnScan = false;
  String? _lastCheckedInFeedback;

  static final RegExp _uuidRegex = RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
  );

  ScannerProvider({
    required this.graphQLService,
    required this.queueService,
    required this.getSettings,
    this.storageService,
    this.onlineTimeoutThreshold,
  });

  ScanState get state => _state;
  String? get scannedCode => _scannedCode;
  String? get errorTitle => _errorTitle;
  String? get errorMessage => _errorMessage;
  String? get duplicateScanNotice => _duplicateScanNotice;
  EventRegistration? get currentRegistration => _currentRegistration;
  bool get isEventMatched => _isEventMatched;
  String? get eventMatchMessage => _eventMatchMessage;
  bool get isOfflineFallback => _isOfflineFallback;
  bool get isOnlineVerifying => _isOnlineVerifying;
  int? get lastCheckedInCount => _lastCheckedInCount;
  bool get wasAlreadyAttendedOnScan => _wasAlreadyAttendedOnScan;
  String? get lastScannedUuid => _lastScannedUuid;
  DateTime? get lastScannedAt => _lastScannedAt;
  String? get lastCheckedInFeedback => _lastCheckedInFeedback;

  void clearCheckedInFeedback() {
    _lastCheckedInFeedback = null;
    notifyListeners();
  }

  void clearDuplicateNotice() {
    _duplicateScanNotice = null;
    notifyListeners();
  }

  @visibleForTesting
  void setEventMatchedForTesting(bool matched, [String? message]) {
    _isEventMatched = matched;
    _eventMatchMessage = message;
    notifyListeners();
  }

  @visibleForTesting
  void setCurrentRegistrationForTesting(EventRegistration? reg) {
    _currentRegistration = reg;
    _state = reg != null ? ScanState.ticketFound : ScanState.ready;
    notifyListeners();
  }

  static bool isValidUuid(String code) {
    return _uuidRegex.hasMatch(code.trim());
  }

  void _applyEventMatching(EventRegistration reg, AppSettings settings) {
    final activeEvents = settings.activeEventIds;
    if (activeEvents.isNotEmpty) {
      final regEventId = reg.event?.id ?? '';
      if (activeEvents.contains(regEventId)) {
        _isEventMatched = true;
        _eventMatchMessage = null;
      } else {
        _isEventMatched = false;
        _eventMatchMessage =
            'Ticket is for "${reg.event?.title ?? 'Unknown'}" (ID: $regEventId), which does not match active event(s).';
      }
    } else {
      _isEventMatched = true;
      _eventMatchMessage = null;
    }
  }

  Future<void> handleBarcodeScanned(String rawCode) async {
    final code = rawCode.trim();
    if (code.isEmpty) return;

    // Ignore incoming scans while a request is in-flight (if not found locally)
    if (_state == ScanState.fetching) {
      return;
    }

    // Inform user if the exact same ticket is already on screen
    if (_state == ScanState.ticketFound && _scannedCode == code) {
      _duplicateScanNotice = 'Ticket is already displayed on screen.';
      notifyListeners();
      return;
    }

    // Inform user if debounced within 1.5 seconds (prevents accidental immediate duplicate check-ins)
    if (_lastScannedUuid == code &&
        _lastScannedAt != null &&
        DateTime.now().difference(_lastScannedAt!) <
            const Duration(milliseconds: 1500)) {
      _duplicateScanNotice =
          'Ticket recently checked in / scanned. Point camera at next ticket.';
      notifyListeners();
      return;
    }

    _duplicateScanNotice = null;
    _lastScannedUuid = code;
    _lastScannedAt = DateTime.now();
    _scannedCode = code;
    _lastCheckedInCount = null;

    // Step 1: UUID Format Check
    if (!isValidUuid(code)) {
      _state = ScanState.error;
      _errorTitle = 'Invalid QR Code';
      _errorMessage =
          'The scanned code is not a valid ticket UUID. Please make sure the attendee is presenting an official event ticket.';
      _currentRegistration = null;
      _isOfflineFallback = false;
      _isOnlineVerifying = false;
      notifyListeners();
      return;
    }

    final settings = getSettings();

    // Step 2: IMMEDIATE local copy verification
    EventRegistration? localReg;
    if (storageService != null) {
      localReg = await storageService!.findCachedRegistration(code);
    }

    if (localReg != null) {
      // Deduct any entries currently pending or processing in the queue
      final pendingCount = queueService.getPendingEntriesCount(localReg.id);
      if (pendingCount > 0) {
        final effectiveRemaining =
            (localReg.remainingEntries - pendingCount).clamp(0, localReg.totalPartySize);
        localReg = localReg.copyWith(
          remainingEntries: effectiveRemaining,
          didAttend: localReg.didAttend || effectiveRemaining < localReg.totalPartySize,
        );
      }

      _currentRegistration = localReg;
      _wasAlreadyAttendedOnScan = localReg.isAlreadyAttended;
      _applyEventMatching(localReg, settings);
      _state = ScanState.ticketFound;
      _isOnlineVerifying = true;
      _isOfflineFallback = false;
      _errorTitle = null;
      _errorMessage = null;

      // Haptic feedback alert immediately on local resolution:
      // Trigger error vibration if ticket was already used, unpaid, or event does not match
      final isLocalProblematic = localReg.isAlreadyAttended ||
          localReg.isPaymentIncomplete ||
          !_isEventMatched;
      if (isLocalProblematic) {
        M3Haptics.vibrateScanError();
      } else {
        M3Haptics.vibrateScanSuccess();
      }

      notifyListeners();

      // Run online verification concurrently in the background
      _performBackgroundOnlineCheck(code, settings, hadLocalMatch: true);
    } else {
      // Not yet in local cache: show validating indicator while online check runs
      _state = ScanState.fetching;
      _errorTitle = null;
      _errorMessage = null;
      _isOfflineFallback = false;
      _isOnlineVerifying = true;
      notifyListeners();

      await _performBackgroundOnlineCheck(code, settings, hadLocalMatch: false);
    }
  }

  Future<void> _performBackgroundOnlineCheck(
    String code,
    AppSettings settings, {
    required bool hadLocalMatch,
  }) async {
    GraphQLResult<EventRegistration>? result;
    final timeout = onlineTimeoutThreshold ?? Duration(seconds: settings.timeoutSeconds);
    try {
      // Continue waiting until the timeout set in settings is reached before offering offline check-in
      result = await graphQLService.getRegistration(code, settings).timeout(
        timeout,
      );
    } catch (_) {
      // Network timeout or offline exception
      result = null;
    }

    // If another ticket was scanned in the meantime, discard stale response
    if (_scannedCode != code) return;

    if (result != null && result.isSuccess && result.data != null) {
      final serverReg = result.data!;

      // Retrieve existing local cache state
      final cached = storageService != null
          ? await storageService!.findCachedRegistration(serverReg.id)
          : null;

      final pendingCount = queueService.getPendingEntriesCount(serverReg.id);
      final hasDeviceCheckIn = queueService.hasAnyDeviceCheckIn(serverReg.id);

      final reconciled = serverReg.reconcileWithLocal(
        cached: cached ?? _currentRegistration,
        pendingQueueEntries: pendingCount,
        hasDeviceCheckIn: hasDeviceCheckIn,
      );

      _currentRegistration = reconciled;
      _applyEventMatching(reconciled, settings);
      final isReconciledProblematic = reconciled.isAlreadyAttended ||
          reconciled.isPaymentIncomplete ||
          !_isEventMatched;

      if (!hadLocalMatch) {
        _wasAlreadyAttendedOnScan = reconciled.isAlreadyAttended;
        if (isReconciledProblematic) {
          M3Haptics.vibrateScanError();
        } else {
          M3Haptics.vibrateScanSuccess();
        }
      } else if (isReconciledProblematic &&
          !(cached?.isAlreadyAttended ?? false) &&
          !(cached?.isPaymentIncomplete ?? false)) {
        // Ticket initially seemed fine locally, but server authoritative record revealed a problem
        M3Haptics.vibrateScanError();
      }
      _isOnlineVerifying = false;
      _isOfflineFallback = false;
      _state = ScanState.ticketFound;
      if (storageService != null) {
        await storageService!.saveReconciledRegistration(reconciled);
      }
      notifyListeners();
    } else {
      // Online check failed or server is slow/offline
      _isOnlineVerifying = false;

      if (hadLocalMatch) {
        // We already have the verified local copy from the downloaded server roster.
        // Mark as offline so UI can show the degraded-connectivity indicator.
        _isOfflineFallback = true;
        notifyListeners();
      } else {
        // Strict security rule: Unknown UUIDs CANNOT be checked in offline.
        // Offline check-in is strictly permitted only for tickets present in the downloaded roster.
        _state = ScanState.error;
        _isOfflineFallback = false;
        _currentRegistration = null;
        final isNotFoundOnServer = result != null &&
            result.errorMessage != null &&
            result.errorMessage!.toLowerCase().contains('not found in database');

        if (isNotFoundOnServer) {
          _errorTitle = 'Ticket Not Found';
          _errorMessage = result.errorMessage ??
              'The scanned ticket UUID does not exist on the server.';
        } else {
          _errorTitle = 'Cannot Verify Offline';
          _errorMessage =
              'This ticket is not in the downloaded attendee list, and the server is unreachable. Offline check-in is only permitted for tickets in the downloaded event list.';
        }
        M3Haptics.vibrateScanError();
        notifyListeners();
      }
    }
  }

  /// Attempts to re-query the live server for the currently scanned ticket
  Future<void> retryOnline() async {
    if (_scannedCode == null) return;
    final code = _scannedCode!;
    // If ticket is already on screen, keep sheet open while verifying
    if (_currentRegistration == null) {
      _state = ScanState.fetching;
    }
    _isOnlineVerifying = true;
    _isOfflineFallback = false;
    notifyListeners();

    final settings = getSettings();
    final timeout = onlineTimeoutThreshold ?? Duration(seconds: settings.timeoutSeconds);
    GraphQLResult<EventRegistration>? result;
    try {
      result = await graphQLService.getRegistration(code, settings).timeout(timeout);
    } catch (_) {
      result = null;
    }

    if (result != null && result.isSuccess && result.data != null) {
      final serverReg = result.data!;
      final cached = storageService != null
          ? await storageService!.findCachedRegistration(serverReg.id)
          : null;

      final pendingCount = queueService.getPendingEntriesCount(serverReg.id);
      final hasDeviceCheckIn = queueService.hasAnyDeviceCheckIn(serverReg.id);

      final reconciled = serverReg.reconcileWithLocal(
        cached: cached ?? _currentRegistration,
        pendingQueueEntries: pendingCount,
        hasDeviceCheckIn: hasDeviceCheckIn,
      );

      _currentRegistration = reconciled;
      _isOfflineFallback = false;
      _isOnlineVerifying = false;
      _state = ScanState.ticketFound;
      if (storageService != null) {
        await storageService!.saveReconciledRegistration(reconciled);
      }
    } else {
      // If we had a verified local match, retain it with the offline indicator
      if (_currentRegistration != null) {
        _isOfflineFallback = true;
        _isOnlineVerifying = false;
        _state = ScanState.ticketFound;
      } else {
        _isOfflineFallback = false;
        _isOnlineVerifying = false;
        _state = ScanState.error;
        _errorTitle = 'Verification Failed';
        _errorMessage = result?.errorMessage ?? 'Unable to verify ticket online.';
      }
    }
    notifyListeners();
  }

  Future<void> checkInCurrentTicket({int count = 1}) async {
    if (_currentRegistration == null) return;

    final reg = _currentRegistration!;
    final effectiveCount = count <= 0 ? 1 : count;

    // Record session check-in count for UI success feedback
    _lastCheckedInCount = effectiveCount;

    // Update local cache immediately so repeat scans show checked-in
    if (storageService != null) {
      await storageService!.updateCachedRegistrationCheckIn(
        reg.id,
        true,
        DateTime.now(),
        count: effectiveCount,
        fallbackRegistration: reg,
      );
    }

    // Enqueue for async background processing / sync
    await queueService.enqueueRegistration(reg, count: effectiveCount, manual: false);

    // Update current registration locally with decremented entries so preview sheet is immediately status aware!
    final newRemaining = (reg.remainingEntries - effectiveCount).clamp(0, reg.totalPartySize);
    final newGuestCheckIns = reg.didAttend
        ? (reg.guestCheckIns + effectiveCount).clamp(0, reg.guestCount)
        : (reg.guestCheckIns + (effectiveCount - 1)).clamp(0, reg.guestCount);

    _currentRegistration = reg.copyWith(
      remainingEntries: newRemaining,
      didAttend: true,
      guestCheckIns: newGuestCheckIns,
      checkInTime: reg.checkInTime ?? DateTime.now().toIso8601String(),
    );

    // Debounce the same code so camera doesn't immediately re-scan
    _lastScannedUuid = reg.id;
    _lastScannedAt = DateTime.now();
    final attendeeName = reg.user?.fullName ?? 'Attendee';
    _lastCheckedInFeedback = 'Checked in $attendeeName ($effectiveCount ${effectiveCount == 1 ? "entry" : "entries"})';
    notifyListeners();
  }

  void reset({bool keepRecentScanLock = false}) {
    _state = ScanState.ready;
    _scannedCode = null;
    _errorTitle = null;
    _errorMessage = null;
    _currentRegistration = null;
    _isEventMatched = true;
    _eventMatchMessage = null;
    // Only keep recent scan lock if explicitly requested or if a check-in just finished.
    // Otherwise (cancelled, dismissed error, or re-scanned), clear so user can re-scan immediately.
    if (!keepRecentScanLock && _lastCheckedInFeedback == null) {
      _lastScannedUuid = null;
      _lastScannedAt = null;
    }
    _duplicateScanNotice = null;
    _isOfflineFallback = false;
    _isOnlineVerifying = false;
    _lastCheckedInCount = null;
    _wasAlreadyAttendedOnScan = false;
    notifyListeners();
  }
}
