import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/app_settings.dart';
import '../providers/attendees_provider.dart';
import '../providers/settings_provider.dart';
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

  void _addEventId() {
    final id = _newEventIdController.text.trim();
    if (id.isEmpty) return;
    M3Haptics.vibrateAction();
    context.read<SettingsProvider>().addEventId(id);
    _newEventIdController.clear();
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
          _buildSectionHeader(context, 'ACTIVE EVENT IDS'),
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
                  'Specify Event IDs to validate tickets against. If multiple IDs are added, tickets matching any active event will be permitted.',
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
                          hintText: 'e.g. 6e014c8b-b1b6-4412-814c-e5031e1a03be',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(
                              M3Shape.cornerSmall,
                            ),
                          ),
                          isDense: true,
                          prefixIcon: const Icon(
                            Icons.confirmation_number_outlined,
                          ),
                        ),
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 12,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilledButton.tonalIcon(
                      icon: const Icon(Icons.add, size: 18),
                      label: const Text('Add'),
                      onPressed: _addEventId,
                    ),
                  ],
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
                    runSpacing: 6,
                    children: settings.activeEventIds.map((id) {
                      return Chip(
                        label: Text(
                          id,
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 11,
                          ),
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
              ],
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
