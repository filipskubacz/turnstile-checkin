import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/app_settings.dart';
import '../models/queue_item.dart';
import '../models/registration.dart';

class StorageService {
  static const String _settingsKey = 'turnstile_app_settings';
  static const String _queueKey = 'turnstile_queue_items';
  static const String _cacheKeyPrefix = 'turnstile_reg_cache_';
  static const String _cachedEventAttendeesKey = 'turnstile_cached_event_attendees_';
  static const String _lastRefreshKey = 'turnstile_last_attendee_refresh_';

  final SharedPreferences _prefs;

  StorageService(this._prefs);

  SharedPreferences get prefs => _prefs;

  static Future<StorageService> init() async {
    final prefs = await SharedPreferences.getInstance();
    return StorageService(prefs);
  }

  // --- Settings ---
  AppSettings loadSettings() {
    final jsonStr = _prefs.getString(_settingsKey);
    if (jsonStr == null) return const AppSettings();
    try {
      final map = jsonDecode(jsonStr) as Map<String, dynamic>;
      return AppSettings.fromJson(map);
    } catch (e) {
      debugPrint('Error loading settings: $e');
      return const AppSettings();
    }
  }

  Future<void> saveSettings(AppSettings settings) async {
    final jsonStr = jsonEncode(settings.toJson());
    await _prefs.setString(_settingsKey, jsonStr);
  }

  // --- Queue Items ---
  Future<List<QueueItem>> loadQueue() async {
    final str = _prefs.getString(_queueKey);
    if (str != null && str.isNotEmpty) {
      try {
        final list = jsonDecode(str) as List<dynamic>;
        return list.map((e) => QueueItem.fromJson(e as Map<String, dynamic>)).toList();
      } catch (e) {
        debugPrint('Error decoding queue: $e');
      }
    }
    return [];
  }

  Future<void> saveQueue(List<QueueItem> items) async {
    final jsonStr = jsonEncode(items.map((i) => i.toJson()).toList());
    await _prefs.setString(_queueKey, jsonStr);
  }

  // --- Registration Cache ---
  Future<void> cacheRegistration(EventRegistration reg) async {
    await _prefs.setString('$_cacheKeyPrefix${reg.id}', jsonEncode(reg.toJson()));
  }

  EventRegistration? getCachedRegistration(String id) {
    final jsonStr = _prefs.getString('$_cacheKeyPrefix$id');
    if (jsonStr == null) return null;
    try {
      final map = jsonDecode(jsonStr) as Map<String, dynamic>;
      return EventRegistration.fromJson(map);
    } catch (e) {
      return null;
    }
  }

  // --- Event Attendees Offline Cache ---
  Future<void> saveCachedEventAttendees(EventDetails event, {bool reindexIndividuals = true}) async {
    final jsonStr = jsonEncode(event.toJson());
    await _prefs.setString('$_cachedEventAttendeesKey${event.id}', jsonStr);
    await _prefs.setString(_cachedEventAttendeesKey, jsonStr);
    await saveLastAttendeeRefreshTime(DateTime.now(), eventId: event.id);

    if (reindexIndividuals) {
      for (final reg in event.participantRegistrations) {
        await cacheRegistration(reg);
      }
      for (final org in event.organizerRegistrations) {
        await cacheRegistration(org);
      }
    }
  }

  Future<EventDetails?> loadCachedEvent({String? eventId}) async {
    final key = eventId != null
        ? '$_cachedEventAttendeesKey$eventId'
        : _cachedEventAttendeesKey;
    final jsonStr = _prefs.getString(key);
    if (jsonStr != null && jsonStr.isNotEmpty) {
      try {
        final map = jsonDecode(jsonStr) as Map<String, dynamic>;
        return EventDetails.fromJson(map);
      } catch (e) {
        debugPrint('Error decoding cached event: $e');
      }
    }
    return null;
  }

  Future<EventRegistration?> findCachedRegistration(String registrationId) async {
    final direct = getCachedRegistration(registrationId);
    if (direct != null) return direct;

    final event = await loadCachedEvent();
    if (event != null) {
      for (final r in event.participantRegistrations) {
        if (r.id == registrationId) return r;
      }
      for (final org in event.organizerRegistrations) {
        if (org.id == registrationId) return org;
      }
    }
    return null;
  }

  Future<void> updateCachedRegistrationCheckIn(
    String registrationId,
    bool didAttend,
    DateTime checkInTime, {
    int count = 1,
    EventRegistration? fallbackRegistration,
  }) async {
    var reg = await findCachedRegistration(registrationId);
    reg ??= fallbackRegistration;

    if (reg != null) {
      final effectiveCount = count <= 0 ? 1 : count;
      final newRemaining = (reg.remainingEntries - effectiveCount).clamp(0, reg.totalPartySize);
      final newDidAttend = reg.didAttend || didAttend;
      final newGuestCheckIns = reg.didAttend
          ? (reg.guestCheckIns + effectiveCount).clamp(0, reg.guestCount)
          : (reg.guestCheckIns + (effectiveCount - 1)).clamp(0, reg.guestCount);

      final updated = reg.copyWith(
        didAttend: newDidAttend,
        checkInTime: reg.checkInTime ?? checkInTime.toIso8601String(),
        guestCheckIns: newGuestCheckIns,
        remainingEntries: newRemaining,
      );
      await cacheRegistration(updated);

      final event = await loadCachedEvent(eventId: reg.event?.id);
      if (event != null) {
        final updatedParticipants = event.participantRegistrations.map((p) {
          if (p.id == registrationId) {
            return updated;
          }
          return p;
        }).toList();

        final updatedEvent = EventDetails(
          id: event.id,
          title: event.title,
          icon: event.icon,
          start: event.start,
          end: event.end,
          participantLimit: event.participantLimit,
          participantRegistrationCount: event.participantRegistrationCount,
          totalRegisteredCount: event.totalRegisteredCount,
          participantsAttended:
              event.participantsAttended + (newDidAttend && !reg.didAttend ? 1 : 0),
          participantRegistrations: updatedParticipants,
          organizerRegistrations: event.organizerRegistrations,
        );
        await saveCachedEventAttendees(updatedEvent, reindexIndividuals: false);
      }
    }
  }

  /// Persists a reconciled registration into both individual direct cache and the cached event attendees list.
  Future<void> saveReconciledRegistration(EventRegistration reg) async {
    await cacheRegistration(reg);

    final event = await loadCachedEvent(eventId: reg.event?.id);
    if (event != null) {
      bool found = false;
      final updatedParticipants = event.participantRegistrations.map((p) {
        if (p.id == reg.id) {
          found = true;
          return reg;
        }
        return p;
      }).toList();

      final updatedOrganizers = event.organizerRegistrations.map((o) {
        if (o.id == reg.id) {
          found = true;
          return reg;
        }
        return o;
      }).toList();

      if (found) {
        final attendedCount = updatedParticipants.where((p) => p.didAttend).length;
        final updatedEvent = EventDetails(
          id: event.id,
          title: event.title,
          icon: event.icon,
          start: event.start,
          end: event.end,
          participantLimit: event.participantLimit,
          participantRegistrationCount: event.participantRegistrationCount,
          totalRegisteredCount: event.totalRegisteredCount,
          participantsAttended: attendedCount,
          participantRegistrations: updatedParticipants,
          organizerRegistrations: updatedOrganizers,
        );
        await saveCachedEventAttendees(updatedEvent, reindexIndividuals: false);
      }
    }
  }

  DateTime? getLastAttendeeRefreshTime({String? eventId}) {
    final key = eventId != null ? '$_lastRefreshKey$eventId' : _lastRefreshKey;
    final iso = _prefs.getString(key);
    if (iso == null) return null;
    return DateTime.tryParse(iso);
  }

  Future<void> saveLastAttendeeRefreshTime(DateTime dt, {String? eventId}) async {
    final key = eventId != null ? '$_lastRefreshKey$eventId' : _lastRefreshKey;
    await _prefs.setString(key, dt.toIso8601String());
    await _prefs.setString(_lastRefreshKey, dt.toIso8601String());
  }
}
