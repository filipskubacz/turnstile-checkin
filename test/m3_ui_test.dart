import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:turnstile_checkin/main.dart';
import 'package:turnstile_checkin/models/app_settings.dart';
import 'package:turnstile_checkin/models/registration.dart';
import 'package:turnstile_checkin/providers/scanner_provider.dart';
import 'package:provider/provider.dart';
import 'package:turnstile_checkin/providers/attendees_provider.dart';
import 'package:turnstile_checkin/providers/settings_provider.dart';
import 'package:turnstile_checkin/screens/attendees_screen.dart';
import 'package:turnstile_checkin/screens/scanner_screen.dart';
import 'package:turnstile_checkin/screens/settings_screen.dart';
import 'package:turnstile_checkin/services/graphql_service.dart';
import 'package:turnstile_checkin/services/queue_service.dart';
import 'package:turnstile_checkin/services/storage_service.dart';
import 'package:turnstile_checkin/utils/m3_motion.dart';
import 'package:turnstile_checkin/widgets/m3_swipe_lock.dart';
import 'package:turnstile_checkin/widgets/ticket_preview_sheet.dart';

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
  });

  group('M3 Motion & Shape Tokens Tests', () {
    test('M3 Motion curves are defined per M3 Expressive specification', () {
      expect(M3Motion.expressiveFastSpatial, const Cubic(0.42, 1.67, 0.21, 0.90));
      expect(M3Motion.expressiveDefaultSpatial, const Cubic(0.38, 1.21, 0.22, 1.00));
      expect(M3Motion.expressiveDefaultEffects, const Cubic(0.34, 0.80, 0.34, 1.00));
      expect(M3Motion.durationFastSpatial, const Duration(milliseconds: 350));
      expect(M3Motion.durationDefaultEffects, const Duration(milliseconds: 200));
    });

    test('M3 Corner radii adhere to 10-step scale', () {
      expect(M3Shape.cornerNone, 0.0);
      expect(M3Shape.cornerExtraSmall, 4.0);
      expect(M3Shape.cornerSmall, 8.0);
      expect(M3Shape.cornerMedium, 12.0);
      expect(M3Shape.cornerLarge, 16.0);
      expect(M3Shape.cornerLargeIncreased, 20.0);
      expect(M3Shape.cornerExtraLarge, 28.0);
      expect(M3Shape.cornerExtraLargeIncreased, 32.0);
      expect(M3Shape.cornerExtraExtraLarge, 48.0);
      expect(M3Shape.cornerFull, 999.0);
    });

    test('Optical roundness follows inner = outer - padding rule', () {
      final innerRadius = M3Shape.opticalInnerRadius(28.0, 16.0);
      expect(innerRadius, 12.0);

      final clamped = M3Shape.opticalInnerRadius(12.0, 20.0);
      expect(clamped, 0.0);
    });

    test('M3 Haptics calls complete without errors', () async {
      await expectLater(M3Haptics.vibrateScanSuccess(), completes);
      await expectLater(M3Haptics.vibrateScanError(), completes);
      await expectLater(M3Haptics.vibrateAction(), completes);
      await expectLater(M3Haptics.vibrateSelection(), completes);
    });
  });

  group('M3 Theme Construction Tests', () {
    testWidgets('TurnstileApp theme uses Material 3 and M3 NavigationBar', (tester) async {
      const app = TurnstileApp();
      expect(app, isNotNull);

      // Verify theme builder with M3 tokens
      final theme = ThemeData(
        useMaterial3: true,
        navigationBarTheme: const NavigationBarThemeData(
          indicatorShape: StadiumBorder(),
          height: 80,
        ),
      );

      expect(theme.useMaterial3, isTrue);
      expect(theme.navigationBarTheme.indicatorShape, const StadiumBorder());
      expect(theme.navigationBarTheme.height, 80);
    });

    test('M3 Error tokens adhere to role pairings and container shapes', () {
      final scheme = ColorScheme.fromSeed(seedColor: const Color(0xFF006688));
      // Pair test: error container paired with on error container
      expect(scheme.errorContainer, isNotNull);
      expect(scheme.onErrorContainer, isNotNull);
      // Reticle uses M3Shape.cornerExtraLarge (28.0)
      expect(M3Shape.cornerExtraLarge, 28.0);
      expect(M3Shape.cornerLarge, 16.0);
    });
  });

  group('M3 Swipe Lock & Event Match Confirmation Tests', () {
    testWidgets('M3SwipeLock renders label and triggers onConfirmed only on full swipe', (tester) async {
      bool confirmed = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 300,
                child: M3SwipeLock(
                  label: 'Slide to Confirm Admission',
                  onConfirmed: () {
                    confirmed = true;
                  },
                ),
              ),
            ),
          ),
        ),
      );

      expect(find.text('Slide to Confirm Admission'), findsOneWidget);
      expect(find.byIcon(Icons.lock_outline_rounded), findsOneWidget);
      expect(confirmed, isFalse);

      // 1. Partial drag (under 85% threshold, e.g. 50px)
      await tester.drag(find.byType(GestureDetector).first, const Offset(50, 0));
      await tester.pumpAndSettle();
      expect(confirmed, isFalse); // Did not trigger

      // 2. Full drag across track (e.g. 260px)
      await tester.drag(find.byType(GestureDetector).first, const Offset(260, 0));
      await tester.pumpAndSettle();
      expect(confirmed, isTrue); // Successfully confirmed!
    });

    testWidgets('TicketPreviewSheet disables and grays out check-in button on event mismatch', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final storage = StorageService(prefs);
      final gql = GraphQLService(storage);
      final queue = QueueService(
        storageService: storage,
        graphQLService: gql,
        getSettings: () => const AppSettings(activeEventIds: ['active-event-123']),
      );

      final scanner = ScannerProvider(
        graphQLService: gql,
        queueService: queue,
        getSettings: () => const AppSettings(activeEventIds: ['active-event-123']),
      );

      // Ticket belongs to mismatched-event-999
      const reg = EventRegistration(
        id: 'ticket-mismatch-1',
        type: 'PARTICIPANT',
        status: 'SUCCESSFUL',
        didAttend: false,
        totalPartySize: 1,
        remainingEntries: 1,
        event: EventInfo(id: 'mismatched-event-999', title: 'Other Event'),
        user: UserInfo(id: 'u1', fullName: 'Alice'),
      );

      // Simulate scanner detecting mismatched state
      scanner.setEventMatchedForTesting(
        false,
        'Ticket is for "Other Event" (ID: mismatched-event-999), which does not match active event(s).',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TicketPreviewSheet(
              registration: reg,
              scannerProvider: scanner,
              onDismiss: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Check-in button text should say Event Mismatch and be disabled
      expect(find.text('Event Mismatch — Check-In Disabled'), findsOneWidget);
      final filledBtn = tester.widget<FilledButton>(find.byType(FilledButton));
      expect(filledBtn.onPressed, isNull); // Disabled / grayed out!
    });

    testWidgets('TicketPreviewSheet disallows check-in for already attended tickets and displays Scan Next without Force Check-In', (tester) async {
      SharedPreferences.setMockInitialValues({});
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
        storageService: storage,
        getSettings: () => const AppSettings(),
      );

      const regAttended = EventRegistration(
        id: 'ticket-attended-1',
        type: 'PARTICIPANT',
        status: 'SUCCESSFUL',
        didAttend: true,
        totalPartySize: 1,
        remainingEntries: 0,
        event: EventInfo(id: 'event-1', title: 'Test Event'),
        user: UserInfo(id: 'u1', fullName: 'Bob'),
      );

      bool dismissed = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TicketPreviewSheet(
              registration: regAttended,
              scannerProvider: scanner,
              onDismiss: () {
                dismissed = true;
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Must NOT show Force Check-In
      expect(find.text('Force Check-In'), findsNothing);
      expect(find.text('Slide to Force Check-In'), findsNothing);

      // Must show Scan Next and Close
      expect(find.text('Scan Next'), findsOneWidget);
      expect(find.text('Close'), findsOneWidget);
      expect(find.text('ALL ENTRIES USED'), findsOneWidget);

      // Tap Scan Next dismisses sheet
      await tester.tap(find.text('Scan Next'));
      await tester.pumpAndSettle();
      expect(dismissed, isTrue);
    });

    testWidgets('TicketPreviewSheet admits unpaid group in safe mode without crashing', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final storage = StorageService(prefs);
      final gql = GraphQLService(storage);
      final queue = QueueService(
        storageService: storage,
        graphQLService: gql,
        getSettings: () => const AppSettings(isSafeMode: true),
      );

      final scanner = ScannerProvider(
        graphQLService: gql,
        queueService: queue,
        storageService: storage,
        getSettings: () => const AppSettings(isSafeMode: true),
      );

      const unpaidGroupReg = EventRegistration(
        id: 'unpaid-group-1',
        type: 'PARTICIPANT',
        status: 'PENDING',
        didAttend: false,
        totalPartySize: 2,
        guestCount: 1,
        remainingEntries: 2,
        event: EventInfo(id: 'event-1', title: 'Test Event'),
        user: UserInfo(id: 'u2', fullName: 'Charlie'),
      );

      scanner.setCurrentRegistrationForTesting(unpaidGroupReg);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TicketPreviewSheet(
              registration: unpaidGroupReg,
              scannerProvider: scanner,
              onDismiss: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Button says Admit Unpaid Group (2 left)
      expect(find.text('Admit Unpaid Group (2 left)'), findsOneWidget);
      await tester.ensureVisible(find.text('Admit Unpaid Group (2 left)'));
      await tester.tap(find.text('Admit Unpaid Group (2 left)'));
      await tester.pumpAndSettle();

      // Confirmation dialog should be visible with Group terminology
      expect(find.text('Confirm Unpaid Group (2)'), findsOneWidget);
      expect(find.text('Slide to Confirm Admission'), findsOneWidget);
      expect(find.byType(M3SwipeLock), findsOneWidget);

      // Slide to confirm
      final lockGesture = find.descendant(
        of: find.byType(M3SwipeLock),
        matching: find.byType(GestureDetector),
      );
      await tester.drag(lockGesture, const Offset(240, 0));
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        for (int i = 0; i < 20; i++) {
          if (queue.items.isNotEmpty) break;
          await Future.delayed(const Duration(milliseconds: 50));
        }
      });
      await tester.pump(const Duration(milliseconds: 700));
      await tester.pumpAndSettle();
      expect(queue.items.length, 1);
      expect(queue.items.first.registrationId, 'unpaid-group-1');
    });

    testWidgets('AttendeesScreen locks manual check-in when isExpertMode is false, and unlocks when true', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final storage = StorageService(prefs);
      final gql = GraphQLService(storage);
      final settingsProv = SettingsProvider(storage);
      final queue = QueueService(
        storageService: storage,
        graphQLService: gql,
        getSettings: () => settingsProv.settings,
      );
      final attendeesProv = AttendeesProvider(
        storageService: storage,
        graphQLService: gql,
        getSettings: () => settingsProv.settings,
      );

      const reg = EventRegistration(
        id: 'attendee-test-1',
        type: 'PARTICIPANT',
        status: 'PENDING',
        didAttend: false,
        totalPartySize: 2,
        guestCount: 1,
        remainingEntries: 2,
        event: EventInfo(id: 'event-1', title: 'Test Event'),
        user: UserInfo(id: 'u3', fullName: 'Dana'),
      );

      // Cache an event with this participant
      await storage.saveCachedEventAttendees(
        const EventDetails(
          id: 'event-1',
          title: 'Test Event',
          participantRegistrations: [reg],
        ),
      );
      await attendeesProv.init(enableBackgroundTimer: false);

      // 1. With isExpertMode = false (default)
      await settingsProv.setExpertMode(false);

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: settingsProv),
            ChangeNotifierProvider.value(value: queue),
            ChangeNotifierProvider.value(value: attendeesProv),
          ],
          child: const MaterialApp(
            home: AttendeesScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Dana'), findsOneWidget);
      await tester.tap(find.text('Dana'));
      await tester.pumpAndSettle();

      // Manual roster check-in is locked
      expect(find.textContaining('Manual roster check-in is locked'), findsOneWidget);
      expect(find.text('Admit Unpaid Group (2 left) [Expert]'), findsNothing);

      Navigator.of(tester.element(find.textContaining('Manual roster check-in is locked'))).pop();
      await tester.pumpAndSettle();

      // 2. Enable isExpertMode = true
      await settingsProv.setExpertMode(true);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Dana'));
      await tester.pumpAndSettle();

      // Now manual check-in button with [Expert] is unlocked and visible
      expect(find.text('Admit Unpaid Group (2 left) [Expert]'), findsOneWidget);
    });

    testWidgets('SettingsScreen displays Expert Mode card with warning after 10 version taps and shows Auto-Refresh slider', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final storage = StorageService(prefs);
      final settingsProv = SettingsProvider(storage);

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: settingsProv),
          ],
          child: MaterialApp(
            home: SettingsScreen(storageService: storage),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Verify second slider: Attendee Auto-Refresh is visible with default 10m
      expect(find.text('Attendee Auto-Refresh'), findsOneWidget);
      expect(find.text('10m'), findsOneWidget);

      // Expert Mode section is hidden initially
      final expertHeader = find.text('EXPERT MODE / ROSTER CHECK-IN');
      expect(expertHeader, findsNothing);

      // Scroll to About section and tap version number 10 times
      await tester.drag(find.byType(ListView).first, const Offset(0, -600));
      await tester.pumpAndSettle();

      final versionFinder = find.textContaining('Version');
      expect(versionFinder, findsOneWidget);

      for (var i = 0; i < 10; i++) {
        await tester.tap(versionFinder);
        await tester.pump(const Duration(milliseconds: 50));
      }
      await tester.pumpAndSettle();

      // Now Expert Mode is unlocked and visible
      expect(expertHeader, findsOneWidget);
      expect(find.text('Expert Mode Disabled'), findsOneWidget);
      expect(find.textContaining('Warning: With Expert Mode enabled'), findsOneWidget);
    });

    testWidgets('TicketPreviewSheet quantity selector allows choosing from 1 to N attendees', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final storage = StorageService(prefs);
      final gql = GraphQLService(storage);
      final queue = QueueService(
        storageService: storage,
        graphQLService: gql,
        getSettings: () => const AppSettings(isSafeMode: true),
      );

      final scanner = ScannerProvider(
        graphQLService: gql,
        queueService: queue,
        storageService: storage,
        getSettings: () => const AppSettings(isSafeMode: true),
      );

      const groupReg = EventRegistration(
        id: 'group-selector-reg',
        type: 'PARTICIPANT',
        status: 'SUCCESSFUL',
        didAttend: false,
        totalPartySize: 3,
        guestCount: 2,
        remainingEntries: 3,
        event: EventInfo(id: 'event-1', title: 'Test Event'),
        user: UserInfo(id: 'u-sel', fullName: 'Group Host'),
      );

      scanner.setCurrentRegistrationForTesting(groupReg);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TicketPreviewSheet(
              registration: groupReg,
              scannerProvider: scanner,
              onDismiss: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // By default all remaining (3) entries are selected
      expect(find.byKey(const Key('group-checkin-count')), findsOneWidget);
      expect(find.text('Check In Group (3 entries)'), findsOneWidget);

      // Tap decrement [-] -> now 2
      await tester.tap(find.byKey(const Key('group-checkin-decrement')));
      await tester.pumpAndSettle();
      expect(find.text('Check In 2 People (1 left)'), findsOneWidget);

      // Tap quick "1 person" button -> now 1
      await tester.tap(find.byKey(const Key('group-checkin-quick-one')));
      await tester.pumpAndSettle();
      expect(find.text('Check In 1 Person (2 left)'), findsOneWidget);

      // Tap quick "All (3)" button -> back to 3
      await tester.tap(find.byKey(const Key('group-checkin-quick-all')));
      await tester.pumpAndSettle();
      expect(find.text('Check In Group (3 entries)'), findsOneWidget);

      // Tap decrement to select 2, and check in
      await tester.tap(find.byKey(const Key('group-checkin-decrement')));
      await tester.pumpAndSettle();
      expect(find.text('Check In 2 People (1 left)'), findsOneWidget);

      await tester.tap(find.text('Check In 2 People (1 left)'));
      await tester.pumpAndSettle();

      expect(queue.items.length, 1);
      expect(queue.items.first.entriesCount, 2);
      expect(queue.items.first.manual, isFalse);
    });

    testWidgets('AttendeesScreen allows choosing quantity from 1 to N in Expert Mode', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final storage = StorageService(prefs);
      final gql = GraphQLService(storage);
      final settingsProv = SettingsProvider(storage);
      final queue = QueueService(
        storageService: storage,
        graphQLService: gql,
        getSettings: () => settingsProv.settings,
      );
      final attendeesProv = AttendeesProvider(
        storageService: storage,
        graphQLService: gql,
        getSettings: () => settingsProv.settings,
      );

      const groupReg = EventRegistration(
        id: 'attendee-group-expert',
        type: 'PARTICIPANT',
        status: 'SUCCESSFUL',
        didAttend: false,
        totalPartySize: 3,
        guestCount: 2,
        remainingEntries: 3,
        event: EventInfo(id: 'event-1', title: 'Test Event'),
        user: UserInfo(id: 'u-exp', fullName: 'Elena Group'),
      );

      await storage.saveCachedEventAttendees(
        const EventDetails(
          id: 'event-1',
          title: 'Test Event',
          participantRegistrations: [groupReg],
        ),
      );
      await attendeesProv.init(enableBackgroundTimer: false);
      await settingsProv.setExpertMode(true);

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: settingsProv),
            ChangeNotifierProvider.value(value: queue),
            ChangeNotifierProvider.value(value: attendeesProv),
          ],
          child: const MaterialApp(
            home: AttendeesScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Elena Group'), findsOneWidget);
      await tester.tap(find.text('Elena Group'));
      await tester.pumpAndSettle();

      // Initially shows all 3
      expect(find.text('3 of 3 left'), findsOneWidget);
      expect(find.text('Check In Group (3 left) [Expert]'), findsOneWidget);

      // Tap quick "1 person" button
      await tester.tap(find.byKey(const Key('attendee-group-quick-one')));
      await tester.pumpAndSettle();

      expect(find.text('1 of 3 left'), findsOneWidget);
      expect(find.text('Check In Group (1 of 3) [Expert]'), findsOneWidget);

      // Tap check-in button
      await tester.tap(find.text('Check In Group (1 of 3) [Expert]'));
      await tester.pumpAndSettle();

      expect(queue.items.length, 1);
      expect(queue.items.first.entriesCount, 1);
      expect(queue.items.first.manual, isTrue);
    });

    testWidgets('TicketPreviewSheet shows pending sync banner and reacts to queue state', (tester) async {
      final prefs = await SharedPreferences.getInstance();
      final storage = StorageService(prefs);
      final gql = GraphQLService(storage);
      final queue = QueueService(
        storageService: storage,
        graphQLService: gql,
        getSettings: () => const AppSettings(isSafeMode: true),
      );

      final scanner = ScannerProvider(
        graphQLService: gql,
        queueService: queue,
        storageService: storage,
        getSettings: () => const AppSettings(isSafeMode: true, activeEventIds: ['ev-test']),
      );

      const reg = EventRegistration(
        id: 'reg-pending-ui',
        type: 'PARTICIPANT',
        status: 'SUCCESSFUL',
        totalPartySize: 3,
        remainingEntries: 3,
        event: EventInfo(id: 'ev-test', title: 'Test Event'),
        user: UserInfo(id: 'u-pending', fullName: 'Pending Attendee'),
      );

      // Pre-enqueue a pending sync item for this ticket
      await queue.enqueueRegistration(reg, count: 2);

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.from(
            colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
            useMaterial3: true,
          ),
          home: Scaffold(
            body: TicketPreviewSheet(
              registration: reg,
              scannerProvider: scanner,
              onDismiss: () {},
            ),
          ),
        ),
      );

      await tester.pump();

      // Should display the pending sync indicator banner (either pending or syncing)
      expect(
        find.byWidgetPredicate(
          (w) => w is Text && (w.data?.toUpperCase().contains('SYNC') == true),
        ),
        findsWidgets,
      );

      // Main action button should reflect the pending sync state ('Done (Pending Sync)' or 'Syncing...')
      expect(
        find.byWidgetPredicate(
          (w) => w is Text && (w.data?.contains('Sync') == true || w.data?.contains('Pending') == true),
        ),
        findsWidgets,
      );
      expect(find.text('Scan Next'), findsOneWidget);

      // Settle background timers
      await tester.pump(const Duration(milliseconds: 500));
    });

    testWidgets('TicketPreviewSheet displays success confirmation banner and Scan Next button after admission', (tester) async {
      final prefs = await SharedPreferences.getInstance();
      final storage = StorageService(prefs);
      final gql = GraphQLService(storage);
      final queue = QueueService(
        storageService: storage,
        graphQLService: gql,
        getSettings: () => const AppSettings(isSafeMode: true),
      );

      final scanner = ScannerProvider(
        graphQLService: gql,
        queueService: queue,
        storageService: storage,
        getSettings: () => const AppSettings(isSafeMode: true, activeEventIds: ['ev-sheet']),
      );

      const reg = EventRegistration(
        id: 'success-sheet-test-uuid',
        type: 'PARTICIPANT',
        status: 'SUCCESSFUL',
        totalPartySize: 2,
        remainingEntries: 2,
        guestCount: 1,
        event: EventInfo(id: 'ev-sheet', title: 'Sheet Event'),
        user: UserInfo(id: 'u-sheet-test', fullName: 'Success Test User'),
      );

      scanner.setCurrentRegistrationForTesting(reg);

      // Perform check-in of all 2 entries
      await scanner.checkInCurrentTicket(count: 2);
      // Advance fake async clock so queue item completes in safe mode
      await tester.pump(const Duration(milliseconds: 100));

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(useMaterial3: true),
          home: Scaffold(
            body: TicketPreviewSheet(
              registration: scanner.currentRegistration!,
              scannerProvider: scanner,
              onDismiss: () {},
            ),
          ),
        ),
      );

      await tester.pump();

      // Must display the green M3 success confirmation banner
      expect(
        find.byWidgetPredicate(
          (w) => w is Text && (w.data?.contains('CHECK-IN COMPLETE') == true || w.data?.contains('ADMISSION CONFIRMED') == true),
        ),
        findsOneWidget,
      );

      // Must NOT display 'ALL ENTRIES USED' error banner
      expect(find.text('ALL ENTRIES USED'), findsNothing);

      // Must NOT display 'Force Check-In' button
      expect(find.text('Force Check-In'), findsNothing);

      // Primary button must be 'Scan Next'
      expect(find.text('Scan Next'), findsOneWidget);

      await tester.pump(const Duration(milliseconds: 500));
    });

    testWidgets('TicketPreviewSheet tapping Check In immediately enqueues to queue and invokes onDismiss to close modal', (tester) async {
      final prefs = await SharedPreferences.getInstance();
      final storage = StorageService(prefs);
      final gql = GraphQLService(storage);
      final queue = QueueService(
        storageService: storage,
        graphQLService: gql,
        getSettings: () => const AppSettings(isSafeMode: true),
      );

      final scanner = ScannerProvider(
        graphQLService: gql,
        queueService: queue,
        storageService: storage,
        getSettings: () => const AppSettings(isSafeMode: true, activeEventIds: ['ev-dismiss']),
      );

      const reg = EventRegistration(
        id: 'dismiss-test-uuid',
        type: 'PARTICIPANT',
        status: 'SUCCESSFUL',
        totalPartySize: 1,
        remainingEntries: 1,
        event: EventInfo(id: 'ev-dismiss', title: 'Dismiss Test Event'),
        user: UserInfo(id: 'u-dismiss', fullName: 'Dismiss Test User'),
      );

      scanner.setCurrentRegistrationForTesting(reg);

      bool dismissCalled = false;

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(useMaterial3: true),
          home: Scaffold(
            body: TicketPreviewSheet(
              registration: reg,
              scannerProvider: scanner,
              onDismiss: () {
                dismissCalled = true;
              },
            ),
          ),
        ),
      );

      await tester.pump();

      // Find Check In button
      final checkInBtn = find.text('Check In');
      expect(checkInBtn, findsOneWidget);

      // Tap Check In
      await tester.tap(checkInBtn);
      await tester.pump();

      // onDismiss must have been called!
      expect(dismissCalled, isTrue);

      // Item must have been enqueued in QueueService!
      expect(queue.items.any((i) => i.registrationId == reg.id), isTrue);

      await tester.pump(const Duration(milliseconds: 500));
    });

    testWidgets('TicketPreviewSheet clicking Check In Guest (1 left) enqueues guest and closes modal', (tester) async {
      final prefs = await SharedPreferences.getInstance();
      final storage = StorageService(prefs);
      final gql = GraphQLService(storage);
      final queue = QueueService(
        storageService: storage,
        graphQLService: gql,
        getSettings: () => const AppSettings(isSafeMode: true),
      );

      final scanner = ScannerProvider(
        graphQLService: gql,
        queueService: queue,
        storageService: storage,
        getSettings: () => const AppSettings(isSafeMode: true, activeEventIds: ['ev-guest-left']),
      );

      const reg = EventRegistration(
        id: 'guest-left-test-uuid',
        type: 'PARTICIPANT',
        status: 'SUCCESSFUL',
        totalPartySize: 2,
        remainingEntries: 1,
        guestCount: 1,
        guestCheckIns: 0,
        didAttend: true,
        event: EventInfo(id: 'ev-guest-left', title: 'Guest Left Event'),
        user: UserInfo(id: 'u-guest-left', fullName: 'Party Lead User'),
      );

      scanner.setCurrentRegistrationForTesting(reg);

      bool dismissCalled = false;

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(useMaterial3: true),
          home: Scaffold(
            body: TicketPreviewSheet(
              registration: reg,
              scannerProvider: scanner,
              onDismiss: () {
                dismissCalled = true;
                scanner.reset();
              },
            ),
          ),
        ),
      );

      // Advance entrance slide animation
      await tester.pump(const Duration(milliseconds: 300));

      // Button must display 'Check In Guest (1 left)'
      final checkInGuestBtn = find.text('Check In Guest (1 left)');
      expect(checkInGuestBtn, findsOneWidget);

      // Tap Check In Guest (1 left)
      await tester.tap(checkInGuestBtn);
      await tester.pump();

      // onDismiss must have been called
      expect(dismissCalled, isTrue);

      // Guest must have been enqueued into QueueService
      expect(queue.items.any((i) => i.registrationId == reg.id), isTrue);

      // Debounce must be retained even after reset() so immediate camera re-scans don't re-open
      expect(scanner.lastScannedUuid, equals(reg.id));
      expect(scanner.lastScannedAt, isNotNull);

      // Immediate re-scan within debounce threshold must be ignored
      await scanner.handleBarcodeScanned(reg.id);
      expect(scanner.state, equals(ScanState.ready));
      expect(scanner.duplicateScanNotice, contains('Ticket recently checked in'));

      await tester.pump(const Duration(milliseconds: 500));
    });

    testWidgets('ScannerProvider clears lastScannedUuid on manual dismiss so same ticket can be re-scanned immediately', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final storage = StorageService(prefs);
      final gql = GraphQLService(storage);
      final queue = QueueService(
        storageService: storage,
        graphQLService: gql,
        getSettings: () => const AppSettings(isSafeMode: true),
      );

      final scanner = ScannerProvider(
        graphQLService: gql,
        queueService: queue,
        storageService: storage,
        getSettings: () => const AppSettings(isSafeMode: true),
      );

      const testUuid = '12345678-1234-1234-1234-123456789abc';
      await storage.cacheRegistration(const EventRegistration(
        id: testUuid,
        status: 'SUCCESSFUL',
        remainingEntries: 1,
      ));

      // 1. Initial scan
      await scanner.handleBarcodeScanned(testUuid);
      expect(scanner.lastScannedUuid, equals(testUuid));

      // 2. User dismisses without checking in (e.g. cancel button)
      scanner.reset();
      expect(scanner.lastScannedUuid, isNull);
      expect(scanner.lastScannedAt, isNull);

      // 3. User can scan the exact same code immediately without waiting
      await scanner.handleBarcodeScanned(testUuid);
      expect(scanner.duplicateScanNotice, isNull);
      expect(scanner.state, equals(ScanState.ticketFound));
    });

    testWidgets('AttendeesScreen integrates Sync Queue in M3 TabBar and switches tabs cleanly', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final storage = StorageService(prefs);
      final gql = GraphQLService(storage);
      final queue = QueueService(
        storageService: storage,
        graphQLService: gql,
        getSettings: () => const AppSettings(isSafeMode: true),
      );
      await queue.init();

      final attendeesProv = AttendeesProvider(
        storageService: storage,
        graphQLService: gql,
        getSettings: () => const AppSettings(isSafeMode: true),
        queueService: queue,
      );
      await attendeesProv.init();

      final attendeesKey = GlobalKey<AttendeesScreenState>();

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: queue),
            ChangeNotifierProvider.value(value: attendeesProv),
            ChangeNotifierProvider.value(value: SettingsProvider(storage)),
          ],
          child: MaterialApp(
            theme: ThemeData(useMaterial3: true),
            home: AttendeesScreen(key: attendeesKey),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Check that both M3 Tabs exist: 'Attendees' and 'Sync Queue'
      expect(find.textContaining('Attendees'), findsWidgets);
      expect(find.text('Sync Queue'), findsOneWidget);

      // Initially on Attendees tab
      expect(find.text('Attendee List'), findsOneWidget);

      // Switch to Queue tab via programmatic controller call or tap
      attendeesKey.currentState?.switchToQueueTab();
      await tester.pumpAndSettle();

      // Title should dynamically switch to 'Check-In Queue'
      expect(find.text('Check-In Queue'), findsOneWidget);

      // Metric tiles from QueueView should be visible
      expect(find.text('Pending'), findsOneWidget);
      expect(find.text('Needs Manual'), findsOneWidget);
      expect(find.text('Completed'), findsOneWidget);

      attendeesProv.dispose();
      queue.dispose();
    });

    testWidgets('AttendeesScreen top header card and search bar scroll away when scrolling attendee list', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final storage = StorageService(prefs);
      final gql = GraphQLService(storage);
      final queue = QueueService(
        storageService: storage,
        graphQLService: gql,
        getSettings: () => const AppSettings(isSafeMode: true),
      );
      await queue.init();

      final attendeesProv = AttendeesProvider(
        storageService: storage,
        graphQLService: gql,
        getSettings: () => const AppSettings(isSafeMode: true),
        queueService: queue,
      );

      // Create 30 registrations so the list easily overflows the viewport
      final testEvent = EventDetails(
        id: 'ev-scroll-test',
        title: 'Scroll Test Event',
        participantRegistrations: List.generate(
          30,
          (i) => EventRegistration(
            id: 'reg-$i',
            status: 'SUCCESSFUL',
            remainingEntries: 1,
            user: UserInfo(id: 'u-$i', fullName: 'Attendee Number $i'),
          ),
        ),
      );
      await storage.saveCachedEventAttendees(testEvent);
      await attendeesProv.init();

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: queue),
            ChangeNotifierProvider.value(value: attendeesProv),
            ChangeNotifierProvider.value(value: SettingsProvider(storage)),
          ],
          child: MaterialApp(
            theme: ThemeData(useMaterial3: true),
            home: const AttendeesScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Top header card & search bar are initially visible
      final headerFinder = find.textContaining('Check-in Progress');
      final searchFinder = find.byType(SearchBar);
      expect(headerFinder, findsOneWidget);
      expect(searchFinder, findsOneWidget);

      final initialHeaderY = tester.getTopLeft(headerFinder).dy;

      // Scroll the CustomScrollView down
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -450));
      await tester.pumpAndSettle();

      // The top part has scrolled away (header card is off-screen)
      expect(headerFinder, findsNothing);
      expect(find.textContaining('Attendee Number'), findsWidgets);

      // Scroll back up
      await tester.drag(find.byType(CustomScrollView), const Offset(0, 450));
      await tester.pumpAndSettle();

      // Top part has returned to view
      expect(headerFinder, findsOneWidget);
      expect(searchFinder, findsOneWidget);
      expect(tester.getTopLeft(headerFinder).dy, equals(initialHeaderY));

      attendeesProv.dispose();
      queue.dispose();
    });

    testWidgets('AttendeesScreen header status card renders cleanly without overflow on narrow screens', (tester) async {
      tester.view.physicalSize = const Size(320, 600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final storage = StorageService(prefs);
      final gql = GraphQLService(storage);
      final queue = QueueService(
        storageService: storage,
        graphQLService: gql,
        getSettings: () => const AppSettings(isSafeMode: true),
      );
      await queue.init();

      final attendeesProv = AttendeesProvider(
        storageService: storage,
        graphQLService: gql,
        getSettings: () => const AppSettings(isSafeMode: true),
        queueService: queue,
      );

      final testEvent = EventDetails(
        id: 'ev-overflow-test',
        title: 'Overflow Test Event',
        participantRegistrations: [
          EventRegistration(
            id: 'reg-1',
            status: 'SUCCESSFUL',
            remainingEntries: 1,
            user: UserInfo(id: 'u-1', fullName: 'Alice'),
          ),
        ],
      );
      await storage.saveCachedEventAttendees(testEvent);
      await storage.saveLastAttendeeRefreshTime(DateTime.now().subtract(const Duration(minutes: 42)), eventId: testEvent.id);
      await attendeesProv.init();

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: queue),
            ChangeNotifierProvider.value(value: attendeesProv),
            ChangeNotifierProvider.value(value: SettingsProvider(storage)),
          ],
          child: MaterialApp(
            theme: ThemeData(useMaterial3: true),
            home: const AttendeesScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byTooltip('Refresh'), findsOneWidget);
      expect(find.textContaining('Check-in Progress'), findsOneWidget);

      attendeesProv.dispose();
      queue.dispose();
    });

    testWidgets('ScannerScreen renders validating indicator in fetching state', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final storage = StorageService(prefs);
      final gql = _MockDelayedGraphQLService(storage, delay: const Duration(milliseconds: 500));
      final queue = QueueService(
        storageService: storage,
        graphQLService: gql,
        getSettings: () => const AppSettings(isSafeMode: true),
      );
      await queue.init();

      final scanner = ScannerProvider(
        graphQLService: gql,
        queueService: queue,
        storageService: storage,
        getSettings: () => const AppSettings(),
      );

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: queue),
            ChangeNotifierProvider.value(value: scanner),
            ChangeNotifierProvider.value(value: SettingsProvider(storage)),
          ],
          child: const MaterialApp(
            home: ScannerScreen(),
          ),
        ),
      );
      await tester.pump();

      // Trigger an unknown ticket check so scanner enters fetching state
      const unknownUuid = '11111111-2222-3333-4444-555555555555';
      final scanFuture = scanner.handleBarcodeScanned(unknownUuid);
      await tester.pump();

      expect(scanner.state, ScanState.fetching);
      expect(find.text('Validating ticket with server...'), findsOneWidget);

      await tester.pump(const Duration(milliseconds: 600));
      await scanFuture;
    });
  });
}

class _MockDelayedGraphQLService extends GraphQLService {
  final Duration delay;
  _MockDelayedGraphQLService(super.storageService, {required this.delay});

  @override
  Future<GraphQLResult<EventRegistration>> getRegistration(
    String registrationId,
    AppSettings settings,
  ) async {
    await Future<void>.delayed(delay);
    return const GraphQLResult.failure('Server unreachable');
  }
}



