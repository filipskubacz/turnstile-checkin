import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/app_settings.dart';
import '../models/queue_item.dart';
import '../models/registration.dart';
import '../services/graphql_service.dart';
import '../services/queue_service.dart';
import '../services/storage_service.dart';

class AttendeesProvider extends ChangeNotifier {
  final StorageService storageService;
  final GraphQLService? graphQLService;
  final AppSettings Function()? getSettings;
  final QueueService? queueService;

  List<EventRegistration> _cachedRegistrations = [];
  EventDetails? _currentEvent;
  String _searchQuery = '';
  bool _isRefreshing = false;
  String? _refreshError;
  DateTime? _lastRefreshedAt;
  Timer? _backgroundTimer;

  AttendeesProvider({
    required this.storageService,
    this.graphQLService,
    this.getSettings,
    this.queueService,
  }) {
    queueService?.addListener(_onQueueChanged);
  }

  void _onQueueChanged() {
    notifyListeners();
  }

  EventDetails? get currentEvent => _currentEvent;
  bool get isRefreshing => _isRefreshing;
  String? get refreshError => _refreshError;
  DateTime? get lastRefreshedAt => _lastRefreshedAt;
  int get totalRegisteredCount =>
      _currentEvent?.totalRegisteredCount ?? _cachedRegistrations.length;
  int get attendedCount {
    if (queueService == null) {
      return _currentEvent?.participantsAttended ??
          _cachedRegistrations.where((r) => r.didAttend).length;
    }
    return _cachedRegistrations.where((r) {
      return r.didAttend || queueService!.hasPendingCheckIn(r.id);
    }).length;
  }

  EventRegistration _reconcileRegistration(EventRegistration r) {
    if (queueService == null) return r;
    final pendingCount = queueService!.getPendingEntriesCount(r.id);
    final activeItem = queueService!.getActiveItem(r.id);
    if (pendingCount > 0 || activeItem != null) {
      final effectiveRemaining = (r.remainingEntries - pendingCount).clamp(0, r.totalPartySize);
      return r.copyWith(
        remainingEntries: effectiveRemaining,
        didAttend: true,
      );
    }
    return r;
  }

  /// Combined / active attendees list matching search query
  List<EventRegistration> get registrations {
    final list = _cachedRegistrations.map(_reconcileRegistration).toList();
    if (_searchQuery.trim().isEmpty) {
      return List.unmodifiable(list);
    }
    final q = _searchQuery.toLowerCase().trim();
    return list.where((r) {
      final name = (r.user?.displayName ?? '').toLowerCase();
      final id = r.id.toLowerCase();
      final email = (r.user?.email ?? '').toLowerCase();
      final esn = (r.user?.esnCardNumber ?? '').toLowerCase();
      final eventTitle = (r.event?.title ?? '').toLowerCase();
      return name.contains(q) ||
          id.contains(q) ||
          email.contains(q) ||
          esn.contains(q) ||
          eventTitle.contains(q);
    }).toList();
  }

  /// Session check-in history from queue
  List<QueueItem> get sessionAttendees {
    final list = queueService?.completedItems ?? const [];
    if (_searchQuery.trim().isEmpty) return list;
    final q = _searchQuery.toLowerCase().trim();
    return list.where((item) {
      final name = item.attendeeName.toLowerCase();
      final id = item.registrationId.toLowerCase();
      final event = item.eventTitle.toLowerCase();
      final esn = (item.rawRegistration?['user']?['esnCardNumber']?.toString() ?? '').toLowerCase();
      return name.contains(q) || id.contains(q) || event.contains(q) || esn.contains(q);
    }).toList();
  }

  Future<void> init({bool enableBackgroundTimer = true}) async {
    // 1. Load locally cached event and attendee list immediately (instant offline startup)
    _currentEvent = await storageService.loadCachedEvent();
    if (_currentEvent != null) {
      _cachedRegistrations = _currentEvent!.participantRegistrations;
    }
    _lastRefreshedAt = storageService.getLastAttendeeRefreshTime();
    notifyListeners();

    if (enableBackgroundTimer) {
      // 3. Trigger initial refresh in background if network is available
      unawaited(refreshAttendees());

      // 4. Setup periodic background refresh
      startBackgroundTimer();
    }
  }

  void startBackgroundTimer() {
    _backgroundTimer?.cancel();
    final minutes = getSettings?.call().autoRefreshMinutes ?? 10;
    _backgroundTimer = Timer.periodic(Duration(minutes: minutes), (_) {
      refreshAttendees();
    });
  }

  Future<void> refresh() async {
    await refreshAttendees(force: true);
  }

  /// Reloads local cache from storage without triggering a network fetch
  Future<void> reloadFromStorage() async {
    _currentEvent = await storageService.loadCachedEvent();
    if (_currentEvent != null) {
      _cachedRegistrations = _currentEvent!.participantRegistrations;
    }
    _lastRefreshedAt = storageService.getLastAttendeeRefreshTime();
    notifyListeners();
  }

  /// Refreshes the attendee list from the GraphQL backend using loadEventForRunning
  Future<void> refreshAttendees({bool force = false}) async {
    if (_isRefreshing) return;
    if (graphQLService == null || getSettings == null) return;

    final settings = getSettings!();
    // Use active event ID if configured, or fallback to current cached event ID
    final activeEventIds = settings.activeEventIds;
    final targetEventId = activeEventIds.isNotEmpty
        ? activeEventIds.first
        : _currentEvent?.id;

    if (targetEventId == null || targetEventId.trim().isEmpty) {
      // No event ID configured; can't query backend
      return;
    }

    _isRefreshing = true;
    _refreshError = null;
    notifyListeners();

    try {
      final result =
          await graphQLService!.loadEventForRunning(targetEventId, settings);

      if (result.isSuccess && result.data != null) {
        final event = result.data!;

        // Reconcile server data with local cache and queue check-ins to prevent overwriting local attendees
        final reconciledParticipants = event.participantRegistrations.map((serverReg) {
          final pendingCount = queueService?.getPendingEntriesCount(serverReg.id) ?? 0;
          final hasDeviceCheckIn = queueService?.hasAnyDeviceCheckIn(serverReg.id) ?? false;
          final cached = storageService.getCachedRegistration(serverReg.id);
          return serverReg.reconcileWithLocal(
            cached: cached,
            pendingQueueEntries: pendingCount,
            hasDeviceCheckIn: hasDeviceCheckIn,
          );
        }).toList();

        final reconciledOrganizers = event.organizerRegistrations.map((serverReg) {
          final pendingCount = queueService?.getPendingEntriesCount(serverReg.id) ?? 0;
          final hasDeviceCheckIn = queueService?.hasAnyDeviceCheckIn(serverReg.id) ?? false;
          final cached = storageService.getCachedRegistration(serverReg.id);
          return serverReg.reconcileWithLocal(
            cached: cached,
            pendingQueueEntries: pendingCount,
            hasDeviceCheckIn: hasDeviceCheckIn,
          );
        }).toList();

        final attendedCount = reconciledParticipants.where((p) => p.didAttend).length;

        final reconciledEvent = EventDetails(
          id: event.id,
          title: event.title,
          icon: event.icon,
          start: event.start,
          end: event.end,
          participantLimit: event.participantLimit,
          participantRegistrationCount: event.participantRegistrationCount,
          totalRegisteredCount: event.totalRegisteredCount,
          participantsAttended: attendedCount,
          participantRegistrations: reconciledParticipants,
          organizerRegistrations: reconciledOrganizers,
        );

        _currentEvent = reconciledEvent;
        _cachedRegistrations = reconciledParticipants;
        _lastRefreshedAt = DateTime.now();
        _refreshError = null;

        // Persist to local offline storage cache
        await storageService.saveCachedEventAttendees(reconciledEvent);
      } else {
        _refreshError = result.errorMessage ?? 'Server error';
        // Note: we leave _cachedRegistrations and _currentEvent intact so offline usage is preserved!
      }
    } catch (e) {
      _refreshError = 'Network error: $e';
    } finally {
      _isRefreshing = false;
      notifyListeners();
    }
  }

  void setSearchQuery(String query) {
    _searchQuery = query;
    notifyListeners();
  }

  Future<void> clearHistory() async {
    await queueService?.clearCompleted();
    notifyListeners();
  }

  @override
  void dispose() {
    _backgroundTimer?.cancel();
    queueService?.removeListener(_onQueueChanged);
    super.dispose();
  }
}
