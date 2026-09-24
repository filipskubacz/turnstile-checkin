class AppSettings {
  final String bearerToken;
  final String apiUrl;
  final List<String> activeEventIds;
  final int timeoutSeconds;
  final int autoRefreshMinutes;
  final bool isSafeMode; // Dry-run protection for live environment
  final bool isExpertMode; // Allows manual check-in from attendee roster

  static const String defaultApiUrl =
      String.fromEnvironment('GRAPHQL_ENDPOINT', defaultValue: '');

  const AppSettings({
    this.bearerToken = '',
    this.apiUrl = defaultApiUrl,
    this.activeEventIds = const [],
    this.timeoutSeconds = 30,
    this.autoRefreshMinutes = 10,
    this.isSafeMode = true,
    this.isExpertMode = false,
  });

  AppSettings copyWith({
    String? bearerToken,
    String? apiUrl,
    List<String>? activeEventIds,
    int? timeoutSeconds,
    int? autoRefreshMinutes,
    bool? isSafeMode,
    bool? isExpertMode,
  }) {
    return AppSettings(
      bearerToken: bearerToken ?? this.bearerToken,
      apiUrl: apiUrl ?? this.apiUrl,
      activeEventIds: activeEventIds ?? this.activeEventIds,
      timeoutSeconds: timeoutSeconds ?? this.timeoutSeconds,
      autoRefreshMinutes: autoRefreshMinutes ?? this.autoRefreshMinutes,
      isSafeMode: isSafeMode ?? this.isSafeMode,
      isExpertMode: isExpertMode ?? this.isExpertMode,
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
    };
  }

  factory AppSettings.fromJson(Map<String, dynamic> json) {
    final rawUrl = json['apiUrl'] as String?;
    final resolvedUrl = (rawUrl == null || rawUrl.isEmpty)
        ? defaultApiUrl
        : rawUrl;

    return AppSettings(
      bearerToken: json['bearerToken'] as String? ?? '',
      apiUrl: resolvedUrl,
      activeEventIds: (json['activeEventIds'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
      timeoutSeconds: json['timeoutSeconds'] as int? ?? 30,
      autoRefreshMinutes: json['autoRefreshMinutes'] as int? ?? 10,
      isSafeMode: json['isSafeMode'] as bool? ?? true,
      isExpertMode: json['isExpertMode'] as bool? ?? false,
    );
  }
}
