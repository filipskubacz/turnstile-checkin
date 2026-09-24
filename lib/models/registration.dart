class EventInfo {
  final String id;
  final String title;
  final String? icon;

  const EventInfo({
    required this.id,
    required this.title,
    this.icon,
  });

  factory EventInfo.fromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return const EventInfo(id: '', title: 'Unknown Event');
    }
    return EventInfo(
      id: json['id']?.toString() ?? '',
      title: json['title']?.toString() ?? 'Unnamed Event',
      icon: json['icon']?.toString(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'icon': icon,
      };
}

class UserInfo {
  final String id;
  final String? fullName;
  final String? lastName;
  final String? picture;
  final String? email;
  final String? phone;
  final String? communicationEmail;
  final String? esnCardNumber;
  final String? esnCardValidUntil;

  const UserInfo({
    required this.id,
    this.fullName,
    this.lastName,
    this.picture,
    this.email,
    this.phone,
    this.communicationEmail,
    this.esnCardNumber,
    this.esnCardValidUntil,
  });

  String get displayName {
    if (fullName != null && fullName!.isNotEmpty) return fullName!;
    if (lastName != null && lastName!.isNotEmpty) return lastName!;
    if (email != null && email!.isNotEmpty) return email!;
    return 'Anonymous Attendee';
  }

  factory UserInfo.fromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return const UserInfo(id: '');
    }
    return UserInfo(
      id: json['id']?.toString() ?? '',
      fullName: json['fullName']?.toString(),
      lastName: json['lastName']?.toString(),
      picture: json['picture']?.toString(),
      email: json['email']?.toString(),
      phone: json['phone']?.toString(),
      communicationEmail: json['communicationEmail']?.toString(),
      esnCardNumber: json['esnCardNumber']?.toString(),
      esnCardValidUntil: json['esnCardValidUntil']?.toString(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'fullName': fullName,
        'lastName': lastName,
        'picture': picture,
        'email': email,
        'phone': phone,
        'communicationEmail': communicationEmail,
        'esnCardNumber': esnCardNumber,
        'esnCardValidUntil': esnCardValidUntil,
      };
}

num? _parseNum(dynamic val) =>
    val is num ? val : (val is String ? num.tryParse(val.trim()) : null);

int? _parseInt(dynamic val) {
  if (val is int) return val;
  if (val is num) return val.toInt();
  if (val is String) return int.tryParse(val.trim()) ?? num.tryParse(val.trim())?.toInt();
  return null;
}

class RegistrationTransaction {
  final String? id;
  final String? status;
  final String? direction;
  final num? amount;
  final String? type;
  final String? subject;
  final String? stripePaymentId;
  final String? stripePaymentStatus;

  const RegistrationTransaction({
    this.id,
    this.status,
    this.direction,
    this.amount,
    this.type,
    this.subject,
    this.stripePaymentId,
    this.stripePaymentStatus,
  });

  bool get isPending => status?.toUpperCase() == 'PENDING';
  bool get isStripeIncomplete => stripePaymentStatus?.toLowerCase() == 'incomplete';
  bool get isUnpaid => isPending || isStripeIncomplete;

  factory RegistrationTransaction.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const RegistrationTransaction();
    final stripe = json['stripePayment'] as Map<String, dynamic>?;
    return RegistrationTransaction(
      id: json['id']?.toString(),
      status: json['status']?.toString(),
      direction: json['direction']?.toString(),
      amount: _parseNum(json['amount']),
      type: json['type']?.toString(),
      subject: json['subject']?.toString(),
      stripePaymentId: stripe?['id']?.toString(),
      stripePaymentStatus: stripe?['status']?.toString(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'status': status,
        'direction': direction,
        'amount': amount,
        'type': type,
        'subject': subject,
        if (stripePaymentId != null || stripePaymentStatus != null)
          'stripePayment': {
            'id': stripePaymentId,
            'status': stripePaymentStatus,
          },
      };
}

class RegistrationUsageLog {
  final String? timestamp;
  final String? actorId;
  final bool? manual;
  final String? note;

  const RegistrationUsageLog({
    this.timestamp,
    this.actorId,
    this.manual,
    this.note,
  });

  factory RegistrationUsageLog.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const RegistrationUsageLog();
    return RegistrationUsageLog(
      timestamp: json['timestamp']?.toString(),
      actorId: json['actorId']?.toString(),
      manual: json['manual'] as bool?,
      note: json['note']?.toString(),
    );
  }

  Map<String, dynamic> toJson() => {
        'timestamp': timestamp,
        'actorId': actorId,
        'manual': manual,
        'note': note,
      };
}

class EventRegistration {
  final String id;
  final String type;
  final String status;
  final bool didAttend;
  final String? checkInTime;
  final int guestCount;
  final num? guestUnitPrice;
  final int guestCheckIns;
  final int totalPartySize;
  final int remainingEntries;
  final EventInfo? event;
  final UserInfo? user;
  final List<RegistrationTransaction> transactions;
  final List<RegistrationUsageLog> usageLog;
  final Map<String, dynamic> rawJson;

  const EventRegistration({
    required this.id,
    this.type = 'PARTICIPANT',
    this.status = 'SUCCESSFUL',
    this.didAttend = false,
    this.checkInTime,
    this.guestCount = 0,
    this.guestUnitPrice,
    this.guestCheckIns = 0,
    this.totalPartySize = 1,
    this.remainingEntries = 1,
    this.event,
    this.user,
    this.transactions = const [],
    this.usageLog = const [],
    this.rawJson = const {},
  });

  bool get isSuccessful => status.toUpperCase() == 'SUCCESSFUL';
  bool get isPending => status.toUpperCase() == 'PENDING';
  bool get isPartyTicket => totalPartySize > 1 || guestCount > 0;
  bool get isAlreadyAttended => remainingEntries <= 0;
  bool get isFullyAttended => isAlreadyAttended;
  bool get isPartiallyAttended => remainingEntries > 0 && remainingEntries < totalPartySize;
  bool get canCheckIn => remainingEntries > 0;

  /// Whether payment has NOT been completed (e.g. status is PENDING or transactions are unpaid/incomplete)
  bool get isPaymentIncomplete =>
      isPending ||
      transactions.any((t) => t.isUnpaid) ||
      status.toUpperCase() == 'INCOMPLETE';

  bool get isUnpaid => isPaymentIncomplete;

  /// Whether the ticket is fully paid and confirmed
  bool get hasCompletedPayment => isSuccessful && !isPaymentIncomplete;

  /// Formatted group summary text
  String get guestSummary {
    if (!isPartyTicket) return 'Single attendee (1 ticket)';
    if (guestCount == 1) return 'Group of 2 (1 ticket holder + 1 guest)';
    return 'Group of $totalPartySize (1 ticket holder + $guestCount guests)';
  }

  /// Detailed human-readable error description for payment status
  String get paymentErrorMessage {
    if (!isPaymentIncomplete) return '';
    final guestPart = isPartyTicket
        ? 'Payment has not been completed for this group ticket ($totalPartySize admissions: 1 ticket holder + $guestCount guest${guestCount > 1 ? 's' : ''}).'
        : 'Payment has not been completed for this ticket.';
    final amount = transactions.isNotEmpty && transactions.first.amount != null
        ? 'Amount: €${transactions.first.amount}'
        : 'Pending transaction';
    return '$guestPart ($amount). Payment has not been completed.';
  }

  factory EventRegistration.fromJson(Map<String, dynamic> json) {
    final transactionsList = (json['transactions'] as List<dynamic>?)
            ?.map((t) => RegistrationTransaction.fromJson(t as Map<String, dynamic>?))
            .toList() ??
        const [];

    final usageList = (json['usageLog'] as List<dynamic>?)
            ?.map((u) => RegistrationUsageLog.fromJson(u as Map<String, dynamic>?))
            .toList() ??
        const [];

    return EventRegistration(
      id: json['id']?.toString() ?? '',
      type: json['type']?.toString() ?? 'PARTICIPANT',
      status: json['status']?.toString() ?? 'UNKNOWN',
      didAttend: json['didAttend'] as bool? ?? false,
      checkInTime: json['checkInTime']?.toString(),
      guestCount: _parseInt(json['guestCount']) ?? 0,
      guestUnitPrice: _parseNum(json['guestUnitPrice']),
      guestCheckIns: _parseInt(json['guestCheckIns']) ?? 0,
      totalPartySize: _parseInt(json['totalPartySize']) ?? 1,
      remainingEntries: _parseInt(json['remainingEntries']) ?? (json['didAttend'] == true ? 0 : 1),
      event: EventInfo.fromJson(json['event'] as Map<String, dynamic>?),
      user: UserInfo.fromJson(json['user'] as Map<String, dynamic>?),
      transactions: transactionsList,
      usageLog: usageList,
      rawJson: json,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type,
        'status': status,
        'didAttend': didAttend,
        'checkInTime': checkInTime,
        'guestCount': guestCount,
        'guestUnitPrice': guestUnitPrice,
        'guestCheckIns': guestCheckIns,
        'totalPartySize': totalPartySize,
        'remainingEntries': remainingEntries,
        'event': event?.toJson(),
        'user': user?.toJson(),
        'transactions': transactions.map((t) => t.toJson()).toList(),
        'usageLog': usageLog.map((u) => u.toJson()).toList(),
        'rawJson': rawJson,
      };

  EventRegistration copyWith({
    String? id,
    String? type,
    String? status,
    bool? didAttend,
    String? checkInTime,
    int? guestCount,
    num? guestUnitPrice,
    int? guestCheckIns,
    int? totalPartySize,
    int? remainingEntries,
    EventInfo? event,
    UserInfo? user,
    List<RegistrationTransaction>? transactions,
    List<RegistrationUsageLog>? usageLog,
    Map<String, dynamic>? rawJson,
  }) {
    return EventRegistration(
      id: id ?? this.id,
      type: type ?? this.type,
      status: status ?? this.status,
      didAttend: didAttend ?? this.didAttend,
      checkInTime: checkInTime ?? this.checkInTime,
      guestCount: guestCount ?? this.guestCount,
      guestUnitPrice: guestUnitPrice ?? this.guestUnitPrice,
      guestCheckIns: guestCheckIns ?? this.guestCheckIns,
      totalPartySize: totalPartySize ?? this.totalPartySize,
      remainingEntries: remainingEntries ?? this.remainingEntries,
      event: event ?? this.event,
      user: user ?? this.user,
      transactions: transactions ?? this.transactions,
      usageLog: usageLog ?? this.usageLog,
      rawJson: rawJson ?? this.rawJson,
    );
  }

  /// Monotonically reconciles this registration with existing local cache and device queue state.
  /// Guarantees that check-in progress (entries used, didAttend, timestamps) is NEVER reverted by a stale server read.
  EventRegistration reconcileWithLocal({
    EventRegistration? cached,
    int pendingQueueEntries = 0,
    bool hasDeviceCheckIn = false,
  }) {
    final effectiveDidAttend = didAttend || (cached?.didAttend ?? false) || hasDeviceCheckIn;
    final maxGuestCheckIns = [guestCheckIns, cached?.guestCheckIns ?? 0].reduce((a, b) => a > b ? a : b);

    // Remaining entries can only decrease, never increase from local state
    var minRemaining = cached != null
        ? (cached.remainingEntries < remainingEntries ? cached.remainingEntries : remainingEntries)
        : remainingEntries;

    if (pendingQueueEntries > 0) {
      minRemaining = minRemaining - pendingQueueEntries;
    }

    if (effectiveDidAttend && totalPartySize == 1) {
      minRemaining = 0;
    } else if (effectiveDidAttend) {
      final maxPossibleRemaining = (totalPartySize - 1 - maxGuestCheckIns).clamp(0, totalPartySize);
      if (minRemaining > maxPossibleRemaining) {
        minRemaining = maxPossibleRemaining;
      }
    }

    minRemaining = minRemaining.clamp(0, totalPartySize);

    return copyWith(
      didAttend: effectiveDidAttend,
      remainingEntries: minRemaining,
      guestCheckIns: maxGuestCheckIns,
      checkInTime: cached?.checkInTime ?? checkInTime,
    );
  }
}

class EventDetails {
  final String id;
  final String title;
  final String? icon;
  final DateTime? start;
  final DateTime? end;
  final int participantLimit;
  final int participantRegistrationCount;
  final int totalRegisteredCount;
  final int participantsAttended;
  final List<EventRegistration> participantRegistrations;
  final List<EventRegistration> organizerRegistrations;

  const EventDetails({
    required this.id,
    required this.title,
    this.icon,
    this.start,
    this.end,
    this.participantLimit = 0,
    this.participantRegistrationCount = 0,
    this.totalRegisteredCount = 0,
    this.participantsAttended = 0,
    this.participantRegistrations = const [],
    this.organizerRegistrations = const [],
  });

  factory EventDetails.fromJson(Map<String, dynamic> json) {
    DateTime? parseDt(dynamic val) {
      if (val == null) return null;
      return DateTime.tryParse(val.toString());
    }

    final eventInfo = EventInfo(
      id: json['id']?.toString() ?? '',
      title: json['title']?.toString() ?? 'Unnamed Event',
      icon: json['icon']?.toString(),
    );

    final participants = (json['participantRegistrations'] as List<dynamic>?)
            ?.map((r) {
              final map = Map<String, dynamic>.from(r as Map);
              if (!map.containsKey('event') || map['event'] == null) {
                map['event'] = eventInfo.toJson();
              }
              return EventRegistration.fromJson(map);
            })
            .toList() ??
        const [];

    final organizers = (json['organizerRegistrations'] as List<dynamic>?)
            ?.map((r) {
              final map = Map<String, dynamic>.from(r as Map);
              if (!map.containsKey('event') || map['event'] == null) {
                map['event'] = eventInfo.toJson();
              }
              return EventRegistration.fromJson(map);
            })
            .toList() ??
        const [];

    return EventDetails(
      id: json['id']?.toString() ?? '',
      title: json['title']?.toString() ?? 'Unnamed Event',
      icon: json['icon']?.toString(),
      start: parseDt(json['start']),
      end: parseDt(json['end']),
      participantLimit: (json['participantLimit'] as num?)?.toInt() ?? 0,
      participantRegistrationCount:
          (json['participantRegistrationCount'] as num?)?.toInt() ?? 0,
      totalRegisteredCount:
          (json['totalRegisteredCount'] as num?)?.toInt() ?? 0,
      participantsAttended:
          (json['participantsAttended'] as num?)?.toInt() ?? 0,
      participantRegistrations: participants,
      organizerRegistrations: organizers,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'icon': icon,
        'start': start?.toIso8601String(),
        'end': end?.toIso8601String(),
        'participantLimit': participantLimit,
        'participantRegistrationCount': participantRegistrationCount,
        'totalRegisteredCount': totalRegisteredCount,
        'participantsAttended': participantsAttended,
        'participantRegistrations':
            participantRegistrations.map((p) => p.toJson()).toList(),
        'organizerRegistrations':
            organizerRegistrations.map((o) => o.toJson()).toList(),
      };
}
