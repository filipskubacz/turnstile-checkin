import 'package:flutter/foundation.dart';
import '../models/app_settings.dart';
import '../services/storage_service.dart';

class SettingsProvider extends ChangeNotifier {
  final StorageService storageService;
  late AppSettings _settings;

  AppSettings get settings => _settings;

  SettingsProvider(this.storageService) {
    _settings = storageService.loadSettings();
  }

  Future<void> updateSettings(AppSettings newSettings) async {
    _settings = newSettings;
    await storageService.saveSettings(_settings);
    notifyListeners();
  }

  Future<void> setBearerToken(String token) async {
    await updateSettings(_settings.copyWith(bearerToken: token.trim()));
  }

  Future<void> setApiUrl(String url) async {
    await updateSettings(_settings.copyWith(apiUrl: url.trim()));
  }

  Future<void> setTimeoutSeconds(int seconds) async {
    await updateSettings(_settings.copyWith(timeoutSeconds: seconds));
  }

  Future<void> setAutoRefreshMinutes(int minutes) async {
    await updateSettings(_settings.copyWith(autoRefreshMinutes: minutes));
  }

  Future<void> setSafeMode(bool enabled) async {
    await updateSettings(_settings.copyWith(isSafeMode: enabled));
  }

  Future<void> setExpertMode(bool enabled) async {
    await updateSettings(_settings.copyWith(isExpertMode: enabled));
  }

  Future<void> addEventId(String eventId) async {
    final cleanId = eventId.trim();
    if (cleanId.isEmpty || _settings.activeEventIds.contains(cleanId)) return;
    final updated = List<String>.from(_settings.activeEventIds)..add(cleanId);
    await updateSettings(_settings.copyWith(activeEventIds: updated));
  }

  Future<void> removeEventId(String eventId) async {
    final updated = List<String>.from(_settings.activeEventIds)..remove(eventId);
    await updateSettings(_settings.copyWith(activeEventIds: updated));
  }
}
