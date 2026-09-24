import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/app_settings.dart';
import '../models/queue_item.dart';
import '../models/registration.dart';
import 'graphql_service.dart';
import 'storage_service.dart';

class QueueService extends ChangeNotifier {
  final StorageService storageService;
  final GraphQLService graphQLService;
  AppSettings Function() getSettings;

  List<QueueItem> _items = [];
  bool _isProcessing = false;
  Timer? _retryTimer;

  List<QueueItem> get items => List.unmodifiable(_items);
  List<QueueItem> get completedItems =>
      _items.where((i) => i.status == QueueStatus.completed).toList();
  int get pendingCount =>
      _items.where((i) => i.status == QueueStatus.pending || i.status == QueueStatus.failedRetrying).length;
  int get failedManualCount =>
      _items.where((i) => i.status == QueueStatus.failedManual).length;
  int get completedCount =>
      _items.where((i) => i.status == QueueStatus.completed).length;

  /// Returns true if the registration currently has an in-flight or queued check-in
  bool hasPendingCheckIn(String registrationId) {
    return _items.any(
      (i) =>
          i.registrationId == registrationId &&
          (i.status == QueueStatus.pending ||
              i.status == QueueStatus.processing ||
              i.status == QueueStatus.failedRetrying),
    );
  }

  /// Returns the active (pending, processing, or retrying) queue item for a registration if any
  QueueItem? getActiveItem(String registrationId) {
    try {
      return _items.firstWhere(
        (i) =>
            i.registrationId == registrationId &&
            (i.status == QueueStatus.pending ||
                i.status == QueueStatus.processing ||
                i.status == QueueStatus.failedRetrying),
      );
    } catch (_) {
      return null;
    }
  }

  /// Returns the total pending entries count for this registration that have not yet finished syncing
  int getPendingEntriesCount(String registrationId) {
    int total = 0;
    for (final item in _items) {
      if (item.registrationId == registrationId &&
          (item.status == QueueStatus.pending ||
              item.status == QueueStatus.processing ||
              item.status == QueueStatus.failedRetrying)) {
        total += (item.entriesCount - item.entriesProcessed);
      }
    }
    return total;
  }

  /// Returns the total entries checked in on this device across all queue items (pending, processing, or completed)
  int getTotalDeviceAdmittedEntries(String registrationId) {
    int total = 0;
    for (final item in _items) {
      if (item.registrationId == registrationId &&
          item.status != QueueStatus.failedManual) {
        total += item.entriesCount;
      }
    }
    return total;
  }

  /// Returns true if this device has any check-in record for this registration (pending, processing, or completed)
  bool hasAnyDeviceCheckIn(String registrationId) {
    return _items.any(
      (i) =>
          i.registrationId == registrationId &&
          i.status != QueueStatus.failedManual,
    );
  }

  QueueService({
    required this.storageService,
    required this.graphQLService,
    required this.getSettings,
  });

  Future<void> init() async {
    _items = await storageService.loadQueue();
    notifyListeners();
    // Resume any pending items on startup
    _processNext();
  }

  Future<QueueItem> enqueueRegistration(
    EventRegistration reg, {
    int count = 1,
    bool manual = false,
  }) async {
    final item = QueueItem(
      id: '${DateTime.now().microsecondsSinceEpoch}',
      registrationId: reg.id,
      attendeeName: reg.user?.fullName ?? 'Guest',
      attendeePicture: reg.user?.picture,
      eventTitle: reg.event?.title ?? 'Event',
      eventId: reg.event?.id ?? '',
      enqueuedAt: DateTime.now(),
      status: QueueStatus.pending,
      rawRegistration: reg.toJson(),
      entriesCount: count,
      entriesProcessed: 0,
      manual: manual,
    );

    _items.insert(0, item);
    await storageService.saveQueue(_items);
    notifyListeners();

    _processNext();
    return item;
  }

  void _processNext() async {
    if (_isProcessing) return;

    final targetIndex = _items.indexWhere(
      (i) => i.status == QueueStatus.pending || i.status == QueueStatus.failedRetrying,
    );

    if (targetIndex == -1) return;

    _isProcessing = true;
    final item = _items[targetIndex];
    final updatedItem = item.copyWith(
      status: QueueStatus.processing,
      lastAttemptAt: DateTime.now(),
    );
    
    // Always look up by ID to prevent index shifting bugs on re-entrant enqueue
    final idx = _items.indexWhere((i) => i.id == item.id);
    if (idx != -1) {
      _items[idx] = updatedItem;
    }
    notifyListeners();

    final settings = getSettings();
    final needed = item.entriesCount - item.entriesProcessed;
    var currentProcessed = item.entriesProcessed;
    String? failureMessage;

    for (int i = 0; i < needed; i++) {
      final result = await graphQLService.useRegistrationEntry(
        item.registrationId,
        settings,
        manual: item.manual,
      );

      if (result.isSuccess) {
        currentProcessed++;

        // Update local cached registration with server's authoritative data if returned
        if (result.data != null && result.data!['simulated'] != true) {
          final cached = await storageService.findCachedRegistration(item.registrationId);
          if (cached != null) {
            final entryData = result.data!;
            final updatedCached = cached.copyWith(
              remainingEntries: (entryData['remainingEntries'] as num?)?.toInt() ?? cached.remainingEntries,
              guestCheckIns: (entryData['guestCheckIns'] as num?)?.toInt() ?? cached.guestCheckIns,
              checkInTime: entryData['checkInTime']?.toString() ?? cached.checkInTime,
              didAttend: true,
            );
            await storageService.saveReconciledRegistration(updatedCached);
          }
        }

        final curIdx = _items.indexWhere((it) => it.id == item.id);
        if (curIdx != -1) {
          _items[curIdx] = updatedItem.copyWith(
            entriesProcessed: currentProcessed,
          );
          await storageService.saveQueue(_items);
          notifyListeners();
        }
      } else {
        failureMessage = result.errorMessage ?? 'Check-in failed';
        break;
      }
    }

    final finalIdx = _items.indexWhere((it) => it.id == item.id);

    if (currentProcessed >= item.entriesCount) {
      // Check-in succeeded
      if (finalIdx != -1) {
        _items[finalIdx] = updatedItem.copyWith(
          status: QueueStatus.completed,
          completedAt: DateTime.now(),
          entriesProcessed: currentProcessed,
          lastError: null,
        );
      }

      await storageService.saveQueue(_items);
      notifyListeners();

      _isProcessing = false;
      _processNext();
    } else {
      // Check-in failed
      final newRetryCount = item.retryCount + 1;
      final errorMessage = failureMessage ?? 'Unknown check-in error';

      if (newRetryCount >= 3) {
        // Exceeded 3 retries: requires manual intervention
        if (finalIdx != -1) {
          _items[finalIdx] = updatedItem.copyWith(
            status: QueueStatus.failedManual,
            retryCount: newRetryCount,
            entriesProcessed: currentProcessed,
            lastError: errorMessage,
          );
        }
        await storageService.saveQueue(_items);
        notifyListeners();

        _isProcessing = false;
        _processNext();
      } else {
        // Automatic retry with exponential backoff (2s, 4s)
        if (finalIdx != -1) {
          _items[finalIdx] = updatedItem.copyWith(
            status: QueueStatus.failedRetrying,
            retryCount: newRetryCount,
            entriesProcessed: currentProcessed,
            lastError: errorMessage,
          );
        }
        await storageService.saveQueue(_items);
        notifyListeners();

        _isProcessing = false;
        final backoffSeconds = newRetryCount * 2;
        _retryTimer?.cancel();
        _retryTimer = Timer(Duration(seconds: backoffSeconds), () {
          _processNext();
        });
      }
    }
  }

  Future<void> retryItem(String itemId) async {
    final index = _items.indexWhere((i) => i.id == itemId);
    if (index != -1) {
      _items[index] = _items[index].copyWith(
        status: QueueStatus.pending,
        retryCount: 0,
        lastError: null,
      );
      await storageService.saveQueue(_items);
      notifyListeners();
      _processNext();
    }
  }

  Future<void> retryAllFailed() async {
    for (int i = 0; i < _items.length; i++) {
      if (_items[i].status == QueueStatus.failedManual ||
          _items[i].status == QueueStatus.failedRetrying) {
        _items[i] = _items[i].copyWith(
          status: QueueStatus.pending,
          retryCount: 0,
          lastError: null,
        );
      }
    }
    await storageService.saveQueue(_items);
    notifyListeners();
    _processNext();
  }

  Future<void> removeItem(String itemId) async {
    _items.removeWhere((i) => i.id == itemId);
    await storageService.saveQueue(_items);
    notifyListeners();
  }

  Future<void> clearCompleted() async {
    _items.removeWhere((i) => i.status == QueueStatus.completed);
    await storageService.saveQueue(_items);
    notifyListeners();
  }

  @override
  void dispose() {
    _retryTimer?.cancel();
    super.dispose();
  }
}
