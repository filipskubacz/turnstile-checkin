import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/app_settings.dart';
import '../models/registration.dart';
import '../providers/attendees_provider.dart';
import '../providers/settings_provider.dart';
import '../services/graphql_service.dart';
import '../services/storage_service.dart';
import '../utils/jwt_utils.dart';
import '../utils/m3_motion.dart';
import 'web_auth_screen.dart';

class SettingsScreen extends StatefulWidget {
  final StorageService storageService;

  const SettingsScreen({super.key, required this.storageService});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late TextEditingController _tokenController;
  late TextEditingController _urlController;
  final TextEditingController _newEventIdController = TextEditingController();
  bool _obscureToken = true;

  static final RegExp _uuidRegex = RegExp(
    r'[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}',
  );
  final Map<String, EventInfo> _eventMetadata = {};

  static const String _appVersion = '1.0.1';
  int _versionTapCount = 0;
  bool _expertSectionUnlocked = false;

  @override
  void initState() {
    super.initState();
    final settings = context.read<SettingsProvider>().settings;
    _tokenController = TextEditingController(text: settings.bearerToken);
    _urlController = TextEditingController(text: settings.apiUrl);
    if (settings.isExpertMode) {
      _expertSectionUnlocked = true;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadMetadataForConfiguredEvents();
    });
  }

  void _onVersionTapped() {
    setState(() {
      _versionTapCount++;
      if (_versionTapCount >= 10 && !_expertSectionUnlocked) {
        _expertSectionUnlocked = true;
        M3Haptics.vibrateAction();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('🔓 Expert mode controls unlocked'),
            duration: Duration(seconds: 2),
          ),
        );
      } else if (_versionTapCount < 10) {
        final remaining = 10 - _versionTapCount;
        if (remaining <= 3) {
          M3Haptics.vibrateSelection();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('$remaining more tap${remaining == 1 ? '' : 's'} to unlock expert controls'),
              duration: const Duration(milliseconds: 800),
            ),
          );
        }
      }
    });
  }

  @override
  void dispose() {
    _tokenController.dispose();
    _urlController.dispose();
    _newEventIdController.dispose();
    super.dispose();
  }

  void _saveToken() {
    M3Haptics.vibrateAction();
    context.read<SettingsProvider>().setBearerToken(
      _tokenController.text.trim(),
    );
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Bearer auth token saved'),
        duration: Duration(seconds: 1),
      ),
    );
  }

  void _saveUrl() {
    M3Haptics.vibrateAction();
    context.read<SettingsProvider>().setApiUrl(_urlController.text.trim());
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('GraphQL Endpoint saved'),
        duration: Duration(seconds: 1),
      ),
    );
  }

  GraphQLService? _getGraphQLService() {
    try {
      return context.read<GraphQLService>();
    } catch (_) {
      return null;
    }
  }

  Future<void> _loadMetadataForConfiguredEvents() async {
    final settings = context.read<SettingsProvider>().settings;
    final gql = _getGraphQLService();
    if (gql == null) return;
    for (final id in settings.activeEventIds) {
      if (!_eventMetadata.containsKey(id)) {
        final res = await gql.loadEventDisplayData(id, settings);
        if (res.isSuccess && res.data != null && mounted) {
          setState(() {
            _eventMetadata[id] = res.data!;
          });
        }
      }
    }
  }

  void _addEventId([String? explicitInput]) {
    final raw = (explicitInput ?? _newEventIdController.text).trim();
    if (raw.isEmpty) return;

    final match = _uuidRegex.firstMatch(raw);
    if (match == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter a valid Event link or UUID'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    final id = match.group(0)!;
    M3Haptics.vibrateAction();
    context.read<SettingsProvider>().addEventId(id);
    if (explicitInput == null) {
      _newEventIdController.clear();
    }

    // Try resolving event display details
    final settings = context.read<SettingsProvider>().settings;
    final gql = _getGraphQLService();
    if (gql != null && !_eventMetadata.containsKey(id)) {
      gql.loadEventDisplayData(id, settings).then((res) {
        if (res.isSuccess && res.data != null && mounted) {
          setState(() {
            _eventMetadata[id] = res.data!;
          });
        }
      });
    }
  }

  Future<void> _openEventPickerSheet() async {
    M3Haptics.vibrateAction();
    final gql = _getGraphQLService();
    if (gql == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('GraphQL service unavailable'),
          duration: Duration(seconds: 1),
        ),
      );
      return;
    }
    final settings = context.read<SettingsProvider>().settings;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surfaceContainerLow,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(M3Shape.cornerExtraLarge), // 28dp M3 Bottom Sheet
        ),
      ),
      builder: (ctx) => _EventPickerSheet(
        graphQLService: gql,
        settings: settings,
        onEventSelected: (event) {
          setState(() {
            _eventMetadata[event.id] = event;
          });
          context.read<SettingsProvider>().addEventId(event.id);
        },
      ),
    );
  }

  static const String _githubRepoUrl = 'https://github.com/filipskubacz/turnstile-checkin';

  Future<void> _launchGitHubUrl() async {
    M3Haptics.vibrateAction();
    final uri = Uri.parse(_githubRepoUrl);
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {}
  }

  void _showImprintModal(BuildContext context, String imprintText) {
    M3Haptics.vibrateSelection();
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final text = imprintText.trim().isNotEmpty
        ? imprintText.trim()
        : 'No imprint configured. Define the IMPRINT environment variable to display legal disclosure here.';

    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(M3Shape.cornerExtraLarge), // 28dp M3 Dialog
          ),
          icon: Icon(Icons.gavel_rounded, color: colorScheme.primary, size: 28),
          title: const Text('Imprint'),
          content: SingleChildScrollView(
            child: SelectableText(
              text,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurface,
                height: 1.5,
              ),
            ),
          ),
          actions: [
            FilledButton.tonal(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }

  void _showOpenSourceLicenses(BuildContext context) {
    M3Haptics.vibrateSelection();
    showLicensePage(
      context: context,
      applicationName: 'Turnstile Check-In',
      applicationVersion: _appVersion,
      applicationIcon: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Icon(
          Icons.qr_code_scanner_rounded,
          size: 48,
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }

  Future<void> _openWebLogin() async {
    M3Haptics.vibrateAction();
    final loggedIn = await WebAuthScreen.show(context);
    if (loggedIn == true && mounted) {
      final token = context.read<SettingsProvider>().settings.bearerToken;
      setState(() {
        _tokenController.text = token;
      });
    }
  }

  Widget _buildAuthStatusCard(BuildContext context, String rawToken) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final token = rawToken.trim();

    if (token.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(M3Shape.cornerMedium), // 12dp
          border: Border.all(color: colorScheme.outlineVariant, width: 0.8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.key_off_rounded, color: colorScheme.onSurfaceVariant, size: 20),
                const SizedBox(width: 8),
                Text(
                  'No Session Active',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: colorScheme.onSurface,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'Sign in directly via the web portal to enable live check-ins and attendee list syncing.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  shape: const StadiumBorder(),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                icon: const Icon(Icons.login_rounded, size: 18),
                label: const Text('Log In via Web Portal', style: TextStyle(fontWeight: FontWeight.bold)),
                onPressed: _openWebLogin,
              ),
            ),
          ],
        ),
      );
    }

    final isExpired = JwtUtils.isExpired(token);
    final userIdentifier = JwtUtils.getUserIdentifier(token);
    final statusText = JwtUtils.formatExpiryStatus(token);

    if (isExpired) {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: colorScheme.errorContainer.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(M3Shape.cornerMedium),
          border: Border.all(color: colorScheme.error.withValues(alpha: 0.4), width: 0.8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.lock_clock_rounded, color: colorScheme.error, size: 20),
                const SizedBox(width: 8),
                Text(
                  'Session Expired',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: colorScheme.error,
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: colorScheme.error.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(M3Shape.cornerFull),
                  ),
                  child: Text(
                    statusText,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: colorScheme.error,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'Your login token is expired. Live check-ins will fail until you renew your session.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onErrorContainer,
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: colorScheme.error,
                  foregroundColor: colorScheme.onError,
                  shape: const StadiumBorder(),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text('Renew Web Session', style: TextStyle(fontWeight: FontWeight.bold)),
                onPressed: _openWebLogin,
              ),
            ),
          ],
        ),
      );
    }

    // Active & Valid
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.teal.shade50.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(M3Shape.cornerMedium),
        border: Border.all(color: Colors.teal.shade300, width: 0.8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.verified_user_rounded, color: Colors.teal.shade800, size: 20),
              const SizedBox(width: 8),
              Text(
                'Active Session',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: Colors.teal.shade900,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.teal.shade100,
                  borderRadius: BorderRadius.circular(M3Shape.cornerFull),
                ),
                child: Text(
                  statusText,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: Colors.teal.shade900,
                  ),
                ),
              ),
            ],
          ),
          if (userIdentifier != null) ...[
            const SizedBox(height: 4),
            Text(
              'Authenticated as: $userIdentifier',
              style: TextStyle(
                fontSize: 12,
                color: Colors.teal.shade800,
              ),
            ),
          ],
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.teal.shade900,
                side: BorderSide(color: Colors.teal.shade400),
                shape: const StadiumBorder(),
                padding: const EdgeInsets.symmetric(vertical: 10),
              ),
              icon: const Icon(Icons.open_in_browser_rounded, size: 16),
              label: const Text('Switch Account / Re-login', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
              onPressed: _openWebLogin,
            ),
          ),
        ],
      ),
    );
  }

  void _onToggleSafeMode(bool enabled) {
    M3Haptics.vibrateSelection();
    final settingsProvider = context.read<SettingsProvider>();
    if (!enabled) {
      // Switching to Live Mode: Show Warning Dialog with M3 Dialog (28dp corners)
      showDialog(
        context: context,
        builder: (ctx) {
          final theme = Theme.of(ctx);
          final colorScheme = theme.colorScheme;
          return AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(
                M3Shape.cornerExtraLarge,
              ), // 28dp M3 Dialog
            ),
            title: Row(
              children: [
                Icon(
                  Icons.warning_amber_rounded,
                  color: colorScheme.error,
                  size: 28,
                ),
                const SizedBox(width: 10),
                const Text('Enable Live Mode?'),
              ],
            ),
            content: const Text(
              'WARNING: You are about to enable Live Check-In against production.\n\n'
              'Check-in mutations will be executed against the live database and modify attendee records. Ensure your Bearer token and active Event IDs are configured properly.',
            ),
            actions: [
              TextButton(
                onPressed: () {
                  M3Haptics.vibrateSelection();
                  Navigator.of(ctx).pop();
                },
                child: const Text('Keep Safe Mode'),
              ),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: colorScheme.error,
                  foregroundColor: colorScheme.onError,
                  shape: const StadiumBorder(),
                ),
                onPressed: () {
                  M3Haptics.vibrateAction();
                  Navigator.of(ctx).pop();
                  settingsProvider.setSafeMode(false);
                },
                child: const Text('Yes, Enable Live Mode'),
              ),
            ],
          );
        },
      );
    } else {
      settingsProvider.setSafeMode(true);
    }
  }

  void _onToggleExpertMode(bool enable) {
    final settingsProvider = context.read<SettingsProvider>();
    final colorScheme = Theme.of(context).colorScheme;

    if (enable) {
      M3Haptics.vibrateSelection();
      showDialog(
        context: context,
        builder: (ctx) {
          return AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(M3Shape.cornerExtraLarge),
            ),
            icon: Icon(
              Icons.warning_amber_rounded,
              color: colorScheme.error,
              size: 32,
            ),
            title: const Text(
              'Enable Expert Mode?',
              textAlign: TextAlign.center,
            ),
            content: const Text(
              'WARNING: Expert Mode allows volunteers to manually check in attendees directly from the attendee roster without scanning their physical QR codes.\n\n'
              'Only enable this if attendees are unable to display their QR codes (e.g. broken phone screens). Always verify identity with an official ID before manual admission.',
            ),
            actions: [
              TextButton(
                onPressed: () {
                  M3Haptics.vibrateSelection();
                  Navigator.of(ctx).pop();
                },
                child: const Text('Keep Disabled'),
              ),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: colorScheme.error,
                  foregroundColor: colorScheme.onError,
                  shape: const StadiumBorder(),
                ),
                onPressed: () {
                  M3Haptics.vibrateAction();
                  Navigator.of(ctx).pop();
                  settingsProvider.setExpertMode(true);
                },
                child: const Text('Enable Expert Mode'),
              ),
            ],
          );
        },
      );
    } else {
      settingsProvider.setExpertMode(false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final settingsProvider = context.watch<SettingsProvider>();
    final settings = settingsProvider.settings;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Configuration & Safety')),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        children: [
          // Section 1: Server & Auth Settings
          _buildSectionHeader(context, 'BACKEND & AUTHENTICATION'),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(M3Shape.cornerLarge), // 16dp
              border: Border.all(color: colorScheme.outlineVariant, width: 0.8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildAuthStatusCard(context, settings.bearerToken),
                const SizedBox(height: 16),
                Text(
                  'Manual Bearer Token (Advanced)',
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _tokenController,
                  obscureText: _obscureToken,
                  onChanged: (val) {
                    context.read<SettingsProvider>().setBearerToken(val.trim());
                  },
                  decoration: InputDecoration(
                    hintText: 'Paste Bearer token here...',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(M3Shape.cornerSmall),
                    ),
                    isDense: true,
                    suffixIcon: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: Icon(
                            _obscureToken
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined,
                          ),
                          onPressed: () {
                            M3Haptics.vibrateSelection();
                            setState(() => _obscureToken = !_obscureToken);
                          },
                        ),
                        IconButton(
                          icon: Icon(
                            Icons.check_circle,
                            color: colorScheme.primary,
                          ),
                          tooltip: 'Save Token',
                          onPressed: _saveToken,
                        ),
                      ],
                    ),
                  ),
                  onSubmitted: (_) => _saveToken(),
                ),
                const SizedBox(height: 18),
                Text(
                  'GraphQL Endpoint URL',
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _urlController,
                  onChanged: (val) {
                    context.read<SettingsProvider>().setApiUrl(val.trim());
                  },
                  decoration: InputDecoration(
                    hintText: AppSettings.defaultApiUrl,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(M3Shape.cornerSmall),
                    ),
                    isDense: true,
                    suffixIcon: IconButton(
                      icon: Icon(
                        Icons.check_circle,
                        color: colorScheme.primary,
                      ),
                      tooltip: 'Save URL',
                      onPressed: _saveUrl,
                    ),
                  ),
                  onSubmitted: (_) => _saveUrl(),
                ),
                const SizedBox(height: 18),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Network Timeout',
                      style: theme.textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(M3Shape.cornerFull),
                      ),
                      child: Text(
                        '${settings.timeoutSeconds}s',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: colorScheme.primary,
                        ),
                      ),
                    ),
                  ],
                ),
                Slider(
                  value: settings.timeoutSeconds.toDouble(),
                  min: 10,
                  max: 120,
                  divisions: 11,
                  label: '${settings.timeoutSeconds}s',
                  onChanged: (val) {
                    settingsProvider.setTimeoutSeconds(val.toInt());
                  },
                ),
                const SizedBox(height: 14),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Attendee Auto-Refresh',
                      style: theme.textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(M3Shape.cornerFull),
                      ),
                      child: Text(
                        '${settings.autoRefreshMinutes}m',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: colorScheme.primary,
                        ),
                      ),
                    ),
                  ],
                ),
                Slider(
                  value: settings.autoRefreshMinutes.toDouble().clamp(1.0, 60.0),
                  min: 1,
                  max: 60,
                  divisions: 59,
                  label: '${settings.autoRefreshMinutes}m',
                  onChanged: (val) {
                    settingsProvider.setAutoRefreshMinutes(val.toInt());
                    try {
                      context.read<AttendeesProvider?>()?.startBackgroundTimer();
                    } catch (_) {}
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Section 2: Safe Mode Guard
          _buildSectionHeader(context, 'ENVIRONMENT SAFETY'),
          Material(
            color: colorScheme.surfaceContainerLow,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(M3Shape.cornerLarge),
              side: BorderSide(color: colorScheme.outlineVariant, width: 0.8),
            ),
            clipBehavior: Clip.antiAlias,
            child: SwitchListTile(
              title: Text(
                settings.isSafeMode ? 'Safe Mode (Dry-Run Only)' : 'Live Check-In Enabled',
                style: TextStyle(
                  fontWeight: FontWeight.bold, // Title Medium Emphasized
                  color: settings.isSafeMode ? Colors.teal.shade800 : colorScheme.error,
                ),
              ),
              subtitle: Text(
                settings.isSafeMode
                    ? 'Check-ins are simulated locally. No live GraphQL mutations are executed.'
                    : 'Check-in mutations will be sent to the production GraphQL backend.',
                style: TextStyle(
                  fontSize: 12,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              value: settings.isSafeMode,
              activeTrackColor: Colors.teal,
              onChanged: _onToggleSafeMode,
            ),
          ),
          const SizedBox(height: 24),

          // Section 2.5: Expert Mode (Manual Roster Check-In) — hidden behind 10-tap unlock
          if (_expertSectionUnlocked) ...[
            _buildSectionHeader(context, 'EXPERT MODE / ROSTER CHECK-IN'),
            Material(
              color: colorScheme.surfaceContainerLow,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(M3Shape.cornerLarge),
                side: BorderSide(
                  color: settings.isExpertMode
                      ? colorScheme.error.withValues(alpha: 0.5)
                      : colorScheme.outlineVariant,
                  width: settings.isExpertMode ? 1.2 : 0.8,
                ),
              ),
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: [
                  SwitchListTile(
                    title: Text(
                      settings.isExpertMode
                          ? 'Expert Mode Active (Manual Check-In Enabled)'
                          : 'Expert Mode Disabled',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: settings.isExpertMode ? colorScheme.error : null,
                      ),
                    ),
                    subtitle: Text(
                      settings.isExpertMode
                          ? 'Volunteers can manually check in attendees directly from the roster list without scanning QR codes.'
                          : 'Manual check-in from the roster is disabled to prevent accidental check-ins.',
                      style: TextStyle(
                        fontSize: 12,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                    value: settings.isExpertMode,
                    activeTrackColor: colorScheme.error,
                    onChanged: _onToggleExpertMode,
                  ),
                  Container(
                    margin: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: settings.isExpertMode
                          ? colorScheme.errorContainer.withValues(alpha: 0.4)
                          : colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(M3Shape.cornerMedium),
                      border: Border.all(
                        color: settings.isExpertMode
                            ? colorScheme.error.withValues(alpha: 0.3)
                            : colorScheme.outlineVariant.withValues(alpha: 0.5),
                        width: 0.8,
                      ),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.warning_amber_rounded,
                          size: 20,
                          color: settings.isExpertMode
                              ? colorScheme.onErrorContainer
                              : colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Warning: With Expert Mode enabled, any volunteer can admit attendees from the attendee list without verifying physical tickets or QR codes. Keep disabled unless an attendee has an unreadable or broken screen.',
                            style: TextStyle(
                              fontSize: 11.5,
                              color: settings.isExpertMode
                                  ? colorScheme.onErrorContainer
                                  : colorScheme.onSurfaceVariant,
                              fontWeight: settings.isExpertMode ? FontWeight.w600 : FontWeight.normal,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
          ],

          // Section 3: Multi-Event Management
          _buildSectionHeader(context, 'ACTIVE EVENTS'),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(M3Shape.cornerLarge),
              border: Border.all(color: colorScheme.outlineVariant, width: 0.8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  settings.isExpertMode
                      ? 'Specify active events to validate tickets against. Multiple events permitted in Expert Mode.'
                      : 'Specify the active event to validate tickets against. Only one event can be active at a time.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _newEventIdController,
                        decoration: InputDecoration(
                          hintText: 'Paste event link or UUID',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(
                              M3Shape.cornerSmall,
                            ),
                          ),
                          isDense: true,
                          prefixIcon: const Icon(
                            Icons.link_rounded,
                          ),
                        ),
                        style: const TextStyle(
                          fontSize: 13,
                        ),
                        onSubmitted: (_) => _addEventId(),
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilledButton.tonalIcon(
                      icon: const Icon(Icons.add, size: 18),
                      label: const Text('Add'),
                      onPressed: () => _addEventId(),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  icon: const Icon(Icons.event_available_outlined, size: 18),
                  label: const Text('Browse Public Events'),
                  style: OutlinedButton.styleFrom(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(M3Shape.cornerSmall),
                    ),
                  ),
                  onPressed: _openEventPickerSheet,
                ),
                const SizedBox(height: 14),
                if (settings.activeEventIds.isEmpty)
                  Text(
                    'No Event IDs configured (All events accepted)',
                    style: TextStyle(
                      fontStyle: FontStyle.italic,
                      color: colorScheme.outline,
                      fontSize: 13,
                    ),
                  )
                else
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: settings.activeEventIds.map((id) {
                      final meta = _eventMetadata[id];
                      final title = meta?.title.isNotEmpty == true ? meta!.title : id;
                      final dateStr = meta?.start != null ? _formatEventDate(meta!.start) : '';

                      return InputChip(
                        avatar: Icon(
                          _mapTumiIcon(meta?.icon),
                          size: 18,
                          color: colorScheme.primary,
                        ),
                        label: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              title,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 12,
                              ),
                            ),
                            if (dateStr.isNotEmpty)
                              Text(
                                dateStr,
                                style: TextStyle(
                                  fontSize: 10,
                                  color: colorScheme.onSurfaceVariant,
                                ),
                              ),
                          ],
                        ),
                        deleteIcon: const Icon(Icons.close, size: 16),
                        onDeleted: () {
                          M3Haptics.vibrateSelection();
                          settingsProvider.removeEventId(id);
                        },
                      );
                    }).toList(),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 24),



          // Section: About — always visible; version taps unlock expert section
          _buildSectionHeader(context, 'ABOUT'),
          Material(
            color: colorScheme.surfaceContainerLow,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(M3Shape.cornerLarge),
              side: BorderSide(color: colorScheme.outlineVariant, width: 0.8),
            ),
            clipBehavior: Clip.antiAlias,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                Row(
                  children: [
                    Icon(Icons.qr_code_scanner_rounded, size: 36, color: colorScheme.primary),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Turnstile Check-In',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Turnstile — Event Access Control',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                GestureDetector(
                  onTap: _onVersionTapped,
                  behavior: HitTestBehavior.opaque,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        Icon(Icons.info_outline_rounded, size: 16, color: colorScheme.onSurfaceVariant),
                        const SizedBox(width: 8),
                        Text(
                          'Version $_appVersion',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                            fontFamily: 'monospace',
                          ),
                        ),
                        if (_expertSectionUnlocked) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                            decoration: BoxDecoration(
                              color: colorScheme.errorContainer,
                              borderRadius: BorderRadius.circular(M3Shape.cornerFull),
                            ),
                            child: Text(
                              'EXPERT',
                              style: TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                                color: colorScheme.onErrorContainer,
                                letterSpacing: 0.8,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                Divider(
                  height: 24,
                  thickness: 0.8,
                  color: colorScheme.outlineVariant,
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.code_rounded, color: colorScheme.primary),
                  title: const Text(
                    'Source Code',
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                  ),
                  subtitle: Text(
                    'github.com/filipskubacz/turnstile-checkin',
                    style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant),
                  ),
                  trailing: Icon(Icons.open_in_new_rounded, size: 18, color: colorScheme.onSurfaceVariant),
                  onTap: _launchGitHubUrl,
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.gavel_rounded, color: colorScheme.primary),
                  title: const Text(
                    'Imprint',
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                  ),
                  subtitle: Text(
                    settings.imprint.trim().isNotEmpty
                        ? 'Legal disclosure and contact details'
                        : 'Not configured (set IMPRINT)',
                    style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant),
                  ),
                  trailing: Icon(Icons.chevron_right_rounded, size: 18, color: colorScheme.onSurfaceVariant),
                  onTap: () => _showImprintModal(context, settings.imprint),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.policy_outlined, color: colorScheme.primary),
                  title: const Text(
                    'Open Source Licenses',
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                  ),
                  subtitle: Text(
                    'Licenses of third-party software libraries',
                    style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant),
                  ),
                  trailing: Icon(Icons.chevron_right_rounded, size: 18, color: colorScheme.onSurfaceVariant),
                  onTap: () => _showOpenSourceLicenses(context),
                ),
              ],
            ),
          ),
        ),
          const SizedBox(height: 32),

        ],
      ),
    );
  }

  Widget _buildSectionHeader(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.bold,
          letterSpacing: 1.2,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

IconData _mapTumiIcon(String? iconName) {
  if (iconName == null || iconName.isEmpty) return Icons.event_outlined;
  final clean = iconName.toLowerCase().split(':').first;
  if (clean.contains('beer') || clean.contains('drink') || clean.contains('bar') || clean.contains('crawl')) {
    return Icons.sports_bar_outlined;
  }
  if (clean.contains('party') || clean.contains('club') || clean.contains('celebrat')) {
    return Icons.celebration_outlined;
  }
  if (clean.contains('friend') || clean.contains('group') || clean.contains('meet')) {
    return Icons.groups_outlined;
  }
  if (clean.contains('sport') || clean.contains('run') || clean.contains('hike') || clean.contains('walk')) {
    return Icons.directions_run_outlined;
  }
  if (clean.contains('class') || clean.contains('learn') || clean.contains('fair') || clean.contains('workshop')) {
    return Icons.school_outlined;
  }
  if (clean.contains('food') || clean.contains('cook') || clean.contains('dinner') || clean.contains('eat')) {
    return Icons.restaurant_outlined;
  }
  if (clean.contains('trip') || clean.contains('travel') || clean.contains('tour')) {
    return Icons.explore_outlined;
  }
  return Icons.event_outlined;
}

String _formatEventDate(DateTime? dt) {
  if (dt == null) return '';
  final local = dt.toLocal();
  final d = local.day.toString().padLeft(2, '0');
  final mo = local.month.toString().padLeft(2, '0');
  final y = local.year;
  final h = local.hour.toString().padLeft(2, '0');
  final mi = local.minute.toString().padLeft(2, '0');
  return '$d.$mo.$y $h:$mi';
}

class _EventPickerSheet extends StatefulWidget {
  final GraphQLService graphQLService;
  final AppSettings settings;
  final ValueChanged<EventInfo> onEventSelected;

  const _EventPickerSheet({
    required this.graphQLService,
    required this.settings,
    required this.onEventSelected,
  });

  @override
  State<_EventPickerSheet> createState() => _EventPickerSheetState();
}

class _EventPickerSheetState extends State<_EventPickerSheet> {
  final TextEditingController _filterController = TextEditingController();
  List<EventInfo> _allEvents = [];
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _fetchEvents();
  }

  @override
  void dispose() {
    _filterController.dispose();
    super.dispose();
  }

  Future<void> _fetchEvents() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final res = await widget.graphQLService.getPublicEvents(widget.settings);
    if (!mounted) return;

    if (res.isSuccess && res.data != null) {
      setState(() {
        _allEvents = res.data!;
        _isLoading = false;
      });
    } else {
      setState(() {
        _errorMessage = res.errorMessage ?? 'Failed to load events';
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final activeIds = context.watch<SettingsProvider>().settings.activeEventIds;
    final query = _filterController.text.trim().toLowerCase();

    final filteredEvents = query.isEmpty
        ? _allEvents
        : _allEvents.where((e) {
            final tMatch = e.title.toLowerCase().contains(query);
            final idMatch = e.id.toLowerCase().contains(query);
            return tMatch || idMatch;
          }).toList();

    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      expand: false,
      builder: (ctx, scrollController) {
        return Column(
          children: [
            const SizedBox(height: 12),
            Container(
              width: 32,
              height: 4,
              decoration: BoxDecoration(
                color: colorScheme.outlineVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Choose Event',
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          'Select from public events on TUMI',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.refresh_rounded),
                    tooltip: 'Refresh',
                    onPressed: _isLoading ? null : _fetchEvents,
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: TextField(
                controller: _filterController,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  hintText: 'Search by title or ID...',
                  prefixIcon: const Icon(Icons.search_rounded),
                  suffixIcon: _filterController.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear_rounded),
                          onPressed: () {
                            _filterController.clear();
                            setState(() {});
                          },
                        )
                      : null,
                  isDense: true,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(M3Shape.cornerMedium),
                  ),
                ),
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _errorMessage != null
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.error_outline_rounded,
                                    size: 40, color: colorScheme.error),
                                const SizedBox(height: 12),
                                Text(
                                  _errorMessage!,
                                  textAlign: TextAlign.center,
                                  style: TextStyle(color: colorScheme.error),
                                ),
                                const SizedBox(height: 12),
                                FilledButton.tonal(
                                  onPressed: _fetchEvents,
                                  child: const Text('Retry'),
                                ),
                              ],
                            ),
                          ),
                        )
                      : filteredEvents.isEmpty
                          ? Center(
                              child: Text(
                                'No events found',
                                style: TextStyle(color: colorScheme.outline),
                              ),
                            )
                          : ListView.builder(
                              controller: scrollController,
                              itemCount: filteredEvents.length,
                              itemBuilder: (ctx, index) {
                                final ev = filteredEvents[index];
                                final isSelected = activeIds.contains(ev.id);
                                final dateStr = ev.start != null
                                    ? _formatEventDate(ev.start)
                                    : '';

                                return ListTile(
                                  leading: Container(
                                    width: 40,
                                    height: 40,
                                    decoration: BoxDecoration(
                                      color: isSelected
                                          ? colorScheme.primaryContainer
                                          : colorScheme.surfaceContainerHigh,
                                      borderRadius: BorderRadius.circular(
                                          M3Shape.cornerSmall),
                                    ),
                                    child: Icon(
                                      _mapTumiIcon(ev.icon),
                                      color: isSelected
                                          ? colorScheme.onPrimaryContainer
                                          : colorScheme.onSurfaceVariant,
                                      size: 20,
                                    ),
                                  ),
                                  title: Text(
                                    ev.title,
                                    style: TextStyle(
                                      fontWeight: isSelected
                                          ? FontWeight.bold
                                          : FontWeight.w500,
                                    ),
                                  ),
                                  subtitle: Text(
                                    dateStr.isNotEmpty
                                        ? '$dateStr · ${ev.id.substring(0, 8)}...'
                                        : ev.id,
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                  trailing: isSelected
                                      ? Icon(Icons.check_circle_rounded,
                                          color: colorScheme.primary)
                                      : Icon(
                                          context.watch<SettingsProvider>().settings.isExpertMode
                                              ? Icons.add_circle_outline_rounded
                                              : Icons.radio_button_unchecked_rounded,
                                          color: colorScheme.onSurfaceVariant,
                                        ),
                                  onTap: () {
                                    M3Haptics.vibrateSelection();
                                    if (isSelected) {
                                      context.read<SettingsProvider>().removeEventId(ev.id);
                                    } else {
                                      widget.onEventSelected(ev);
                                    }
                                  },
                                );
                              },
                            ),
            ),
          ],
        );
      },
    );
  }
}

