import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'providers/attendees_provider.dart';
import 'providers/scanner_provider.dart';
import 'providers/settings_provider.dart';
import 'screens/attendees_screen.dart';
import 'screens/scanner_screen.dart';
import 'screens/settings_screen.dart';
import 'services/graphql_service.dart';
import 'services/queue_service.dart';
import 'services/storage_service.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'utils/jwt_utils.dart';
import 'utils/m3_motion.dart';
import 'utils/web_url_cleaner.dart';

Future<void> _handleIncomingWebAuth(SettingsProvider settingsProvider) async {
  try {
    final uri = Uri.base;

    // Check for direct URL token parameter (?token=... or #token=... or access_token=...)
    String? token = uri.queryParameters['token'] ?? uri.queryParameters['access_token'];
    if (token == null || token.isEmpty) {
      if (uri.hasFragment) {
        final frag = uri.fragment;
        final match = RegExp(r'(?:^|[&?])(?:token|access_token)=([^&]+)').firstMatch(frag);
        if (match != null) {
          token = Uri.decodeComponent(match.group(1)!);
        }
      }
    }

    if (token != null && token.isNotEmpty && token.startsWith('eyJ')) {
      if (!JwtUtils.isExpired(token)) {
        settingsProvider.setBearerToken(token);
      }
      cleanBrowserUrl();
    }
  } catch (e) {
    debugPrint('Web auth ingestion error: $e');
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
    ),
  );

  final storageService = await StorageService.init();
  final graphQLService = GraphQLService(storageService);
  final settingsProvider = SettingsProvider(storageService);

  if (kIsWeb) {
    await _handleIncomingWebAuth(settingsProvider);
  }

  final queueService = QueueService(
    storageService: storageService,
    graphQLService: graphQLService,
    getSettings: () => settingsProvider.settings,
  );
  await queueService.init();

  final attendeesProvider = AttendeesProvider(
    storageService: storageService,
    graphQLService: graphQLService,
    getSettings: () => settingsProvider.settings,
    queueService: queueService,
  );
  await attendeesProvider.init();

  final scannerProvider = ScannerProvider(
    graphQLService: graphQLService,
    queueService: queueService,
    storageService: storageService,
    getSettings: () => settingsProvider.settings,
  );

  runApp(
    MultiProvider(
      providers: [
        Provider<StorageService>.value(value: storageService),
        Provider<GraphQLService>.value(value: graphQLService),
        ChangeNotifierProvider<SettingsProvider>.value(value: settingsProvider),
        ChangeNotifierProvider<QueueService>.value(value: queueService),
        ChangeNotifierProvider<AttendeesProvider>.value(value: attendeesProvider),
        ChangeNotifierProvider<ScannerProvider>.value(value: scannerProvider),
      ],
      child: const TurnstileApp(),
    ),
  );
}

class TurnstileApp extends StatelessWidget {
  const TurnstileApp({super.key});

  @override
  Widget build(BuildContext context) {
    const lightColorScheme = ColorScheme(
      brightness: Brightness.light,
      primary: Color(0xFF005AC1),
      onPrimary: Color(0xFFFFFFFF),
      primaryContainer: Color(0xFFD8E2FF),
      onPrimaryContainer: Color(0xFF001A41),
      secondary: Color(0xFF575E71),
      onSecondary: Color(0xFFFFFFFF),
      secondaryContainer: Color(0xFFDBE2F9),
      onSecondaryContainer: Color(0xFF141B2C),
      tertiary: Color(0xFF715573),
      onTertiary: Color(0xFFFFFFFF),
      tertiaryContainer: Color(0xFFFBD7FC),
      onTertiaryContainer: Color(0xFF29132D),
      error: Color(0xFFBA1A1A),
      onError: Color(0xFFFFFFFF),
      errorContainer: Color(0xFFFFDAD6),
      onErrorContainer: Color(0xFF410002),
      surface: Color(0xFFFDFBFF),
      onSurface: Color(0xFF1B1B1F),
      onSurfaceVariant: Color(0xFF44474F),
      outline: Color(0xFF74777F),
      outlineVariant: Color(0xFFC4C6D0),
      surfaceContainerLowest: Color(0xFFFFFFFF),
      surfaceContainerLow: Color(0xFFF7F2FA),
      surfaceContainer: Color(0xFFF1EDF4),
      surfaceContainerHigh: Color(0xFFEBE7EF),
      surfaceContainerHighest: Color(0xFFE5E1E9),
    );

    const darkColorScheme = ColorScheme(
      brightness: Brightness.dark,
      primary: Color(0xFFADC6FF),
      onPrimary: Color(0xFF002E69),
      primaryContainer: Color(0xFF004494),
      onPrimaryContainer: Color(0xFFD8E2FF),
      secondary: Color(0xFFBFC6DC),
      onSecondary: Color(0xFF293041),
      secondaryContainer: Color(0xFF3F4759),
      onSecondaryContainer: Color(0xFFDBE2F9),
      tertiary: Color(0xFFDEBCDF),
      onTertiary: Color(0xFF402843),
      tertiaryContainer: Color(0xFF583E5B),
      onTertiaryContainer: Color(0xFFFBD7FC),
      error: Color(0xFFFFB4AB),
      onError: Color(0xFF690005),
      errorContainer: Color(0xFF93000A),
      onErrorContainer: Color(0xFFFFDAD6),
      surface: Color(0xFF131316),
      onSurface: Color(0xFFE3E2E6),
      onSurfaceVariant: Color(0xFFC4C6D0),
      outline: Color(0xFF8E9099),
      outlineVariant: Color(0xFF44474F),
      surfaceContainerLowest: Color(0xFF0E0E11),
      surfaceContainerLow: Color(0xFF1B1B1F),
      surfaceContainer: Color(0xFF1F1F23),
      surfaceContainerHigh: Color(0xFF2A2A2E),
      surfaceContainerHighest: Color(0xFF353439),
    );

    return MaterialApp(
      title: 'Turnstile Check-In',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: lightColorScheme,
        cardTheme: CardThemeData(
          elevation: 0,
          color: lightColorScheme.surfaceContainerLow,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(M3Shape.cornerMedium),
            side: BorderSide(color: lightColorScheme.outlineVariant, width: 0.8),
          ),
        ),
        navigationBarTheme: NavigationBarThemeData(
          elevation: 0,
          backgroundColor: lightColorScheme.surfaceContainer,
          indicatorColor: lightColorScheme.secondaryContainer,
          labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
          height: 80,
          indicatorShape: const StadiumBorder(),
        ),
        appBarTheme: AppBarTheme(
          elevation: 0,
          backgroundColor: lightColorScheme.surface,
          foregroundColor: lightColorScheme.onSurface,
          centerTitle: true,
        ),
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorScheme: darkColorScheme,
        cardTheme: CardThemeData(
          elevation: 0,
          color: darkColorScheme.surfaceContainerLow,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(M3Shape.cornerMedium),
            side: BorderSide(color: darkColorScheme.outlineVariant, width: 0.8),
          ),
        ),
        navigationBarTheme: NavigationBarThemeData(
          elevation: 0,
          backgroundColor: darkColorScheme.surfaceContainer,
          indicatorColor: darkColorScheme.secondaryContainer,
          labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
          height: 80,
          indicatorShape: const StadiumBorder(),
        ),
        appBarTheme: AppBarTheme(
          elevation: 0,
          backgroundColor: darkColorScheme.surface,
          foregroundColor: darkColorScheme.onSurface,
          centerTitle: true,
        ),
      ),
      themeMode: ThemeMode.system,
      home: const MainNavigationShell(),
    );
  }
}

class MainNavigationShell extends StatefulWidget {
  const MainNavigationShell({super.key});

  @override
  State<MainNavigationShell> createState() => _MainNavigationShellState();
}

class _MainNavigationShellState extends State<MainNavigationShell> {
  int _currentIndex = 0;
  final GlobalKey<AttendeesScreenState> _attendeesKey = GlobalKey<AttendeesScreenState>();

  @override
  Widget build(BuildContext context) {
    final queueService = context.watch<QueueService>();
    final storageService = context.read<StorageService>();
    final pendingCount = queueService.pendingCount;
    final failedCount = queueService.failedManualCount;

    final pages = [
      ScannerScreen(
        onNavigateToQueue: () {
          M3Haptics.vibrateSelection();
          setState(() => _currentIndex = 1);
          _attendeesKey.currentState?.switchToQueueTab();
        },
      ),
      AttendeesScreen(key: _attendeesKey),
      SettingsScreen(storageService: storageService),
    ];

    return Scaffold(
      body: AnimatedSwitcher(
        duration: M3Motion.durationDefaultEffects,
        switchInCurve: M3Motion.expressiveDefaultEffects,
        switchOutCurve: M3Motion.expressiveDefaultEffects,
        transitionBuilder: (child, animation) {
          return FadeTransition(
            opacity: animation,
            child: child,
          );
        },
        child: KeyedSubtree(
          key: ValueKey<int>(_currentIndex),
          child: pages[_currentIndex],
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (idx) {
          M3Haptics.vibrateSelection();
          setState(() => _currentIndex = idx);
          if (idx == 1) {
            context.read<AttendeesProvider>().refresh();
          }
        },
        destinations: [
          const NavigationDestination(
            icon: Icon(Icons.qr_code_scanner_outlined),
            selectedIcon: Icon(Icons.qr_code_scanner),
            label: 'Scanner',
          ),
          NavigationDestination(
            icon: Badge(
              isLabelVisible: pendingCount > 0 || failedCount > 0,
              label: Text('${pendingCount + failedCount}'),
              backgroundColor: failedCount > 0 ? Colors.red : Colors.amber.shade900,
              child: const Icon(Icons.people_outline),
            ),
            selectedIcon: Badge(
              isLabelVisible: pendingCount > 0 || failedCount > 0,
              label: Text('${pendingCount + failedCount}'),
              backgroundColor: failedCount > 0 ? Colors.red : Colors.amber.shade900,
              child: const Icon(Icons.people),
            ),
            label: 'Attendees',
          ),
          const NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: 'Settings',
          ),
        ],
      ),
    );
  }
}
