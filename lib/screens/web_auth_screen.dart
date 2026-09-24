import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../providers/settings_provider.dart';
import '../utils/jwt_utils.dart';
import '../utils/m3_motion.dart';
import '../utils/web_url_cleaner.dart';

class WebAuthScreen extends StatefulWidget {
  final String? initialUrl;

  const WebAuthScreen({super.key, this.initialUrl});

  static Future<bool?> show(BuildContext context, {String? initialUrl}) {
    return Navigator.of(context).push<bool>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => WebAuthScreen(initialUrl: initialUrl),
      ),
    );
  }

  @override
  State<WebAuthScreen> createState() => _WebAuthScreenState();
}

class _WebAuthScreenState extends State<WebAuthScreen> {
  WebViewController? _controller;
  late final String _targetUrl;
  final TextEditingController _webTokenInputController = TextEditingController();
  int _progress = 0;
  bool _isChecking = false;
  String? _statusInfo;

  String get _targetHost {
    final host = Uri.tryParse(_targetUrl)?.host;
    return (host != null && host.isNotEmpty) ? host : 'Web Platform';
  }

  // Browser DevTools helper snippet that extracts and copies the JWT directly to clipboard.
  // Works with Auth0 SPA SDK and standard localStorage/sessionStorage tokens.
  static const String _quickCopySnippet =
      "copy((function(){for(let s of [localStorage,sessionStorage]){for(let i=0;i<s.length;i++){try{let p=JSON.parse(s.getItem(s.key(i)));let t=(p.body&&p.body.access_token)||p.access_token||p.id_token||p.token;if(t&&t.startsWith('eyJ'))return t;}catch(e){}}}return 'No token found';})())";

  static const String _tokenExtractionScript = '''
(function() {
  function findToken(storage) {
    try {
      if (!storage) return null;
      for (var i = 0; i < storage.length; i++) {
        var key = storage.key(i);
        if (!key) continue;
        var val = storage.getItem(key);
        if (!val) continue;

        // Direct JWT format check
        if (typeof val === 'string' && val.indexOf('eyJ') === 0 && val.split('.').length === 3) {
          return val;
        }

        // Parse JSON structures (Auth0 SPA SDK format)
        try {
          var parsed = JSON.parse(val);
          if (parsed && typeof parsed === 'object') {
            var token = (parsed.body && parsed.body.access_token) ||
                        parsed.access_token ||
                        parsed.id_token ||
                        parsed.token;
            if (token && typeof token === 'string' && token.indexOf('eyJ') === 0) {
              return token;
            }
          }
        } catch(e) {}
      }
    } catch(e) {}
    return null;
  }

  return findToken(window.localStorage) || findToken(window.sessionStorage) || null;
})();
''';

  @override
  void initState() {
    super.initState();

    final settings = context.read<SettingsProvider>().settings;
    final apiUrl = settings.apiUrl.trim();
    final uri = Uri.tryParse(apiUrl);
    final origin = (uri != null && uri.hasScheme && uri.hasAuthority)
        ? '${uri.scheme}://${uri.host}${uri.hasPort ? ':${uri.port}' : ''}'
        : '';
    _targetUrl = widget.initialUrl ?? (origin.isNotEmpty ? origin : 'https://localhost');

    // Only instantiate WebViewController on native platforms (iOS/Android)
    if (!kIsWeb) {
      final controller = WebViewController();
      controller
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..setUserAgent(
          'Mozilla/5.0 (Linux; Android 10; Mobile) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/119.0.0.0 Mobile Safari/537.36',
        )
        ..setNavigationDelegate(
          NavigationDelegate(
            onProgress: (int progress) {
              setState(() {
                _progress = progress;
              });
            },
            onPageStarted: (String url) {
              setState(() {
                _statusInfo = 'Loading...';
              });
            },
            onPageFinished: (String url) async {
              setState(() {
                _statusInfo = 'Page loaded. Checking login status...';
              });
              // Automatically attempt silent token extraction when page finishes loading
              await _attemptTokenExtraction(silent: true);
            },
            onWebResourceError: (WebResourceError error) {
              setState(() {
                _statusInfo = 'Network notice: ${error.description}';
              });
            },
          ),
        );

      controller.loadRequest(Uri.parse(_targetUrl));
      _controller = controller;
    }
  }

  @override
  void dispose() {
    _webTokenInputController.dispose();
    super.dispose();
  }

  String? _cleanReturnedToken(dynamic result) {
    if (result == null) return null;
    String str = result.toString().trim();
    if (str.isEmpty || str == 'null') return null;

    // Remove enclosing quotes if returned as a JSON-encoded string
    if (str.startsWith('"') && str.endsWith('"') && str.length >= 2) {
      try {
        final decoded = jsonDecode(str);
        if (decoded is String) str = decoded.trim();
      } catch (_) {
        str = str.substring(1, str.length - 1).trim();
      }
    }

    if (str.startsWith('eyJ') && str.split('.').length == 3) {
      return str;
    }
    return null;
  }

  bool _applyToken(String raw) {
    final token = _cleanReturnedToken(raw);
    if (token == null) {
      M3Haptics.vibrateSelection();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('That doesn\'t look like a valid JWT. Please check and try again.'),
          duration: Duration(seconds: 2),
        ),
      );
      return false;
    }
    if (JwtUtils.isExpired(token)) {
      M3Haptics.vibrateSelection();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Token is already expired. Please log in again and get a fresh token.'),
          duration: Duration(seconds: 3),
        ),
      );
      return false;
    }

    M3Haptics.vibrateAction();
    context.read<SettingsProvider>().setBearerToken(token);
    final userLabel = JwtUtils.getUserIdentifier(token);
    final expiryDesc = JwtUtils.formatExpiryStatus(token);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          userLabel != null
              ? 'Authenticated as $userLabel ($expiryDesc)!'
              : 'Logged in successfully ($expiryDesc)!',
        ),
        backgroundColor: Colors.teal.shade800,
        duration: const Duration(seconds: 3),
      ),
    );
    Navigator.of(context).pop(true);
    return true;
  }

  Future<void> _attemptTokenExtraction({bool silent = false}) async {
    if (kIsWeb || _controller == null) return;

    if (_isChecking || !mounted) return;
    setState(() => _isChecking = true);

    try {
      final rawResult = await _controller!.runJavaScriptReturningResult(
        _tokenExtractionScript,
      );

      final token = _cleanReturnedToken(rawResult);

      if (token != null) {
        final isExpired = JwtUtils.isExpired(token);
        if (isExpired) {
          if (!silent && mounted) {
            M3Haptics.vibrateSelection();
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'Found an expired session token. Please complete login on the page first.',
                ),
                duration: Duration(seconds: 3),
              ),
            );
          }
          setState(() {
            _statusInfo = 'Found expired session. Please sign in.';
          });
          return;
        }

        // Valid, active token found!
        if (mounted) {
          _applyToken(token);
        }
        return;
      }

      if (!silent && mounted) {
        M3Haptics.vibrateSelection();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'No active login session detected. Please sign in on the webpage first.',
            ),
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (!silent && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not read session token: $e'),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isChecking = false);
      }
    }
  }

  String get _mobileBookmarkletCode {
    final uri = Uri.base;
    final returnUrl = '${uri.origin}${uri.path}';
    return "javascript:(function(){for(let s of [localStorage,sessionStorage]){for(let i=0;i<s.length;i++){try{let p=JSON.parse(s.getItem(s.key(i)));let t=(p.body&&p.body.access_token)||p.access_token||p.token;if(t&&t.startsWith('eyJ')){window.location.href='$returnUrl?token='+encodeURIComponent(t);return;}}catch(e){}}}alert('No active login session found. Please sign in first.');})();";
  }

  Widget _buildStepCard({
    required BuildContext context,
    required int stepNumber,
    required String title,
    required String description,
    required Widget child,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16), // M3 CornerLarge (16dp)
        border: Border.all(color: colorScheme.outlineVariant, width: 0.8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 14,
                backgroundColor: colorScheme.primaryContainer,
                child: Text(
                  '$stepNumber',
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: colorScheme.onPrimaryContainer,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: colorScheme.onSurface,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            description,
            style: theme.textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }

  Widget _buildWebAuthView(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final currentInput = _webTokenInputController.text.trim();
    final candidateToken = _cleanReturnedToken(currentInput);
    final bool hasCandidate = candidateToken != null;
    final bool isCandidateExpired = hasCandidate && JwtUtils.isExpired(candidateToken);
    final String? candidateUser = hasCandidate ? JwtUtils.getUserIdentifier(candidateToken) : null;
    final String? candidateExpiry = hasCandidate ? JwtUtils.formatExpiryStatus(candidateToken) : null;

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 680),
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          children: [
            // Hero Bookmarklet Header Card
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: colorScheme.primaryContainer.withValues(alpha: 0.45),
                borderRadius: BorderRadius.circular(16), // M3 CornerLarge (16dp)
                border: Border.all(color: colorScheme.primary.withValues(alpha: 0.3), width: 1.2),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: colorScheme.primary,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.bookmark_added_rounded, color: Colors.white, size: 22),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Mobile Bookmark Login',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: colorScheme.onSurface,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Since phones don\'t have developer tools, this one-tap bookmark grabs your login from $_targetHost and returns you right back here authenticated.',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                            height: 1.4,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Step 1: Copy & Save Bookmarklet
            _buildStepCard(
              context: context,
              stepNumber: 1,
              title: 'Copy & Save the Bookmarklet',
              description:
                  'Copy the code below, create a bookmark in your mobile browser, and paste this code as the bookmark URL:',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        shape: const StadiumBorder(),
                        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 18),
                      ),
                      icon: const Icon(Icons.copy_rounded, size: 18),
                      label: const Text(
                        'Copy Bookmarklet Code',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: _mobileBookmarkletCode));
                        M3Haptics.vibrateAction();
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Bookmarklet code copied to clipboard!'),
                            duration: Duration(seconds: 3),
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 14),

                  // Collapsible instructions for Safari & Chrome
                  Theme(
                    data: theme.copyWith(dividerColor: Colors.transparent),
                    child: ExpansionTile(
                      tilePadding: EdgeInsets.zero,
                      childrenPadding: const EdgeInsets.only(top: 8, bottom: 4),
                      title: Text(
                        'How to save on Safari / Chrome on mobile',
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: colorScheme.primary,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: colorScheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '🍎 Safari (iPhone / iPad):',
                                style: theme.textTheme.labelMedium?.copyWith(fontWeight: FontWeight.bold),
                              ),
                              const SizedBox(height: 4),
                              const Text(
                                '1. Tap Share icon (square with arrow up) → "Add Bookmark".\n'
                                '2. Name it "Auth Token" and tap Save.\n'
                                '3. Tap Bookmarks icon (book) → "Edit" → select "Auth Token".\n'
                                '4. Erase the address, paste the copied code, and tap Done.',
                                style: TextStyle(fontSize: 12, height: 1.4),
                              ),
                              const SizedBox(height: 12),
                              Text(
                                '🤖 Chrome (Android / iOS):',
                                style: theme.textTheme.labelMedium?.copyWith(fontWeight: FontWeight.bold),
                              ),
                              const SizedBox(height: 4),
                              const Text(
                                '1. Tap the three dots (⋮) → Star icon to bookmark this page.\n'
                                '2. Tap "Edit" on the bottom pop-up (or ⋮ → Bookmarks → Edit).\n'
                                '3. Name it "Auth Token".\n'
                                '4. Clear the URL field, paste the copied code, and tap Save.',
                                style: TextStyle(fontSize: 12, height: 1.4),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Step 2: Open Portal & Tap Bookmark
            _buildStepCard(
              context: context,
              stepNumber: 2,
              title: 'Open Portal & Run the Bookmark',
              description:
                  'Click below to open $_targetHost in a new tab. Log in, then run your bookmark:',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.tonalIcon(
                      style: FilledButton.styleFrom(
                        shape: const StadiumBorder(),
                        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 18),
                      ),
                      icon: const Icon(Icons.open_in_new_rounded, size: 18),
                      label: Text(
                        'Open $_targetHost',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      // Using openBrowserTab opens a new tab cleanly without freezing Chrome
                      onPressed: () => openBrowserTab(_targetUrl),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.touch_app_rounded, size: 18, color: colorScheme.primary),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Once signed in on $_targetHost, tap your address bar, type "Auth Token", and tap the bookmark result (or choose it from your Bookmarks list). It will automatically bring you back here signed in!',
                            style: TextStyle(
                              fontSize: 12,
                              color: colorScheme.onSurfaceVariant,
                              height: 1.4,
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

            // Secondary / Fallback: Manual Token Paste or DevTools
            Theme(
              data: theme.copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                  side: BorderSide(color: colorScheme.outlineVariant, width: 0.8),
                ),
                collapsedShape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                  side: BorderSide(color: colorScheme.outlineVariant, width: 0.8),
                ),
                title: Text(
                  'Alternative: Paste Token or Desktop DevTools',
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'If you already have your JWT token or are using a desktop browser:',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _webTokenInputController,
                          maxLines: 3,
                          style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                          decoration: InputDecoration(
                            hintText: 'eyJhbGciOiJSUzI1NiIs...',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            suffixIcon: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.paste_rounded),
                                  tooltip: 'Paste from clipboard',
                                  onPressed: () async {
                                    final data = await Clipboard.getData(Clipboard.kTextPlain);
                                    final text = data?.text?.trim() ?? '';
                                    if (text.isNotEmpty) {
                                      setState(() {
                                        _webTokenInputController.text = text;
                                      });
                                    }
                                  },
                                ),
                                if (_webTokenInputController.text.isNotEmpty)
                                  IconButton(
                                    icon: const Icon(Icons.clear_rounded),
                                    tooltip: 'Clear',
                                    onPressed: () {
                                      setState(() {
                                        _webTokenInputController.clear();
                                      });
                                    },
                                  ),
                              ],
                            ),
                          ),
                          onChanged: (_) => setState(() {}),
                        ),

                        // Real-time JWT preview badge
                        if (hasCandidate) ...[
                          const SizedBox(height: 10),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            decoration: BoxDecoration(
                              color: isCandidateExpired
                                  ? colorScheme.errorContainer.withValues(alpha: 0.6)
                                  : Colors.teal.shade50,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: isCandidateExpired ? colorScheme.error : Colors.teal.shade300,
                                width: 0.8,
                              ),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  isCandidateExpired ? Icons.warning_amber_rounded : Icons.check_circle_rounded,
                                  size: 18,
                                  color: isCandidateExpired ? colorScheme.error : Colors.teal.shade800,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    isCandidateExpired
                                        ? 'Token expired ($candidateExpiry)'
                                        : '${candidateUser != null ? "User: $candidateUser • " : ""}$candidateExpiry',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      color: isCandidateExpired ? colorScheme.error : Colors.teal.shade900,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],

                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            style: FilledButton.styleFrom(
                              shape: const StadiumBorder(),
                              padding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                            icon: const Icon(Icons.check_rounded, size: 18),
                            label: const Text(
                              'Save Token & Finish',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                            onPressed: currentInput.isEmpty
                                ? null
                                : () => _applyToken(currentInput),
                          ),
                        ),
                        const SizedBox(height: 16),
                        const Divider(),
                        const SizedBox(height: 8),

                        // Desktop DevTools snippet
                        Text(
                          'Desktop Browser Snippet (F12 → Console):',
                          style: theme.textTheme.labelMedium?.copyWith(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 6),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: colorScheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: colorScheme.outlineVariant, width: 0.8),
                          ),
                          child: const SelectableText(
                            _quickCopySnippet,
                            style: TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 11,
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(shape: const StadiumBorder()),
                          icon: const Icon(Icons.copy_rounded, size: 16),
                          label: const Text('Copy Console Script'),
                          onPressed: () {
                            Clipboard.setData(const ClipboardData(text: _quickCopySnippet));
                            M3Haptics.vibrateAction();
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('Copied! Paste into DevTools Console on $_targetHost'),
                                duration: const Duration(seconds: 3),
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMobileAuthView(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Column(
      children: [
        // Banner giving clear guidance to user
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          color: colorScheme.surfaceContainerLow,
          child: Row(
            children: [
              Icon(
                Icons.info_outline_rounded,
                size: 16,
                color: colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _statusInfo ?? 'Log in using your account. Token is saved automatically.',
                  style: TextStyle(
                    fontSize: 12,
                    color: colorScheme.onSurfaceVariant,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (_isChecking)
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
            ],
          ),
        ),

        // Embedded WebView
        Expanded(
          child: _controller != null
              ? WebViewWidget(controller: _controller!)
              : const Center(child: CircularProgressIndicator()),
        ),

        // Bottom Action Bar
        SafeArea(
          top: false,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainer,
              border: Border(
                top: BorderSide(color: colorScheme.outlineVariant, width: 0.8),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      shape: const StadiumBorder(),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    icon: _isChecking
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.vpn_key_rounded),
                    label: Text(
                      _isChecking ? 'Checking session...' : 'Capture Token & Finish',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    onPressed: _isChecking ? null : () => _attemptTokenExtraction(silent: false),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Web Portal Sign-In', style: TextStyle(fontSize: 18)),
            Text(
              _targetHost,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.normal),
            ),
          ],
        ),
        actions: [
          if (kIsWeb)
            IconButton(
              icon: const Icon(Icons.open_in_new_rounded),
              tooltip: 'Open in new tab',
              onPressed: () => openBrowserTab(_targetUrl),
            ),
          if (!kIsWeb)
            IconButton(
              icon: const Icon(Icons.refresh_rounded),
              tooltip: 'Reload page',
              onPressed: () {
                _controller?.reload();
              },
            ),
        ],
        bottom: _progress > 0 && _progress < 100
            ? PreferredSize(
                preferredSize: const Size.fromHeight(3),
                child: LinearProgressIndicator(
                  value: _progress / 100,
                  minHeight: 3,
                ),
              )
            : null,
      ),
      body: kIsWeb ? _buildWebAuthView(context) : _buildMobileAuthView(context),
    );
  }
}
