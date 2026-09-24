import 'package:ai_barcode_scanner/ai_barcode_scanner.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/scanner_provider.dart';
import '../providers/settings_provider.dart';
import '../services/queue_service.dart';
import '../utils/m3_motion.dart';
import '../widgets/ticket_preview_sheet.dart';

class ScannerScreen extends StatefulWidget {
  final VoidCallback? onNavigateToQueue;

  const ScannerScreen({super.key, this.onNavigateToQueue});

  @override
  State<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends State<ScannerScreen> {
  late final AiBarcodeScannerController _scannerController;
  ScannerProvider? _scannerProvider;
  bool _isTorchOn = false;

  @override
  void initState() {
    super.initState();
    // Explicitly configure DetectionSpeed.normal and 600ms timeout so the camera
    // does not lock out repeat scans of the same ticket or introduce artificial lag.
    _scannerController = AiBarcodeScannerController(
      detectionSpeed: DetectionSpeed.normal,
      detectionTimeoutMs: 600,
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final provider = context.read<ScannerProvider>();
    if (_scannerProvider != provider) {
      _scannerProvider?.removeListener(_onScannerStateChanged);
      _scannerProvider = provider;
      _scannerProvider?.addListener(_onScannerStateChanged);
    }
  }

  Future<void> _stopCamera() async {
    try {
      if (_scannerController.isRunning) {
        await _scannerController.stop();
      }
    } catch (e) {
      debugPrint('Error stopping camera: $e');
    }
  }

  Future<void> _startCamera() async {
    try {
      if (!_scannerController.isRunning && !_scannerController.value.isStarting) {
        await _scannerController.start();
        if (_isTorchOn) {
          await _scannerController.setTorch(on: true);
        }
      }
      _scannerController.resumeScanning();
    } catch (e) {
      debugPrint('Error starting camera: $e');
    }
  }

  void _onScannerStateChanged() {
    final state = _scannerProvider?.state;
    final isModalOpen = state == ScanState.ticketFound &&
        _scannerProvider?.currentRegistration != null;
    if (isModalOpen) {
      // Pause frame analysis and stop camera feed to release the camera hardware while modal sheet is open
      _scannerController.pauseScanning();
      _stopCamera();
    } else if (state == ScanState.ready) {
      // Resume camera feed and barcode detection smoothly when returning to scanning state
      _startCamera();
    } else if (state == ScanState.fetching || state == ScanState.error) {
      _scannerController.pauseScanning();
    }
  }

  @override
  void dispose() {
    _scannerProvider?.removeListener(_onScannerStateChanged);
    _scannerController.dispose();
    super.dispose();
  }

  void _processScannedCode(String rawCode) {
    final scannerProvider = context.read<ScannerProvider>();
    final isValid = ScannerProvider.isValidUuid(rawCode);

    if (isValid) {
      // Subtle tactile vibration on successful QR scan
      M3Haptics.vibrateScanSuccess();
    } else {
      // Error vibration on malformed QR string
      M3Haptics.vibrateScanError();
    }

    scannerProvider.handleBarcodeScanned(rawCode);
  }

  void _resetScanner() {
    _startCamera();
    context.read<ScannerProvider>().reset();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final settingsProvider = context.watch<SettingsProvider>();
    final scannerProvider = context.watch<ScannerProvider>();
    final queueService = context.watch<QueueService>();

    return Scaffold(
      body: Stack(
        children: [
          // 1. Camera Viewfinder with Modern M3 Expressive static reticle (No cheap scan line)
          Positioned.fill(
            child: AiBarcodeScanner.embedded(
              controller: _scannerController,
              scanMode: ScanMode.continuous,
              scanCooldown: const Duration(milliseconds: 250),
              detectionSpeed: DetectionSpeed.normal,
              detectionTimeoutMs: 750,
              onDetect: (BarcodeCapture capture) {
                if (capture.barcodes.isNotEmpty) {
                  // Only process barcode detections when camera is actively waiting for a new ticket
                  final scanner = context.read<ScannerProvider>();
                  if (scanner.state != ScanState.ready) return;

                  final rawValue = capture.barcodes.first.rawValue;
                  if (rawValue != null) {
                    _scannerController.pauseScanning();
                    _processScannedCode(rawValue);
                  }
                }
              },
              showScanHint: false,
              overlayConfig: ScannerOverlayConfig(
                // Disable the cheap up-and-down laser line completely per user request
                scannerAnimation: ScannerAnimation.none,
                scannerOverlayBackground: ScannerOverlayBackground.dim,
                backgroundColor: Colors.black.withValues(alpha: 0.60),
                borderColor: scannerProvider.state == ScanState.fetching
                    ? colorScheme.primary
                    : (scannerProvider.state == ScanState.ticketFound
                        ? (scannerProvider.currentRegistration?.isPaymentIncomplete == true
                            ? colorScheme.error
                            : colorScheme.primary)
                        : (scannerProvider.state == ScanState.error
                            ? colorScheme.error
                            : Colors.white.withValues(alpha: 0.88))),
                borderRadius: M3Shape.cornerExtraLarge, // 28dp M3 Expressive corner radius
                cornerLength: 38,
                borderStrokeWidth: 3.5,
                scannerBorder: ScannerBorder.corner,
              ),
            ),
          ),

          // 2. Scrim overlay when modal pane is open (guides focus and dismisses on tap)
          () {
            final isModalOpen = scannerProvider.state == ScanState.ticketFound &&
                scannerProvider.currentRegistration != null;
            return Positioned.fill(
              child: TweenAnimationBuilder<double>(
                tween: Tween<double>(begin: 0.0, end: isModalOpen ? 1.0 : 0.0),
                duration: M3Motion.durationDefaultEffects, // 300ms M3 default effects duration
                curve: M3Motion.expressiveDefaultEffects,
                builder: (context, scrimProgress, child) {
                  if (scrimProgress <= 0.001) return const SizedBox.shrink();
                  return GestureDetector(
                    onTap: () {
                      M3Haptics.vibrateSelection();
                      _resetScanner();
                    },
                    behavior: HitTestBehavior.opaque,
                    child: Container(
                      color: Colors.black.withValues(alpha: scrimProgress * 0.40),
                    ),
                  );
                },
              ),
            );
          }(),

          // 3. Top Header Overlay (Status Badges + Torch Action)
          Positioned(
            top: MediaQuery.of(context).padding.top + 12,
            left: 16,
            right: 16,
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Safe Mode / Live Pill
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: (settingsProvider.settings.isSafeMode
                                ? Colors.teal.shade900
                                : colorScheme.error)
                            .withValues(alpha: 0.88),
                        borderRadius: BorderRadius.circular(M3Shape.cornerLargeIncreased), // 20dp
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.15),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            settingsProvider.settings.isSafeMode ? Icons.shield_outlined : Icons.sensors,
                            color: Colors.white,
                            size: 16,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            settingsProvider.settings.isSafeMode ? 'Safe Mode' : 'Live Mode',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.bold, // Label Medium Emphasized
                            ),
                          ),
                        ],
                      ),
                    ),

                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Torch (Flashlight) Toggle Button
                        M3TactilePress(
                          onTap: () async {
                            if (!_scannerController.isRunning) return;
                            M3Haptics.vibrateSelection();
                            await _scannerController.toggleTorch();
                            setState(() {
                              _isTorchOn = !_isTorchOn;
                            });
                          },
                          child: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: (_isTorchOn ? colorScheme.primary : Colors.black87)
                                  .withValues(alpha: 0.88),
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.15),
                                  blurRadius: 8,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: Icon(
                              _isTorchOn ? Icons.flash_on : Icons.flash_off_outlined,
                              color: _isTorchOn ? colorScheme.onPrimary : Colors.white70,
                              size: 18,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),

                        // Queue status badge button
                        M3TactilePress(
                          onTap: () {
                            M3Haptics.vibrateSelection();
                            widget.onNavigateToQueue?.call();
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: (queueService.pendingCount > 0
                                      ? Colors.amber.shade900
                                      : Colors.black87)
                                  .withValues(alpha: 0.88),
                              borderRadius: BorderRadius.circular(M3Shape.cornerLargeIncreased),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.15),
                                  blurRadius: 8,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  queueService.pendingCount > 0 ? Icons.sync : Icons.checklist_rtl,
                                  color: Colors.white,
                                  size: 16,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  'Queue: ${queueService.pendingCount}',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),

                // Active Event Filter info
                if (settingsProvider.settings.activeEventIds.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(M3Shape.cornerMedium),
                    ),
                    child: Text(
                      'Matching ${settingsProvider.settings.activeEventIds.length} Event ID(s)',
                      style: const TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.w500),
                    ),
                  ),
                ],
              ],
            ),
          ),

          // 4. Bottom Controls Overlay: M3 Expressive Error Banner & Loading Indicators
          Positioned(
            bottom: 24,
            left: 16,
            right: 16,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // M3 Duplicate Scan Notice Toast
                if (scannerProvider.duplicateScanNotice != null) ...[
                  AnimatedContainer(
                    duration: M3Motion.durationFastSpatial,
                    curve: M3Motion.expressiveFastSpatial,
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    decoration: BoxDecoration(
                      color: colorScheme.inverseSurface,
                      borderRadius: BorderRadius.circular(M3Shape.cornerFull),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.28),
                          blurRadius: 10,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.info_outline_rounded, color: colorScheme.onInverseSurface, size: 18),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            scannerProvider.duplicateScanNotice!,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: colorScheme.onInverseSurface,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        GestureDetector(
                          onTap: () => scannerProvider.clearDuplicateNotice(),
                          child: Icon(Icons.close, color: colorScheme.onInverseSurface, size: 16),
                        ),
                      ],
                    ),
                  ),
                ],

                // M3 Expressive Fetching / Validating Indicator
                if (scannerProvider.state == ScanState.fetching) ...[
                  AnimatedContainer(
                    duration: M3Motion.durationFastSpatial,
                    curve: M3Motion.expressiveFastSpatial,
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.95),
                      borderRadius: BorderRadius.circular(M3Shape.cornerLarge), // 16dp
                      border: Border.all(
                        color: colorScheme.primary.withValues(alpha: 0.4),
                        width: 1.2,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.22),
                          blurRadius: 16,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            color: colorScheme.primary,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Flexible(
                          child: Text(
                            'Validating ticket with server...',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: colorScheme.onSurface,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                // M3 Expressive Error Banner
                if (scannerProvider.state == ScanState.error &&
                    scannerProvider.errorMessage != null) ...[
                  AnimatedContainer(
                    duration: M3Motion.durationFastSpatial,
                    curve: M3Motion.expressiveFastSpatial,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: colorScheme.errorContainer,
                      borderRadius: BorderRadius.circular(M3Shape.cornerLarge), // 16dp M3 Container
                      border: Border.all(
                        color: colorScheme.error.withValues(alpha: 0.25),
                        width: 1.0,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.22),
                          blurRadius: 16,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: colorScheme.error.withValues(alpha: 0.12),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                Icons.error_outline_rounded,
                                color: colorScheme.onErrorContainer,
                                size: 24,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    scannerProvider.errorTitle ?? 'Scan Error',
                                    style: theme.textTheme.titleSmall?.copyWith(
                                      fontWeight: FontWeight.bold, // M3 Emphasized Title Small (14sp / Bold)
                                      color: colorScheme.onErrorContainer,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    scannerProvider.errorMessage!,
                                    style: theme.textTheme.bodyMedium?.copyWith(
                                      color: colorScheme.onErrorContainer.withValues(alpha: 0.90),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              icon: Icon(Icons.close, color: colorScheme.onErrorContainer, size: 20),
                              tooltip: 'Dismiss error',
                              onPressed: () {
                                M3Haptics.vibrateSelection();
                                _resetScanner();
                              },
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            TextButton.icon(
                              style: TextButton.styleFrom(
                                foregroundColor: colorScheme.onErrorContainer,
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                              ),
                              onPressed: () {
                                M3Haptics.vibrateSelection();
                                _resetScanner();
                              },
                              icon: const Icon(Icons.refresh, size: 18),
                              label: Text(
                                'Scan Again',
                                style: theme.textTheme.labelLarge?.copyWith(
                                  fontWeight: FontWeight.bold, // M3 Emphasized Label Large (14sp / Bold)
                                  color: colorScheme.onErrorContainer,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),

          // 5. Ticket Preview Sheet when ticket is retrieved
          if (scannerProvider.state == ScanState.ticketFound &&
              scannerProvider.currentRegistration != null) ...[
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: TicketPreviewSheet(
                registration: scannerProvider.currentRegistration!,
                scannerProvider: scannerProvider,
                onDismiss: _resetScanner,
              ),
            ),
          ],

          // 6. Checked-in Confirmation Banner
          if (scannerProvider.lastCheckedInFeedback != null &&
              scannerProvider.state == ScanState.ready) ...[
            Positioned(
              bottom: 24,
              left: 16,
              right: 16,
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: 0.0, end: 1.0),
                duration: M3Motion.durationDefaultEffects,
                builder: (context, val, child) => Opacity(opacity: val, child: child),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: Colors.green.shade900.withValues(alpha: 0.94),
                    borderRadius: BorderRadius.circular(M3Shape.cornerLarge),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.25),
                        blurRadius: 16,
                        offset: const Offset(0, 4),
                      ),
                    ],
                    border: Border.all(color: Colors.green.shade400, width: 1.0),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.check_circle_rounded, color: Colors.white, size: 24),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          scannerProvider.lastCheckedInFeedback!,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                      ),
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        icon: const Icon(Icons.close, color: Colors.white70, size: 18),
                        onPressed: () => scannerProvider.clearCheckedInFeedback(),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
