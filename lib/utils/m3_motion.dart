import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// M3 Expressive Motion Tokens and Curves
/// Source: .agent-skills/m3-expressive/references/tokens.md and references/motion.md
class M3Motion {
  M3Motion._();

  // --- Expressive Spatial Springs (Movements, resizing, sliding, scaling) ---
  /// Expressive fast spatial: damping 0.6, stiffness 800 (bounce overshoot)
  static const Curve expressiveFastSpatial = Cubic(0.42, 1.67, 0.21, 0.90);
  static const Duration durationFastSpatial = Duration(milliseconds: 350);

  /// Expressive default spatial: damping 0.8, stiffness 380 (snappy settling)
  static const Curve expressiveDefaultSpatial = Cubic(0.38, 1.21, 0.22, 1.00);
  static const Duration durationDefaultSpatial = Duration(milliseconds: 500);

  /// Expressive slow spatial: damping 0.8, stiffness 200 (full screen transitions)
  static const Curve expressiveSlowSpatial = Cubic(0.39, 1.29, 0.35, 0.98);
  static const Duration durationSlowSpatial = Duration(milliseconds: 650);

  // --- Expressive Effects Springs (Fades, color shifts, opacity - damping 1.0, NO overshoot) ---
  /// Expressive fast effects: damping 1.0, stiffness 3800
  static const Curve expressiveFastEffects = Cubic(0.31, 0.94, 0.34, 1.00);
  static const Duration durationFastEffects = Duration(milliseconds: 150);

  /// Expressive default effects: damping 1.0, stiffness 1600
  static const Curve expressiveDefaultEffects = Cubic(0.34, 0.80, 0.34, 1.00);
  static const Duration durationDefaultEffects = Duration(milliseconds: 200);

  /// Expressive slow effects: damping 1.0, stiffness 800
  static const Curve expressiveSlowEffects = Cubic(0.34, 0.88, 0.34, 1.00);
  static const Duration durationSlowEffects = Duration(milliseconds: 300);
}

/// M3 Corner Radii Tokens
/// Source: .agent-skills/m3-expressive/references/tokens.md
class M3Shape {
  M3Shape._();

  static const double cornerNone = 0.0;
  static const double cornerExtraSmall = 4.0;
  static const double cornerSmall = 8.0;
  static const double cornerMedium = 12.0;
  static const double cornerLarge = 16.0;
  static const double cornerLargeIncreased = 20.0;
  static const double cornerExtraLarge = 28.0;
  static const double cornerExtraLargeIncreased = 32.0;
  static const double cornerExtraExtraLarge = 48.0;
  static const double cornerFull = 999.0; // Fully rounded stadium / pill shape

  /// Optical roundness helper: inner radius = outer radius - padding
  static double opticalInnerRadius(double outerRadius, double padding) {
    return (outerRadius - padding).clamp(0.0, outerRadius);
  }
}

/// Tactile Haptics Engine for subtle scanning feedback
class M3Haptics {
  M3Haptics._();

  /// Subtle vibration on QR barcode detected and valid
  static Future<void> vibrateScanSuccess() async {
    await HapticFeedback.lightImpact();
  }

  /// High-end rhythmic error cadence for invalid, unpaid, already-used, or mismatched tickets.
  /// Uses a crisp staccato double-pulse pattern (heavy impact -> 85ms micro-pause -> heavy impact)
  /// modeled after modern premium OS error haptics (iOS CoreHaptics / Android Rich Haptics).
  static Future<void> vibrateScanError() async {
    await HapticFeedback.heavyImpact();
    await Future<void>.delayed(const Duration(milliseconds: 85));
    await HapticFeedback.heavyImpact();
  }

  /// Tactile feedback when pressing primary action buttons (Check-In)
  static Future<void> vibrateAction() async {
    await HapticFeedback.mediumImpact();
  }

  /// Subtle click feedback on navigation or filter selection
  static Future<void> vibrateSelection() async {
    await HapticFeedback.selectionClick();
  }
}

/// Snappy Spring-Press Tactile Wrapper
/// Scales down slightly (0.96) on touch down and springs back with M3 Fast Spatial spring.
class M3TactilePress extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final double pressScale;

  const M3TactilePress({
    super.key,
    required this.child,
    this.onTap,
    this.pressScale = 0.96,
  });

  @override
  State<M3TactilePress> createState() => _M3TactilePressState();
}

class _M3TactilePressState extends State<M3TactilePress> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 120),
      reverseDuration: M3Motion.durationFastSpatial,
    );
    _scaleAnimation = Tween<double>(
      begin: 1.0,
      end: widget.pressScale,
    ).animate(
      CurvedAnimation(
        parent: _controller,
        curve: Curves.easeOutCubic,
        reverseCurve: M3Motion.expressiveFastSpatial,
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onTapDown(TapDownDetails details) {
    if (widget.onTap == null) return;
    _controller.forward();
  }

  void _onTapUp(TapUpDetails details) {
    if (widget.onTap == null) return;
    _controller.reverse();
    widget.onTap!();
  }

  void _onTapCancel() {
    if (widget.onTap == null) return;
    _controller.reverse();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: _onTapDown,
      onTapUp: _onTapUp,
      onTapCancel: _onTapCancel,
      child: AnimatedBuilder(
        animation: _scaleAnimation,
        builder: (context, child) => Transform.scale(
          scale: _scaleAnimation.value,
          child: child,
        ),
        child: widget.child,
      ),
    );
  }
}
