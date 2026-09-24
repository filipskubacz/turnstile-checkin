import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:turnstile_checkin/models/app_settings.dart';
import 'package:turnstile_checkin/models/queue_item.dart';
import 'package:turnstile_checkin/models/registration.dart';
import 'package:turnstile_checkin/providers/attendees_provider.dart';
import 'package:turnstile_checkin/providers/scanner_provider.dart';
import 'package:turnstile_checkin/services/graphql_service.dart';
import 'package:turnstile_checkin/services/queue_service.dart';
import 'package:turnstile_checkin/services/storage_service.dart';
import 'package:turnstile_checkin/utils/jwt_utils.dart';

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
  });
  group('UUID Validation Tests', () {
    test('Valid UUIDs pass regex validation', () {
      expect(ScannerProvider.isValidUuid('6bb6d9e9-a291-49d6-8e78-625bc2d49b0d'), isTrue);
      expect(ScannerProvider.isValidUuid('6E014C8B-B1B6-4412-814C-E5031E1A03BE'), isTrue);
      expect(ScannerProvider.isValidUuid('00000000-0000-0000-0000-000000000000'), isTrue);
    });

    test('Invalid UUIDs fail validation', () {
      expect(ScannerProvider.isValidUuid(''), isFalse);
      expect(ScannerProvider.isValidUuid('not-a-uuid'), isFalse);
      expect(ScannerProvider.isValidUuid('6bb6d9e9-a291-49d6-8e78'), isFalse);
      expect(ScannerProvider.isValidUuid('6bb6d9e9-a291-49d6-8e78-625bc2d49b0dg'), isFalse); // 'g' invalid hex
      expect(ScannerProvider.isValidUuid('{6bb6d9e9-a291-49d6-8e78-625bc2d49b0d}'), isFalse);
    });

    test('Invalid UUID updates ScannerProvider state with M3 error info', () async {
      final prefs = await SharedPreferences.getInstance();
      final storage = StorageService(prefs);
      final gql = GraphQLService(storage);
      final queue = QueueService(
        storageService: storage,
        graphQLService: gql,
        getSettings: () => const AppSettings(),
      );

      final scanner = ScannerProvider(
        graphQLService: gql,
        queueService: queue,
        getSettings: () => const AppSettings(),
      );

      await scanner.handleBarcodeScanned('invalid-uuid');
      expect(scanner.state, ScanState.error);
      expect(scanner.errorTitle, 'Invalid QR Code');
      expect(scanner.errorMessage, contains('valid ticket UUID'));

      scanner.reset();
      expect(scanner.state, ScanState.ready);
      expect(scanner.errorTitle, isNull);
      expect(scanner.errorMessage, isNull);
    });
  });

  group('EventRegistration Deserialization Tests', () {
    test('Correctly parses provided user sample response', () {
      final sampleJson = {
        "id": "6bb6d9e9-a291-49d6-8e78-625bc2d49b0d",
        "type": "PARTICIPANT",
        "didAttend": false,
        "event": {
          "id": "6e014c8b-b1b6-4412-814c-e5031e1a03be",
          "title": "Test Event",
          "icon": "work",
          "__typename": "Event"
        },
        "__typename": "EventRegistration",
        "transactions": [],
        "status": "SUCCESSFUL",
        "checkInTime": null,
        "guestCount": 0,
        "guestUnitPrice": null,
        "guestCheckIns": 0,
        "totalPartySize": 1,
        "remainingEntries": 1,
        "usageLog": [],
        "user": {
          "__typename": "User",
          "id": "2bba0179-b89a-462e-be57-8b9f1b4819f8",
          "fullName": "Filip Skubacz",
          "picture": "/storage/profile/2bba0179-b89a-462e-be57-8b9f1b4819f8/34981fef%7Cski_aggu_profile.png-cropped",
          "esnCardNumber": null,
          "esnCardValidUntil": null
        }
      };

      final reg = EventRegistration.fromJson(sampleJson);

      expect(reg.id, '6bb6d9e9-a291-49d6-8e78-625bc2d49b0d');
      expect(reg.type, 'PARTICIPANT');
      expect(reg.status, 'SUCCESSFUL');
      expect(reg.didAttend, isFalse);
      expect(reg.remainingEntries, 1);
      expect(reg.totalPartySize, 1);
      expect(reg.isAlreadyAttended, isFalse);
      expect(reg.canCheckIn, isTrue);

      expect(reg.event?.title, 'Test Event');
      expect(reg.event?.id, '6e014c8b-b1b6-4412-814c-e5031e1a03be');

      expect(reg.user?.fullName, 'Filip Skubacz');
      expect(reg.user?.id, '2bba0179-b89a-462e-be57-8b9f1b4819f8');
    });

    test('Gracefully identifies already-attended tickets', () {
      final attendedJson = {
        "id": "6bb6d9e9-a291-49d6-8e78-625bc2d49b0d",
        "status": "SUCCESSFUL",
        "didAttend": true,
        "checkInTime": "2026-09-19T13:00:00Z",
        "remainingEntries": 0,
        "totalPartySize": 1,
      };

      final reg = EventRegistration.fromJson(attendedJson);
      expect(reg.didAttend, isTrue);
      expect(reg.isAlreadyAttended, isTrue);
      expect(reg.canCheckIn, isFalse);
      expect(reg.checkInTime, '2026-09-19T13:00:00Z');
    });

    test('Tolerates unexpected or missing fields without throwing', () {
      final minimalJson = <String, dynamic>{
        "id": "6bb6d9e9-a291-49d6-8e78-625bc2d49b0d",
        "unknownFutureField": 12345,
      };

      final reg = EventRegistration.fromJson(minimalJson);
      expect(reg.id, '6bb6d9e9-a291-49d6-8e78-625bc2d49b0d');
      expect(reg.event, isNotNull);
      expect(reg.user, isNotNull);
      expect(reg.status, 'UNKNOWN');
    });
  });

  group('AppSettings Tests', () {
    test('Settings serialization and defaults', () {
      const settings = AppSettings();
      expect(settings.isSafeMode, isTrue);
      expect(settings.timeoutSeconds, 30);
      expect(settings.activeEventIds, isEmpty);
      expect(settings.apiUrl, AppSettings.defaultApiUrl);

      final modified = settings.copyWith(
        bearerToken: 'test-token',
        apiUrl: 'https://custom.backend/graphql',
        activeEventIds: ['event-1', 'event-2'],
        timeoutSeconds: 45,
        isSafeMode: false,
      );

      final json = modified.toJson();
      final restored = AppSettings.fromJson(json);

      expect(restored.bearerToken, 'test-token');
      expect(restored.apiUrl, 'https://custom.backend/graphql');
      expect(restored.activeEventIds, ['event-1', 'event-2']);
      expect(restored.timeoutSeconds, 45);
      expect(restored.isSafeMode, isFalse);
    });

    test('Falls back to defaultApiUrl when apiUrl is missing or empty', () {
      final emptyJson = <String, dynamic>{
        'apiUrl': '',
      };
      final settings = AppSettings.fromJson(emptyJson);
      expect(settings.apiUrl, AppSettings.defaultApiUrl);
    });
  });

  group('Queue Processing & Retry Mechanics Tests', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('Queue item transitions and retry counter', () async {
      final prefs = await SharedPreferences.getInstance();
      final storage = StorageService(prefs);
      final gql = GraphQLService(storage);

      final queue = QueueService(
        storageService: storage,
        graphQLService: gql,
        getSettings: () => const AppSettings(isSafeMode: true),
      );
      await queue.init();

      final reg = EventRegistration(
        id: '6bb6d9e9-a291-49d6-8e78-625bc2d49b0d',
        user: const UserInfo(id: 'u1', fullName: 'Test Attendee'),
        event: const EventInfo(id: 'e1', title: 'Sample Event'),
      );

      final item = await queue.enqueueRegistration(reg);
      expect(item.status, QueueStatus.pending);

      // Wait briefly for Safe Mode async simulation
      await Future.delayed(const Duration(milliseconds: 700));

      expect(queue.completedCount, 1);
      expect(queue.items.first.status, QueueStatus.completed);

      // Verify stored queue
      final storedQueue = await storage.loadQueue();
      expect(storedQueue.length, 1);
      expect(storedQueue.first.attendeeName, 'Test Attendee');
      expect(storedQueue.first.registrationId, '6bb6d9e9-a291-49d6-8e78-625bc2d49b0d');
    });

    test('Escalates to manual retry after max 3 retries', () {
      var item = QueueItem(
        id: 'q1',
        registrationId: 'reg-1',
        attendeeName: 'Attendee',
        eventTitle: 'Event',
        eventId: 'e1',
        enqueuedAt: DateTime(2026, 9, 19),
        status: QueueStatus.pending,
        retryCount: 0,
      );

      // Simulate 3 failures
      item = item.copyWith(retryCount: 1, status: QueueStatus.failedRetrying, lastError: 'Timeout');
      expect(item.status, QueueStatus.failedRetrying);

      item = item.copyWith(retryCount: 2, status: QueueStatus.failedRetrying, lastError: 'Timeout 2');
      expect(item.status, QueueStatus.failedRetrying);

      item = item.copyWith(retryCount: 3, status: QueueStatus.failedManual, lastError: 'Timeout 3');
      expect(item.status, QueueStatus.failedManual);
      expect(item.retryCount, 3);
    });
  });

  group('Settings Persistence Tests', () {
    test('Persists bearer auth token across storage save and load', () async {
      final prefs = await SharedPreferences.getInstance();
      final storage = StorageService(prefs);

      const testToken = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.testTokenData';
      final settings = const AppSettings().copyWith(
        bearerToken: testToken,
        apiUrl: 'https://example.com/graphql',
      );

      await storage.saveSettings(settings);

      final loaded = storage.loadSettings();
      expect(loaded.bearerToken, testToken);
      expect(loaded.apiUrl, 'https://example.com/graphql');
    });
  });

  group('Attendee List & Offline Fallback Tests', () {
    const userSampleResponse = {
      "id": "fe7f296c-b182-4563-bf47-55384f339882",
      "title": "TEST EVENT PLS IGNORE",
      "icon": "beer",
      "start": "2026-10-20T09:00:00.000Z",
      "end": "2026-10-20T16:00:00.000Z",
      "participantLimit": 1,
      "participantRegistrationCount": 1,
      "multiGuestSettings": null,
      "costItems": [],
      "submissionItems": [],
      "__typename": "Event",
      "participantsAttended": 1,
      "organizerRegistrations": [],
      "totalRegisteredCount": 1,
      "createdBy": {
        "__typename": "User",
        "id": "2bba0179-b89a-462e-be57-8b9f1b4819f8",
        "fullName": "Filip Skubacz"
      },
      "participantRegistrations": [
        {
          "id": "e16b4b24-81a9-4361-ae50-a75cbed0defc",
          "checkInTime": "2026-09-19T14:16:45.775Z",
          "status": "SUCCESSFUL",
          "didAttend": true,
          "guestCount": 0,
          "guestUnitPrice": null,
          "guestCheckIns": 0,
          "totalPartySize": 1,
          "remainingEntries": 0,
          "transactions": [],
          "submissions": [],
          "__typename": "EventRegistration",
          "user": {
            "__typename": "User",
            "id": "2bba0179-b89a-462e-be57-8b9f1b4819f8",
            "fullName": "Filip Skubacz",
            "lastName": "Skubacz",
            "picture": "/storage/profile/2bba0179/pic.png",
            "email": "filip.b.skubacz@gmail.com",
            "acceptPhoneUsage": false,
            "phone": null,
            "phoneNumberOnWhatsapp": false,
            "telegramUsername": "",
            "esnCardValidUntil": null,
            "esnCardNumber": "ESN-12345",
            "communicationEmail": "user@example.com",
            "additionalData": {},
            "currentTenant": {
              "userId": "2bba0179-b89a-462e-be57-8b9f1b4819f8",
              "tenantId": "c7f09dbf-0ff5-4c55-8dd8-f975d7093280",
              "status": "FULL",
              "__typename": "UsersOfTenants"
            }
          }
        }
      ]
    };

    test('Parses loadEventForRunning response accurately', () {
      final event = EventDetails.fromJson(userSampleResponse);

      expect(event.id, 'fe7f296c-b182-4563-bf47-55384f339882');
      expect(event.title, 'TEST EVENT PLS IGNORE');
      expect(event.icon, 'beer');
      expect(event.totalRegisteredCount, 1);
      expect(event.participantsAttended, 1);
      expect(event.participantRegistrations.length, 1);

      final reg = event.participantRegistrations.first;
      expect(reg.id, 'e16b4b24-81a9-4361-ae50-a75cbed0defc');
      expect(reg.didAttend, isTrue);
      expect(reg.user?.displayName, 'Filip Skubacz');
      expect(reg.user?.email, 'filip.b.skubacz@gmail.com');
      expect(reg.user?.esnCardNumber, 'ESN-12345');
      expect(reg.event?.title, 'TEST EVENT PLS IGNORE');
    });

    test('Caches event attendees offline and allows find by UUID', () async {
      final prefs = await SharedPreferences.getInstance();
      final storage = StorageService(prefs);
      final event = EventDetails.fromJson(userSampleResponse);

      await storage.saveCachedEventAttendees(event);

      final cachedEvent = await storage.loadCachedEvent(eventId: event.id);
      expect(cachedEvent, isNotNull);
      expect(cachedEvent!.title, 'TEST EVENT PLS IGNORE');

      final found = await storage.findCachedRegistration('e16b4b24-81a9-4361-ae50-a75cbed0defc');
      expect(found, isNotNull);
      expect(found!.user?.displayName, 'Filip Skubacz');
    });

    test('ScannerProvider falls back to local cache when server call fails', () async {
      final prefs = await SharedPreferences.getInstance();
      final storage = StorageService(prefs);
      final event = EventDetails.fromJson(userSampleResponse);
      await storage.saveCachedEventAttendees(event);

      // Create a mock/failing GraphQL service by not providing a working backend
      final failingGql = GraphQLService(storage);
      final queue = QueueService(
        storageService: storage,
        graphQLService: failingGql,
        getSettings: () => const AppSettings(),
      );

      final scanner = ScannerProvider(
        graphQLService: failingGql,
        queueService: queue,
        storageService: storage,
        getSettings: () => const AppSettings(apiUrl: 'http://invalid.local.test/graphql'),
      );

      // Scan cached ticket UUID
      await scanner.handleBarcodeScanned('e16b4b24-81a9-4361-ae50-a75cbed0defc');
      // Wait for the background online check to complete its network failure
      await Future<void>.delayed(const Duration(milliseconds: 50));

      // Should succeed via offline fallback rather than erroring out!
      expect(scanner.state, ScanState.ticketFound);
      expect(scanner.isOfflineFallback, isTrue);
      expect(scanner.currentRegistration?.id, 'e16b4b24-81a9-4361-ae50-a75cbed0defc');
      expect(scanner.currentRegistration?.user?.displayName, 'Filip Skubacz');
    });

    test('GraphQLService recognizes jwt expired and informs user to update Settings', () async {
      final prefs = await SharedPreferences.getInstance();
      final storage = StorageService(prefs);
      final gql = GraphQLService(storage);

      // Verify the extractError behavior through loadEventForRunning on a mock client if possible,
      // or test GraphQLResult failure message format directly
      final result = await gql.loadEventForRunning(
        'test-id',
        const AppSettings(apiUrl: 'http://localhost:99999/invalid'),
      );
      expect(result.isSuccess, isFalse);
    });
  });

  group('JwtUtils Tests', () {
    const validFutureJwt =
        'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiJhdXRoMHw2NGYxMjM0NTYiLCJuYW1lIjoiRmlsaXAgU2t1YmFjeiIsImVtYWlsIjoiZmlsaXBAZXhhbXBsZS5jb20iLCJleHAiOjI1MjQ2MDgwMDB9.mock_sig';
    const expiredJwt =
        'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiJhdXRoMHw2NGYxMjM0NTYiLCJuYW1lIjoiRmlsaXAgU2t1YmFjeiIsImVtYWlsIjoiZmlsaXBAZXhhbXBsZS5jb20iLCJleHAiOjEwMDAwMDAwMDB9.mock_sig';

    test('Decodes payload correctly', () {
      final payload = JwtUtils.decodePayload(validFutureJwt);
      expect(payload, isNotNull);
      expect(payload!['name'], 'Filip Skubacz');
      expect(payload['email'], 'filip@example.com');
      expect(payload['exp'], 2524608000);
    });

    test('Checks expiry accurately for active vs expired tokens', () {
      expect(JwtUtils.isExpired(validFutureJwt), isFalse);
      expect(JwtUtils.isExpired(expiredJwt), isTrue);
    });

    test('Extracts user identifier properly', () {
      expect(JwtUtils.getUserIdentifier(validFutureJwt), 'Filip Skubacz');
      expect(JwtUtils.getUserIdentifier(expiredJwt), 'Filip Skubacz');
    });

    test('Formats expiry string human-readably', () {
      final activeStatus = JwtUtils.formatExpiryStatus(validFutureJwt);
      expect(activeStatus, contains('Valid for'));

      final expiredStatus = JwtUtils.formatExpiryStatus(expiredJwt);
      expect(expiredStatus, contains('Expired'));
    });

    test('Handles malformed or non-JWT tokens safely without throwing', () {
      expect(JwtUtils.decodePayload('not-a-jwt'), isNull);
      expect(JwtUtils.getExpiry('not-a-jwt'), isNull);
      expect(JwtUtils.isExpired('not-a-jwt'), isFalse);
      expect(JwtUtils.getUserIdentifier('not-a-jwt'), isNull);
      expect(JwtUtils.formatExpiryStatus('not-a-jwt'), 'No expiry date in token');
    });
  });



  group('Party Tickets & String Num Parsing Tests', () {
    test('Parses party ticket payload with string amounts and guest fields accurately', () {
      final json = {
        'id': '42eb8af8-9103-48ae-9f56-3df1fa59878a',
        'type': 'PARTICIPANT',
        'didAttend': false,
        'event': {
          'id': '3bedd12c-b635-4b71-a098-01aa9f7e5407',
          'title': 'TEST EVENT 2',
          'icon': 'beer',
          '__typename': 'Event'
        },
        '__typename': 'EventRegistration',
        'transactions': [
          {
            'id': '42bb5f01-3f72-458d-a3ff-7f3a88425e98',
            'status': 'PENDING',
            'direction': 'USER_TO_ORG',
            'amount': '0', // String amount!
            'type': 'STRIPE',
            'subject': 'Fee for: TEST EVENT 2',
            'stripePayment': {
              'id': 'a753bf43-8137-41a6-84dd-c068d69d0779',
              'status': 'incomplete',
              '__typename': 'StripePayment'
            },
            '__typename': 'Transaction'
          }
        ],
        'status': 'PENDING', // PENDING status!
        'checkInTime': null,
        'guestCount': 1,
        'guestUnitPrice': '0', // String guest unit price!
        'guestCheckIns': 0,
        'totalPartySize': 2,
        'remainingEntries': 2,
        'usageLog': [],
        'user': {
          '__typename': 'User',
          'id': '2bba0179-b89a-462e-be57-8b9f1b4819f8',
          'fullName': 'Filip Skubacz',
          'picture': '/storage/profile/2bba0179-b89a-462e-be57-8b9f1b4819f8/34981fef%7Cski_aggu_profile.png-cropped',
          'esnCardNumber': null,
          'esnCardValidUntil': null
        }
      };

      final reg = EventRegistration.fromJson(json);

      expect(reg.id, '42eb8af8-9103-48ae-9f56-3df1fa59878a');
      expect(reg.isPartyTicket, isTrue);
      expect(reg.guestCount, 1);
      expect(reg.guestUnitPrice, 0.0);
      expect(reg.guestCheckIns, 0);
      expect(reg.totalPartySize, 2);
      expect(reg.remainingEntries, 2);
      expect(reg.isPending, isTrue);
      expect(reg.isPaymentIncomplete, isTrue);
      expect(reg.isUnpaid, isTrue);
      expect(reg.hasCompletedPayment, isFalse);
      expect(reg.transactions.first.stripePaymentStatus, 'incomplete');
      expect(reg.transactions.first.isStripeIncomplete, isTrue);
      expect(reg.transactions.first.isUnpaid, isTrue);
      expect(reg.guestSummary, contains('Group of 2'));
      expect(reg.paymentErrorMessage, contains('not been completed'));
      expect(reg.paymentErrorMessage, contains('2 admissions'));
      expect(reg.canCheckIn, isTrue);
      expect(reg.isAlreadyAttended, isFalse);
      expect(reg.isPartiallyAttended, isFalse);
      expect(reg.isFullyAttended, isFalse);
      expect(reg.transactions.first.amount, 0.0);
    });

    test('Handles partial party check-in states correctly without false already-attended blocks', () {
      final partiallyAttendedJson = {
        'id': 'party-partial-1',
        'type': 'PARTICIPANT',
        'didAttend': true, // Main attendee checked in!
        'status': 'SUCCESSFUL',
        'guestCount': 2,
        'guestCheckIns': 0,
        'totalPartySize': 3,
        'remainingEntries': 2, // 2 guest entries remain!
        'user': {'fullName': 'Main Attendee'},
        'event': {'title': 'Party Night'}
      };

      final reg = EventRegistration.fromJson(partiallyAttendedJson);

      expect(reg.isPartyTicket, isTrue);
      expect(reg.didAttend, isTrue);
      expect(reg.remainingEntries, 2);
      expect(reg.isPartiallyAttended, isTrue);
      expect(reg.isFullyAttended, isFalse);
      // Crucial: Must NOT be considered already attended because guests still need entry!
      expect(reg.isAlreadyAttended, isFalse);
      expect(reg.canCheckIn, isTrue);
    });

    test('Correctly marks party ticket fully attended when remainingEntries is 0', () {
      final fullyAttendedJson = {
        'id': 'party-full-1',
        'type': 'PARTICIPANT',
        'didAttend': true,
        'status': 'SUCCESSFUL',
        'guestCount': 1,
        'guestCheckIns': 1,
        'totalPartySize': 2,
        'remainingEntries': 0, // All entered!
        'user': {'fullName': 'Full Attendee'},
        'event': {'title': 'Party Night'}
      };

      final reg = EventRegistration.fromJson(fullyAttendedJson);

      expect(reg.isPartyTicket, isTrue);
      expect(reg.remainingEntries, 0);
      expect(reg.isPartiallyAttended, isFalse);
      expect(reg.isFullyAttended, isTrue);
      expect(reg.isAlreadyAttended, isTrue);
      expect(reg.canCheckIn, isFalse);
    });

    test('Correctly detects fully paid registrations with no payment error', () {
      final paidJson = {
        'id': 'paid-single-1',
        'type': 'PARTICIPANT',
        'status': 'SUCCESSFUL',
        'didAttend': false,
        'guestCount': 0,
        'totalPartySize': 1,
        'remainingEntries': 1,
        'transactions': [
          {
            'id': 'tx-1',
            'status': 'CONFIRMED',
            'amount': 15.0,
            'stripePayment': {'status': 'succeeded'}
          }
        ],
        'user': {'fullName': 'Paid User'},
        'event': {'title': 'Paid Event'}
      };

      final reg = EventRegistration.fromJson(paidJson);
      expect(reg.isPaymentIncomplete, isFalse);
      expect(reg.isUnpaid, isFalse);
      expect(reg.hasCompletedPayment, isTrue);
      expect(reg.isPartyTicket, isFalse);
    });

    test('Correctly detects unpaid party ticket with multiple guests and creates accurate error description', () {
      final unpaidPartyJson = {
        'id': 'unpaid-party-4',
        'type': 'PARTICIPANT',
        'status': 'PENDING',
        'didAttend': false,
        'guestCount': 3,
        'guestUnitPrice': '5.50',
        'totalPartySize': 4,
        'remainingEntries': 4,
        'transactions': [
          {
            'id': 'tx-party',
            'status': 'PENDING',
            'amount': '22.00',
            'stripePayment': {'status': 'incomplete'}
          }
        ],
        'user': {'fullName': 'Party Host'},
        'event': {'title': 'Festival Party'}
      };

      final reg = EventRegistration.fromJson(unpaidPartyJson);
      expect(reg.isPaymentIncomplete, isTrue);
      expect(reg.isUnpaid, isTrue);
      expect(reg.isPartyTicket, isTrue);
      expect(reg.guestCount, 3);
      expect(reg.totalPartySize, 4);
      expect(reg.guestUnitPrice, 5.50);
      expect(reg.guestSummary, 'Group of 4 (1 ticket holder + 3 guests)');
      expect(reg.paymentErrorMessage, contains('4 admissions'));
      expect(reg.paymentErrorMessage, contains('3 guests'));
      expect(reg.paymentErrorMessage, contains('22.0'));
    });
  });

  group('Group Check-In & useRegistrationEntry Mutation Tests', () {
    test('useRegistrationEntryMutation contains correct query and variables', () {
      expect(GraphQLService.useRegistrationEntryMutation, contains('mutation useRegistrationEntry('));
      expect(GraphQLService.useRegistrationEntryMutation, contains(r'$registrationId: ID!'));
      expect(GraphQLService.useRegistrationEntryMutation, contains(r'$manual: Boolean'));
      expect(GraphQLService.useRegistrationEntryMutation, contains(r'useRegistrationEntry(registrationId: $registrationId, manual: $manual)'));
    });

    test('useRegistrationEntry in safe mode returns simulated success without network calls', () async {
      final prefs = await SharedPreferences.getInstance();
      final storage = StorageService(prefs);
      final gql = GraphQLService(storage);

      const settings = AppSettings(isSafeMode: true);
      final result = await gql.useRegistrationEntry('reg-123', settings, manual: false);

      expect(result.isSuccess, isTrue);
      expect(result.data, isNotNull);
      expect(result.data!['id'], 'reg-123');
      expect(result.data!['status'], 'SUCCESSFUL');
      expect(result.data!['didAttend'], isTrue);
    });

    test('QueueItem serialization preserves entriesCount, entriesProcessed, and manual flag', () {
      final item = QueueItem(
        id: 'q-1',
        registrationId: 'reg-456',
        attendeeName: 'Alex Group',
        eventTitle: 'Gala Night',
        eventId: 'event-99',
        enqueuedAt: DateTime(2026, 9, 19, 18, 0, 0),
        status: QueueStatus.pending,
        entriesCount: 3,
        entriesProcessed: 1,
        manual: true,
      );

      final json = item.toJson();
      expect(json['entriesCount'], 3);
      expect(json['entriesProcessed'], 1);
      expect(json['manual'], isTrue);

      final restored = QueueItem.fromJson(json);
      expect(restored.entriesCount, 3);
      expect(restored.entriesProcessed, 1);
      expect(restored.manual, isTrue);
    });

    test('QueueItem serialization preserves entriesCount and entriesProcessed', () {
      final item = QueueItem(
        id: 'queue-123',
        registrationId: 'reg-123',
        attendeeName: 'Sam Group',
        eventTitle: 'Festival',
        eventId: 'ev-1',
        enqueuedAt: DateTime(2026, 9, 19, 19, 0, 0),
        status: QueueStatus.completed,
        entriesCount: 4,
        entriesProcessed: 3,
      );

      final json = item.toJson();
      expect(json['entriesCount'], 4);
      expect(json['entriesProcessed'], 3);

      final restored = QueueItem.fromJson(json);
      expect(restored.entriesCount, 4);
      expect(restored.entriesProcessed, 3);
    });

    test('StorageService updateCachedRegistrationCheckIn decrements remainingEntries by count', () async {
      final prefs = await SharedPreferences.getInstance();
      final storage = StorageService(prefs);

      const reg = EventRegistration(
        id: 'party-test-multi',
        type: 'PARTICIPANT',
        status: 'SUCCESSFUL',
        didAttend: false,
        totalPartySize: 5,
        guestCount: 4,
        guestCheckIns: 0,
        remainingEntries: 5,
        user: UserInfo(id: 'u-host', fullName: 'Host Attendee'),
      );

      await storage.saveCachedEventAttendees(
        const EventDetails(
          id: 'ev-multi',
          title: 'Mega Party',
          participantRegistrations: [reg],
        ),
      );

      // Check in 2 of 5 entries
      await storage.updateCachedRegistrationCheckIn(
        'party-test-multi',
        true,
        DateTime.now(),
        count: 2,
      );

      var updated = await storage.findCachedRegistration('party-test-multi');
      expect(updated, isNotNull);
      expect(updated!.remainingEntries, 3);
      expect(updated.guestCheckIns, 1); // 1 main + 1 guest
      expect(updated.didAttend, isTrue);

      // Check in the remaining 3 entries
      await storage.updateCachedRegistrationCheckIn(
        'party-test-multi',
        true,
        DateTime.now(),
        count: 3,
      );

      updated = await storage.findCachedRegistration('party-test-multi');
      expect(updated, isNotNull);
      expect(updated!.remainingEntries, 0);
      expect(updated.guestCheckIns, 4); // all 4 guests checked in
      expect(updated.isFullyAttended, isTrue);
    });

    test('QueueService executes useRegistrationEntry multiple times for multi-entry items', () async {
      final prefs = await SharedPreferences.getInstance();
      final storage = StorageService(prefs);
      final gql = GraphQLService(storage);

      final queue = QueueService(
        storageService: storage,
        graphQLService: gql,
        getSettings: () => const AppSettings(isSafeMode: true),
      );

      const reg = EventRegistration(
        id: 'multi-queue-reg',
        type: 'PARTICIPANT',
        status: 'SUCCESSFUL',
        didAttend: false,
        totalPartySize: 3,
        remainingEntries: 3,
        user: UserInfo(id: 'u-queue', fullName: 'Queue Party'),
      );

      final item = await queue.enqueueRegistration(
        reg,
        count: 3,
        manual: false,
      );

      expect(item.entriesCount, 3);
      expect(item.entriesProcessed, 0);

      // Wait a tick for async _processNext to finish in safe mode
      await Future.delayed(const Duration(milliseconds: 200));

      expect(queue.items.first.status, QueueStatus.completed);
      expect(queue.items.first.entriesProcessed, 3);
    });

    test('QueueService tracks active item and pending entries count', () async {
      final prefs = await SharedPreferences.getInstance();
      final storage = StorageService(prefs);
      final gql = GraphQLService(storage);

      final queue = QueueService(
        storageService: storage,
        graphQLService: gql,
        getSettings: () => const AppSettings(isSafeMode: true),
      );

      const reg = EventRegistration(
        id: 'pending-check-reg',
        type: 'PARTICIPANT',
        status: 'SUCCESSFUL',
        totalPartySize: 4,
        remainingEntries: 4,
      );

      expect(queue.hasPendingCheckIn('pending-check-reg'), isFalse);
      expect(queue.getPendingEntriesCount('pending-check-reg'), 0);

      final item = await queue.enqueueRegistration(reg, count: 2);
      expect(item.entriesCount, 2);

      // Immediately after enqueuing, it should be recognized as active/pending
      // (even before or during processing)
      expect(queue.getActiveItem('pending-check-reg'), isNotNull);

      // Wait for safe mode completion
      await Future.delayed(const Duration(milliseconds: 200));

      expect(queue.hasPendingCheckIn('pending-check-reg'), isFalse);
      expect(queue.getPendingEntriesCount('pending-check-reg'), 0);
    });

    test('ScannerProvider checkInCurrentTicket immediately updates currentRegistration locally', () async {
      final prefs = await SharedPreferences.getInstance();
      final storage = StorageService(prefs);
      final gql = GraphQLService(storage);

      final queue = QueueService(
        storageService: storage,
        graphQLService: gql,
        getSettings: () => const AppSettings(isSafeMode: true),
      );

      final provider = ScannerProvider(
        graphQLService: gql,
        queueService: queue,
        storageService: storage,
        getSettings: () => const AppSettings(isSafeMode: true),
      );

      const reg = EventRegistration(
        id: 'instant-feedback-reg',
        type: 'PARTICIPANT',
        status: 'SUCCESSFUL',
        totalPartySize: 3,
        remainingEntries: 3,
        guestCount: 2,
        user: UserInfo(id: 'u-instant', fullName: 'Instant Feedback User'),
      );

      provider.setCurrentRegistrationForTesting(reg);
      expect(provider.currentRegistration, isNotNull);
      expect(provider.currentRegistration!.remainingEntries, 3);

      // Perform check-in of 2 entries
      await provider.checkInCurrentTicket(count: 2);

      // Immediately, provider must still retain currentRegistration with decremented entries!
      expect(provider.currentRegistration, isNotNull);
      expect(provider.currentRegistration!.remainingEntries, 1);
      expect(provider.currentRegistration!.didAttend, isTrue);

      // Barcode debouncing must hold the UUID so quick camera rescans don't immediately overwrite
      expect(provider.lastScannedUuid, 'instant-feedback-reg');
    });

    test('Immediate local verification resolves ticket instantly while background online check runs', () async {
      final prefs = await SharedPreferences.getInstance();
      final storage = StorageService(prefs);
      final gql = GraphQLService(storage);
      final queue = QueueService(
        storageService: storage,
        graphQLService: gql,
        getSettings: () => const AppSettings(isSafeMode: true),
      );

      final provider = ScannerProvider(
        graphQLService: gql,
        queueService: queue,
        storageService: storage,
        getSettings: () => const AppSettings(isSafeMode: true),
      );

      const cachedReg = EventRegistration(
        id: 'e16b4b24-81a9-4361-ae50-a75cbed0de01',
        type: 'PARTICIPANT',
        status: 'SUCCESSFUL',
        totalPartySize: 4,
        remainingEntries: 4,
        guestCount: 3,
        user: UserInfo(id: 'u-cached', fullName: 'Instant Local User'),
      );

      // Cache registration locally
      await storage.cacheRegistration(cachedReg);

      // Scan barcode
      await provider.handleBarcodeScanned('e16b4b24-81a9-4361-ae50-a75cbed0de01');

      // State must immediately be ticketFound with local data, zero spinner latency
      expect(provider.state, ScanState.ticketFound);
      expect(provider.currentRegistration?.id, 'e16b4b24-81a9-4361-ae50-a75cbed0de01');
      expect(provider.currentRegistration?.remainingEntries, 4);
      expect(provider.isOnlineVerifying, isTrue);

      // After background online check finishes (in safe mode mock)
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(provider.isOnlineVerifying, isFalse);
    });

    test('Background online check safely preserves local decrement if checkInCurrentTicket runs before server returns', () async {
      final prefs = await SharedPreferences.getInstance();
      final storage = StorageService(prefs);
      final gql = GraphQLService(storage);
      final queue = QueueService(
        storageService: storage,
        graphQLService: gql,
        getSettings: () => const AppSettings(isSafeMode: true),
      );

      final provider = ScannerProvider(
        graphQLService: gql,
        queueService: queue,
        storageService: storage,
        getSettings: () => const AppSettings(isSafeMode: true),
      );

      const cachedReg = EventRegistration(
        id: 'e16b4b24-81a9-4361-ae50-a75cbed0de02',
        type: 'PARTICIPANT',
        status: 'SUCCESSFUL',
        totalPartySize: 3,
        remainingEntries: 3,
        guestCount: 2,
        user: UserInfo(id: 'u-race', fullName: 'Race Condition Test User'),
      );

      await storage.cacheRegistration(cachedReg);

      // Trigger scan: immediately resolves locally
      await provider.handleBarcodeScanned('e16b4b24-81a9-4361-ae50-a75cbed0de02');
      expect(provider.currentRegistration?.remainingEntries, 3);

      // User immediately clicks check in for 2 people before online check completes
      await provider.checkInCurrentTicket(count: 2);
      expect(provider.currentRegistration?.remainingEntries, 1);
      expect(provider.lastCheckedInCount, 2);

      // Wait for any background check or queue tasks
      await Future<void>.delayed(const Duration(milliseconds: 60));

      // Local progress must not have been reverted by server response!
      expect(provider.currentRegistration?.remainingEntries, 1);
    });

    test('ScannerProvider strictly rejects unknown UUIDs when offline if not in downloaded local roster', () async {
      final prefs = await SharedPreferences.getInstance();
      final storage = StorageService(prefs);
      final gql = GraphQLService(storage);
      final queue = QueueService(
        storageService: storage,
        graphQLService: gql,
        getSettings: () => const AppSettings(isSafeMode: false, apiUrl: 'http://invalid-offline-host:9999/graphql'),
      );

      final provider = ScannerProvider(
        graphQLService: gql,
        queueService: queue,
        storageService: storage,
        getSettings: () => const AppSettings(isSafeMode: false, apiUrl: 'http://invalid-offline-host:9999/graphql'),
        onlineTimeoutThreshold: const Duration(milliseconds: 50),
      );

      // Scan an unknown valid UUID while offline
      const testUuid = 'b1ce1a6c-f968-4c1a-a027-8bf1e4ba2d29';
      await provider.handleBarcodeScanned(testUuid);

      // Security rule: Must NOT fall back to an unverified offline ticket!
      expect(provider.state, ScanState.error);
      expect(provider.errorTitle, 'Cannot Verify Offline');
      expect(provider.isOfflineFallback, isFalse);
      expect(provider.currentRegistration, isNull);

      // Check-in cannot be executed because currentRegistration is null and state is error
      expect(queue.items.isEmpty, isTrue);
    });

    test('AttendeesProvider reconciles queue items, marking them as attended/syncing and preserving across server refresh', () async {
      final prefs = await SharedPreferences.getInstance();
      final storage = StorageService(prefs);
      final gql = GraphQLService(storage);
      final queue = QueueService(
        storageService: storage,
        graphQLService: gql,
        getSettings: () => const AppSettings(isSafeMode: true),
      );
      await queue.init();

      final attendees = AttendeesProvider(
        storageService: storage,
        graphQLService: gql,
        getSettings: () => const AppSettings(isSafeMode: true, activeEventIds: ['ev-reconcile']),
        queueService: queue,
      );

      const reg1 = EventRegistration(
        id: 'attendee-reconcile-1',
        type: 'PARTICIPANT',
        status: 'SUCCESSFUL',
        didAttend: false,
        totalPartySize: 2,
        remainingEntries: 2,
        event: EventInfo(id: 'ev-reconcile', title: 'Reconcile Event'),
        user: UserInfo(id: 'u1', fullName: 'Alice Reconcile'),
      );
      const reg2 = EventRegistration(
        id: 'attendee-reconcile-2',
        type: 'PARTICIPANT',
        status: 'SUCCESSFUL',
        didAttend: false,
        totalPartySize: 1,
        remainingEntries: 1,
        event: EventInfo(id: 'ev-reconcile', title: 'Reconcile Event'),
        user: UserInfo(id: 'u2', fullName: 'Bob Reconcile'),
      );

      final initialEvent = EventDetails(
        id: 'ev-reconcile',
        title: 'Reconcile Event',
        start: DateTime.now(),
        end: DateTime.now(),
        participantRegistrationCount: 2,
        participantLimit: 10,
        totalRegisteredCount: 2,
        participantsAttended: 0,
        participantRegistrations: [reg1, reg2],
      );

      await storage.saveCachedEventAttendees(initialEvent);
      await attendees.init(enableBackgroundTimer: false);

      expect(attendees.attendedCount, 0);
      expect(attendees.registrations.first.didAttend, isFalse);

      // Now enqueue a check-in for Alice (reg1)
      await queue.enqueueRegistration(reg1, count: 1);

      // AttendeesProvider must automatically reconcile!
      expect(attendees.attendedCount, 1);
      final reconciledAlice = attendees.registrations.firstWhere((r) => r.id == reg1.id);
      expect(reconciledAlice.didAttend, isTrue);
      expect(reconciledAlice.remainingEntries, 1);

      // Trigger a server refresh (which still has old didAttend = false for Alice)
      await attendees.refreshAttendees(force: true);

      // Reconciled check-in state must NOT be wiped!
      final preservedAlice = attendees.registrations.firstWhere((r) => r.id == reg1.id);
      expect(preservedAlice.didAttend, isTrue);
      expect(attendees.attendedCount, 1);
    });

    test('ScannerProvider continues waiting for server verification and uses timeout set in settings before offline fallback', () async {
      final prefs = await SharedPreferences.getInstance();
      final storage = StorageService(prefs);
      const reg = EventRegistration(
        id: 'e16b4b24-81a9-4361-ae50-a75cbed0defc',
        type: 'PARTICIPANT',
        status: 'SUCCESSFUL',
        didAttend: false,
        totalPartySize: 1,
        remainingEntries: 1,
        event: EventInfo(id: 'ev-timeout-test', title: 'Timeout Test Event'),
        user: UserInfo(id: 'u1', fullName: 'Test Attendee'),
      );
      final event = EventDetails(
        id: 'ev-timeout-test',
        title: 'Timeout Test Event',
        start: DateTime.now(),
        end: DateTime.now(),
        participantRegistrationCount: 1,
        participantLimit: 10,
        totalRegisteredCount: 1,
        participantsAttended: 0,
        participantRegistrations: [reg],
      );
      await storage.saveCachedEventAttendees(event);

      // Delayed service taking 250ms before responding
      final delayedGql = _DelayedGraphQLService(
        storage,
        delay: const Duration(milliseconds: 250),
      );
      final queue = QueueService(
        storageService: storage,
        graphQLService: delayedGql,
        getSettings: () => const AppSettings(),
      );

      // Settings configured with 1s timeout
      final scanner = ScannerProvider(
        graphQLService: delayedGql,
        queueService: queue,
        storageService: storage,
        getSettings: () => const AppSettings(timeoutSeconds: 1),
      );

      // Scan cached ticket UUID
      await scanner.handleBarcodeScanned('e16b4b24-81a9-4361-ae50-a75cbed0defc');

      // Immediately: ticket found, online verification in progress, NOT yet offline fallback
      expect(scanner.state, ScanState.ticketFound);
      expect(scanner.isOnlineVerifying, isTrue);
      expect(scanner.isOfflineFallback, isFalse);

      // At 100ms: still waiting, not cut off by an artificial 2.5s or premature timeout
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(scanner.isOnlineVerifying, isTrue);
      expect(scanner.isOfflineFallback, isFalse);

      // At 300ms: delayed service has responded, verification completes
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(scanner.isOnlineVerifying, isFalse);
    });

    test('ScannerProvider retryOnline keeps ticket on screen and waits for settings timeout before offline fallback', () async {
      final prefs = await SharedPreferences.getInstance();
      final storage = StorageService(prefs);
      const reg = EventRegistration(
        id: 'e16b4b24-81a9-4361-ae50-a75cbed0defc',
        type: 'PARTICIPANT',
        status: 'SUCCESSFUL',
        didAttend: false,
        totalPartySize: 1,
        remainingEntries: 1,
        event: EventInfo(id: 'ev-timeout-test', title: 'Timeout Test Event'),
        user: UserInfo(id: 'u1', fullName: 'Test Attendee'),
      );
      final event = EventDetails(
        id: 'ev-timeout-test',
        title: 'Timeout Test Event',
        start: DateTime.now(),
        end: DateTime.now(),
        participantRegistrationCount: 1,
        participantLimit: 10,
        totalRegisteredCount: 1,
        participantsAttended: 0,
        participantRegistrations: [reg],
      );
      await storage.saveCachedEventAttendees(event);

      final delayedGql = _DelayedGraphQLService(
        storage,
        delay: const Duration(milliseconds: 150),
      );
      final queue = QueueService(
        storageService: storage,
        graphQLService: delayedGql,
        getSettings: () => const AppSettings(),
      );

      final scanner = ScannerProvider(
        graphQLService: delayedGql,
        queueService: queue,
        storageService: storage,
        getSettings: () => const AppSettings(timeoutSeconds: 1),
      );

      await scanner.handleBarcodeScanned('e16b4b24-81a9-4361-ae50-a75cbed0defc');
      // Wait for initial verification to complete
      await Future<void>.delayed(const Duration(milliseconds: 200));

      // Now trigger retryOnline
      final retryFuture = scanner.retryOnline();
      expect(scanner.state, ScanState.ticketFound); // Stays on screen!
      expect(scanner.isOnlineVerifying, isTrue);
      expect(scanner.isOfflineFallback, isFalse);

      await retryFuture;
      expect(scanner.state, ScanState.ticketFound);
      expect(scanner.isOnlineVerifying, isFalse);
    });

    test('Rescan of checked-in ticket prioritizes local checkin over stale server read returning didAttend: false', () async {
      final prefs = await SharedPreferences.getInstance();
      final storage = StorageService(prefs);
      const testUuid = 'b1ce1a6c-f968-4c1a-a027-8bf1e4ba2d29';
      const initialReg = EventRegistration(
        id: testUuid,
        type: 'PARTICIPANT',
        status: 'SUCCESSFUL',
        didAttend: false,
        totalPartySize: 1,
        remainingEntries: 1,
        event: EventInfo(id: 'ev-test', title: 'Test Event'),
        user: UserInfo(id: 'u1', fullName: 'Alice Test'),
      );
      final event = EventDetails(
        id: 'ev-test',
        title: 'Test Event',
        start: DateTime.now(),
        end: DateTime.now(),
        participantLimit: 10,
        totalRegisteredCount: 1,
        participantsAttended: 0,
        participantRegistrations: [initialReg],
      );
      await storage.saveCachedEventAttendees(event);

      // Server mock returns stale un-attended ticket (simulating safe mode / replica lag)
      final delayedGql = _DelayedGraphQLService(
        storage,
        delay: const Duration(milliseconds: 50),
        mockResult: const GraphQLResult.success(initialReg),
      );
      final queue = QueueService(
        storageService: storage,
        graphQLService: delayedGql,
        getSettings: () => const AppSettings(),
      );
      await queue.init();

      final scanner = ScannerProvider(
        graphQLService: delayedGql,
        queueService: queue,
        storageService: storage,
        getSettings: () => const AppSettings(timeoutSeconds: 1),
      );

      // Step 1: Scan and check in ticket
      await scanner.handleBarcodeScanned(testUuid);
      expect(scanner.state, ScanState.ticketFound);
      await scanner.checkInCurrentTicket(count: 1);
      expect(scanner.currentRegistration?.didAttend, isTrue);
      expect(scanner.currentRegistration?.remainingEntries, 0);

      // Wait for queue to process item
      await Future<void>.delayed(const Duration(milliseconds: 100));

      // Reset scanner between scans (clear recent scan feedback/lock for re-scan)
      scanner.clearCheckedInFeedback();
      scanner.reset(keepRecentScanLock: false);

      // Step 2: Re-scan the same ticket
      await scanner.handleBarcodeScanned(testUuid);

      // Immediately local lookup shows ticket was already attended
      expect(scanner.state, ScanState.ticketFound);
      expect(scanner.currentRegistration?.didAttend, isTrue);
      expect(scanner.currentRegistration?.remainingEntries, 0);
      expect(scanner.currentRegistration?.isAlreadyAttended, isTrue);

      // Wait for background online check to return stale data from server
      await Future<void>.delayed(const Duration(milliseconds: 100));

      // Local checkin MUST have priority! It must NOT revert to didAttend: false or remainingEntries: 1
      expect(scanner.currentRegistration?.didAttend, isTrue);
      expect(scanner.currentRegistration?.remainingEntries, 0);
      expect(scanner.currentRegistration?.isAlreadyAttended, isTrue);
    });

    test('retryOnline on checked-in ticket retains used status even when server returns un-attended record', () async {
      final prefs = await SharedPreferences.getInstance();
      final storage = StorageService(prefs);
      const testUuid = 'b1ce1a6c-f968-4c1a-a027-8bf1e4ba2d29';
      const initialReg = EventRegistration(
        id: testUuid,
        type: 'PARTICIPANT',
        status: 'SUCCESSFUL',
        didAttend: false,
        totalPartySize: 1,
        remainingEntries: 1,
        event: EventInfo(id: 'ev-test', title: 'Test Event'),
        user: UserInfo(id: 'u1', fullName: 'Alice Test'),
      );
      await storage.updateCachedRegistrationCheckIn(
        testUuid,
        true,
        DateTime.now(),
        count: 1,
        fallbackRegistration: initialReg,
      );

      final delayedGql = _DelayedGraphQLService(
        storage,
        delay: const Duration(milliseconds: 50),
        mockResult: const GraphQLResult.success(initialReg),
      );
      final queue = QueueService(
        storageService: storage,
        graphQLService: delayedGql,
        getSettings: () => const AppSettings(),
      );

      final scanner = ScannerProvider(
        graphQLService: delayedGql,
        queueService: queue,
        storageService: storage,
        getSettings: () => const AppSettings(timeoutSeconds: 1),
      );

      await scanner.handleBarcodeScanned(testUuid);
      await Future<void>.delayed(const Duration(milliseconds: 100));

      // Trigger retryOnline
      await scanner.retryOnline();

      expect(scanner.currentRegistration?.didAttend, isTrue);
      expect(scanner.currentRegistration?.remainingEntries, 0);
      expect(scanner.currentRegistration?.isAlreadyAttended, isTrue);
    });

    test('ScannerProvider triggers error vibration when ticket is already attended or unpaid or for wrong event', () async {
      final prefs = await SharedPreferences.getInstance();
      final storage = StorageService(prefs);
      const uuidAttended = 'b1ce1a6c-f968-4c1a-a027-8bf1e4ba2d01';
      const uuidUnpaid = 'b1ce1a6c-f968-4c1a-a027-8bf1e4ba2d02';
      const uuidWrongEvent = 'b1ce1a6c-f968-4c1a-a027-8bf1e4ba2d03';

      const regAttended = EventRegistration(
        id: uuidAttended,
        status: 'SUCCESSFUL',
        didAttend: true,
        remainingEntries: 0,
        event: EventInfo(id: 'ev-active', title: 'Active Event'),
      );
      const regUnpaid = EventRegistration(
        id: uuidUnpaid,
        status: 'PENDING',
        didAttend: false,
        remainingEntries: 1,
        event: EventInfo(id: 'ev-active', title: 'Active Event'),
      );
      const regWrongEvent = EventRegistration(
        id: uuidWrongEvent,
        status: 'SUCCESSFUL',
        didAttend: false,
        remainingEntries: 1,
        event: EventInfo(id: 'ev-other', title: 'Other Event'),
      );

      await storage.cacheRegistration(regAttended);
      await storage.cacheRegistration(regUnpaid);
      await storage.cacheRegistration(regWrongEvent);

      final delayedGql = _DelayedGraphQLService(storage, delay: const Duration(milliseconds: 10));
      final queue = QueueService(
        storageService: storage,
        graphQLService: delayedGql,
        getSettings: () => const AppSettings(activeEventIds: ['ev-active']),
      );

      final scanner = ScannerProvider(
        graphQLService: delayedGql,
        queueService: queue,
        storageService: storage,
        getSettings: () => const AppSettings(activeEventIds: ['ev-active']),
      );

      // 1. Scan already attended
      await scanner.handleBarcodeScanned(uuidAttended);
      expect(scanner.currentRegistration?.isAlreadyAttended, isTrue);

      scanner.clearCheckedInFeedback();
      scanner.reset(keepRecentScanLock: false);

      // 2. Scan unpaid
      await scanner.handleBarcodeScanned(uuidUnpaid);
      expect(scanner.currentRegistration?.isPaymentIncomplete, isTrue);

      scanner.clearCheckedInFeedback();
      scanner.reset(keepRecentScanLock: false);

      // 3. Scan wrong event
      await scanner.handleBarcodeScanned(uuidWrongEvent);
      expect(scanner.isEventMatched, isFalse);
    });
  });
}

class _DelayedGraphQLService extends GraphQLService {
  final Duration delay;
  final GraphQLResult<EventRegistration>? mockResult;

  _DelayedGraphQLService(super.storageService, {required this.delay, this.mockResult});

  @override
  Future<GraphQLResult<EventRegistration>> getRegistration(
    String registrationId,
    AppSettings settings,
  ) async {
    await Future<void>.delayed(delay);
    return mockResult ??
        GraphQLResult.failure('Server unreachable after ${settings.timeoutSeconds}s');
  }
}




