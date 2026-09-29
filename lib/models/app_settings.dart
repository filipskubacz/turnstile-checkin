class AppSettings {
  final String bearerToken;
  final String apiUrl;
  final List<String> activeEventIds;
  final int timeoutSeconds;
  final int autoRefreshMinutes;
  final bool isSafeMode; // Dry-run protection for live environment
  final bool isExpertMode; // Allows manual check-in from attendee roster
  final String imprint;

  static const String defaultApiUrl =
      String.fromEnvironment('GRAPHQL_ENDPOINT', defaultValue: '');
  static const String defaultImprint =
      String.fromEnvironment('IMPRINT', defaultValue: '');

  const AppSettings({
    this.bearerToken = '',
    this.apiUrl = defaultApiUrl,
    this.activeEventIds = const [],
    this.timeoutSeconds = 30,
    this.autoRefreshMinutes = 10,
    this.isSafeMode = false,
    this.isExpertMode = false,
    this.imprint = defaultImprint,
  });

  AppSettings copyWith({
    String? bearerToken,
    String? apiUrl,
    List<String>? activeEventIds,
    int? timeoutSeconds,
    int? autoRefreshMinutes,
    bool? isSafeMode,
    bool? isExpertMode,
    String? imprint,
  }) {
    return AppSettings(
      bearerToken: bearerToken ?? this.bearerToken,
      apiUrl: apiUrl ?? this.apiUrl,
      activeEventIds: activeEventIds ?? this.activeEventIds,
      timeoutSeconds: timeoutSeconds ?? this.timeoutSeconds,
      autoRefreshMinutes: autoRefreshMinutes ?? this.autoRefreshMinutes,
      isSafeMode: isSafeMode ?? this.isSafeMode,
      isExpertMode: isExpertMode ?? this.isExpertMode,
      imprint: imprint ?? this.imprint,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'bearerToken': bearerToken,
      'apiUrl': apiUrl,
      'activeEventIds': activeEventIds,
      'timeoutSeconds': timeoutSeconds,
      'autoRefreshMinutes': autoRefreshMinutes,
      'isSafeMode': isSafeMode,
      'isExpertMode': isExpertMode,
      'imprint': imprint,
    };
  }

  factory AppSettings.fromJson(Map<String, dynamic> json) {
    final rawUrl = json['apiUrl'] as String?;
    final resolvedUrl = (rawUrl == null || rawUrl.isEmpty)
        ? defaultApiUrl
        : rawUrl;

    final rawImprint = json['imprint'] as String?;
    final resolvedImprint = (rawImprint == null || rawImprint.isEmpty)
        ? defaultImprint
        : rawImprint;

    return AppSettings(
      bearerToken: json['bearerToken'] as String? ?? '',
      apiUrl: resolvedUrl,
      activeEventIds: (json['activeEventIds'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
      timeoutSeconds: json['timeoutSeconds'] as int? ?? 30,
      autoRefreshMinutes: json['autoRefreshMinutes'] as int? ?? 10,
      isSafeMode: json['isSafeMode'] as bool? ?? false,
      isExpertMode: json['isExpertMode'] as bool? ?? false,
      imprint: resolvedImprint,
    );
  }
}
