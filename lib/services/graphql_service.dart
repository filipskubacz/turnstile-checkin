import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import '../models/app_settings.dart';
import '../models/registration.dart';
import 'storage_service.dart';

class GraphQLResult<T> {
  final T? data;
  final String? errorMessage;
  final bool isSuccess;
  final Map<String, dynamic>? rawResponse;

  const GraphQLResult.success(this.data, {this.rawResponse})
      : isSuccess = true,
        errorMessage = null;

  const GraphQLResult.failure(this.errorMessage, {this.rawResponse})
      : isSuccess = false,
        data = null;
}

class GraphQLService {
  final StorageService storageService;
  final http.Client _client;

  GraphQLService(this.storageService, {http.Client? client})
      : _client = client ?? http.Client();

  static const String getRegistrationQuery = r'''
query getRegistration($id: ID!) {
  registration(id: $id) {
    id
    transactions {
      id
      status
      direction
      amount
      type
      subject
      stripePayment {
        id
        status
        __typename
      }
      __typename
    }
    status
    type
    didAttend
    checkInTime
    guestCount
    guestUnitPrice
    guestCheckIns
    totalPartySize
    remainingEntries
    usageLog {
      timestamp
      actorId
      manual
      note
      __typename
    }
    event {
      id
      title
      icon
      __typename
    }
    user {
      id
      fullName
      picture
      esnCardNumber
      esnCardValidUntil
      __typename
    }
    __typename
  }
}
''';

  static const String useRegistrationEntryMutation = r'''
mutation useRegistrationEntry($registrationId: ID!, $manual: Boolean) {
  useRegistrationEntry(registrationId: $registrationId, manual: $manual) {
    id
    guestCount
    guestCheckIns
    checkInTime
    totalPartySize
    remainingEntries
    usageLog {
      timestamp
      actorId
      manual
      note
      __typename
    }
    __typename
  }
}
''';

  static const String loadEventForRunningQuery = r'''
query loadEventForRunning($id: ID!) {
  event(id: $id) {
    id
    title
    icon
    start
    end
    participantLimit
    participantRegistrationCount
    totalRegisteredCount
    participantsAttended
    multiGuestSettings {
      enabled
      additionalGuestPrice
      __typename
    }
    createdBy {
      id
      fullName
      __typename
    }
    organizerRegistrations {
      id
      checkInTime
      user {
        id
        fullName
        picture
        email
        acceptPhoneUsage
        phone
        phoneNumberOnWhatsapp
        telegramUsername
        additionalData
        communicationEmail
        currentTenant {
          userId
          tenantId
          status
          __typename
        }
        __typename
      }
      __typename
    }
    costItems(hideOnInvoice: true) {
      id
      amount
      actualAmount
      submittedAmount
      name
      receipts {
        id
        __typename
      }
      __typename
    }
    submissionItems {
      id
      name
      __typename
    }
    participantRegistrations(includePending: true) {
      id
      checkInTime
      status
      didAttend
      guestCount
      guestUnitPrice
      guestCheckIns
      totalPartySize
      remainingEntries
      transactions {
        id
        status
        direction
        amount
        type
        subject
        stripePayment {
          id
          status
          __typename
        }
        __typename
      }
      submissions {
        id
        data
        submissionItem {
          id
          name
          __typename
        }
        __typename
      }
      user {
        id
        fullName
        lastName
        picture
        email
        acceptPhoneUsage
        phone
        phoneNumberOnWhatsapp
        telegramUsername
        esnCardValidUntil
        esnCardNumber
        communicationEmail
        additionalData
        currentTenant {
          userId
          tenantId
          status
          __typename
        }
        __typename
      }
      __typename
    }
    __typename
  }
}
''';

  Map<String, String> _buildHeaders(AppSettings settings) {
    final cleanUrl = settings.apiUrl.trim();
    final uri = Uri.tryParse(cleanUrl);
    final origin = (uri != null && uri.hasScheme && uri.hasAuthority)
        ? '${uri.scheme}://${uri.host}${uri.hasPort ? ':${uri.port}' : ''}'
        : '';

    final headers = <String, String>{
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      if (origin.isNotEmpty) ...{
        'Origin': origin,
        'Referer': '$origin/',
      },
    };

    final rawToken = settings.bearerToken.trim();
    if (rawToken.isNotEmpty) {
      final token = rawToken.startsWith(RegExp(r'bearer\s+', caseSensitive: false))
          ? rawToken.substring(rawToken.indexOf(' ') + 1).trim()
          : rawToken;
      headers['Authorization'] = 'Bearer $token';
    }
    return headers;
  }

  String? _extractError(Map<String, dynamic> body, int statusCode, String? reasonPhrase) {
    if (body.containsKey('errors') && (body['errors'] is List) && (body['errors'] as List).isNotEmpty) {
      final messages = (body['errors'] as List)
          .map((e) => (e is Map ? e['message']?.toString() : null) ?? 'GraphQL Error')
          .toList();

      if (messages.any((m) => m.toLowerCase().contains('jwt expired'))) {
        return 'Your login session has expired (jwt expired). Please update your Bearer token in Settings.';
      }
      return messages.join('; ');
    }
    if (statusCode != 200) {
      return 'HTTP $statusCode: ${reasonPhrase ?? 'Network Error'}';
    }
    return null;
  }

  Map<String, dynamic> _decodeGraphQLResponse(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is List && decoded.isNotEmpty && decoded.first is Map<String, dynamic>) {
        return decoded.first as Map<String, dynamic>;
      }
    } catch (_) {}
    return const {};
  }

  Future<GraphQLResult<EventRegistration>> getRegistration(
    String registrationId,
    AppSettings settings,
  ) async {
    final payload = {
      'operationName': 'getRegistration',
      'variables': {'id': registrationId},
      'extensions': {},
      'query': getRegistrationQuery,
    };

    final timeoutDuration = Duration(seconds: settings.timeoutSeconds);
    final headers = _buildHeaders(settings);

    try {
      final uri = Uri.parse(settings.apiUrl.trim());
      final response = await _client
          .post(
            uri,
            headers: headers,
            body: jsonEncode(payload),
          )
          .timeout(timeoutDuration);

      final body = _decodeGraphQLResponse(response.body);

      final errorMessage = _extractError(body, response.statusCode, response.reasonPhrase);
      if (errorMessage != null) {
        return GraphQLResult.failure(errorMessage, rawResponse: body);
      }

      final data = body['data'] as Map<String, dynamic>?;
      if (data == null || data['registration'] == null) {
        return GraphQLResult.failure(
          'Registration not found in database',
          rawResponse: body,
        );
      }

      final regMap = data['registration'] as Map<String, dynamic>;
      final registration = EventRegistration.fromJson(regMap);

      return GraphQLResult.success(registration, rawResponse: body);
    } on TimeoutException {
      return const GraphQLResult.failure('Request timed out. Please check connection and try again.');
    } on SocketException catch (e) {
      return GraphQLResult.failure('Network unreachable: ${e.message}');
    } catch (e) {
      return GraphQLResult.failure('Error: $e');
    }
  }

  Future<GraphQLResult<EventDetails>> loadEventForRunning(
    String eventId,
    AppSettings settings,
  ) async {
    final payload = {
      'operationName': 'loadEventForRunning',
      'variables': {'id': eventId},
      'extensions': {},
      'query': loadEventForRunningQuery,
    };

    final timeoutDuration = Duration(seconds: settings.timeoutSeconds);
    final headers = _buildHeaders(settings);

    try {
      final uri = Uri.parse(settings.apiUrl.trim());
      final response = await _client
          .post(
            uri,
            headers: headers,
            body: jsonEncode(payload),
          )
          .timeout(timeoutDuration);

      final body = _decodeGraphQLResponse(response.body);

      final errorMessage = _extractError(body, response.statusCode, response.reasonPhrase);
      if (errorMessage != null) {
        return GraphQLResult.failure(errorMessage, rawResponse: body);
      }

      final data = body['data'] as Map<String, dynamic>?;
      if (data == null || data['event'] == null) {
        return GraphQLResult.failure(
          'Event $eventId not found in database',
          rawResponse: body,
        );
      }

      final event = EventDetails.fromJson(data['event'] as Map<String, dynamic>);
      return GraphQLResult.success(event, rawResponse: body);
    } on TimeoutException {
      return GraphQLResult.failure(
        'Request timed out (${settings.timeoutSeconds}s). Server took too long to respond.',
      );
    } on SocketException catch (e) {
      return GraphQLResult.failure('Network unreachable: ${e.message}');
    } catch (e) {
      return GraphQLResult.failure('Error: $e');
    }
  }

  Future<GraphQLResult<Map<String, dynamic>>> useRegistrationEntry(
    String registrationId,
    AppSettings settings, {
    bool manual = false,
  }) async {
    // SAFE MODE DRY-RUN GUARD
    if (settings.isSafeMode) {
      await Future.delayed(const Duration(milliseconds: 10));
      return GraphQLResult.success({
        'simulated': true,
        'id': registrationId,
        'status': 'SUCCESSFUL',
        'didAttend': true,
      });
    }

    final payload = {
      'operationName': 'useRegistrationEntry',
      'variables': {
        'registrationId': registrationId,
        'manual': manual,
      },
      'extensions': {},
      'query': useRegistrationEntryMutation,
    };

    final timeoutDuration = Duration(seconds: settings.timeoutSeconds);
    final headers = _buildHeaders(settings);

    try {
      final uri = Uri.parse(settings.apiUrl.trim());
      final response = await _client
          .post(
            uri,
            headers: headers,
            body: jsonEncode(payload),
          )
          .timeout(timeoutDuration);

      final body = _decodeGraphQLResponse(response.body);

      final errorMessage = _extractError(body, response.statusCode, response.reasonPhrase);
      if (errorMessage != null) {
        return GraphQLResult.failure(errorMessage, rawResponse: body);
      }

      final data = body['data'] as Map<String, dynamic>?;
      final entryData = data?['useRegistrationEntry'] as Map<String, dynamic>?;

      return GraphQLResult.success(entryData ?? body, rawResponse: body);
    } on TimeoutException {
      return const GraphQLResult.failure('Check-in timed out. Will retry.');
    } catch (e) {
      return GraphQLResult.failure('Check-in failed: $e');
    }
  }

  void dispose() {
    _client.close();
  }
}
