enum QueueStatus {
  pending,
  processing,
  completed,
  failedRetrying,
  failedManual;

  String get label {
    switch (this) {
      case QueueStatus.pending:
        return 'Pending';
      case QueueStatus.processing:
        return 'Processing';
      case QueueStatus.completed:
        return 'Completed';
      case QueueStatus.failedRetrying:
        return 'Retrying';
      case QueueStatus.failedManual:
        return 'Manual Retry Required';
    }
  }
}

class QueueItem {
  final String id;
  final String registrationId;
  final String attendeeName;
  final String? attendeePicture;
  final String eventTitle;
  final String eventId;
  final DateTime enqueuedAt;
  final QueueStatus status;
  final int retryCount;
  final String? lastError;
  final DateTime? lastAttemptAt;
  final DateTime? completedAt;
  final Map<String, dynamic>? rawRegistration;
  final int entriesCount;
  final int entriesProcessed;
  final bool manual;

  const QueueItem({
    required this.id,
    required this.registrationId,
    required this.attendeeName,
    this.attendeePicture,
    required this.eventTitle,
    required this.eventId,
    required this.enqueuedAt,
    this.status = QueueStatus.pending,
    this.retryCount = 0,
    this.lastError,
    this.lastAttemptAt,
    this.completedAt,
    this.rawRegistration,
    this.entriesCount = 1,
    this.entriesProcessed = 0,
    this.manual = false,
  });

  QueueItem copyWith({
    String? id,
    String? registrationId,
    String? attendeeName,
    String? attendeePicture,
    String? eventTitle,
    String? eventId,
    DateTime? enqueuedAt,
    QueueStatus? status,
    int? retryCount,
    String? lastError,
    DateTime? lastAttemptAt,
    DateTime? completedAt,
    Map<String, dynamic>? rawRegistration,
    int? entriesCount,
    int? entriesProcessed,
    bool? manual,
  }) {
    return QueueItem(
      id: id ?? this.id,
      registrationId: registrationId ?? this.registrationId,
      attendeeName: attendeeName ?? this.attendeeName,
      attendeePicture: attendeePicture ?? this.attendeePicture,
      eventTitle: eventTitle ?? this.eventTitle,
      eventId: eventId ?? this.eventId,
      enqueuedAt: enqueuedAt ?? this.enqueuedAt,
      status: status ?? this.status,
      retryCount: retryCount ?? this.retryCount,
      lastError: lastError ?? this.lastError,
      lastAttemptAt: lastAttemptAt ?? this.lastAttemptAt,
      completedAt: completedAt ?? this.completedAt,
      rawRegistration: rawRegistration ?? this.rawRegistration,
      entriesCount: entriesCount ?? this.entriesCount,
      entriesProcessed: entriesProcessed ?? this.entriesProcessed,
      manual: manual ?? this.manual,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'registrationId': registrationId,
        'attendeeName': attendeeName,
        'attendeePicture': attendeePicture,
        'eventTitle': eventTitle,
        'eventId': eventId,
        'enqueuedAt': enqueuedAt.toIso8601String(),
        'status': status.name,
        'retryCount': retryCount,
        'lastError': lastError,
        'lastAttemptAt': lastAttemptAt?.toIso8601String(),
        'completedAt': completedAt?.toIso8601String(),
        'rawRegistration': rawRegistration,
        'entriesCount': entriesCount,
        'entriesProcessed': entriesProcessed,
        'manual': manual,
      };

  factory QueueItem.fromJson(Map<String, dynamic> json) {
    return QueueItem(
      id: json['id'] as String? ?? '',
      registrationId: json['registrationId'] as String? ?? '',
      attendeeName: json['attendeeName'] as String? ?? 'Unknown Attendee',
      attendeePicture: json['attendeePicture'] as String?,
      eventTitle: json['eventTitle'] as String? ?? 'Unknown Event',
      eventId: json['eventId'] as String? ?? '',
      enqueuedAt: json['enqueuedAt'] != null
          ? DateTime.tryParse(json['enqueuedAt'].toString()) ?? DateTime.now()
          : DateTime.now(),
      status: QueueStatus.values.firstWhere(
        (s) => s.name == json['status'],
        orElse: () => QueueStatus.pending,
      ),
      retryCount: json['retryCount'] as int? ?? 0,
      lastError: json['lastError'] as String?,
      lastAttemptAt: json['lastAttemptAt'] != null
          ? DateTime.tryParse(json['lastAttemptAt'].toString())
          : null,
      completedAt: json['completedAt'] != null
          ? DateTime.tryParse(json['completedAt'].toString())
          : null,
      rawRegistration: json['rawRegistration'] as Map<String, dynamic>?,
      entriesCount: (json['entriesCount'] as num?)?.toInt() ?? 1,
      entriesProcessed: (json['entriesProcessed'] as num?)?.toInt() ?? 0,
      manual: json['manual'] as bool? ?? false,
    );
  }
}
