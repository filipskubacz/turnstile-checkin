import 'package:flutter/material.dart';
import '../utils/m3_motion.dart';

/// Material Design 3 Expressive Swipe-to-Confirm Slider Lock
///
/// Implements a tactile, high-security slide-to-unlock mechanism fitting M3 Expressive:
/// - 56dp container height (M3 button / container standard)
/// - Stadium border (M3Shape.cornerFull)
/// - Spring return / snap-to-end physics (M3Motion.expressiveFastSpatial)
/// - Color scheme roles & contrast pairing
/// - Tactile haptic feedback on sliding and unlocking
class M3SwipeLock extends StatefulWidget {
  final String label;
  final VoidCallback onConfirmed;
  final Color? confirmColor;
  final Color? trackColor;
  final Color? textColor;
  final IconData lockIcon;
  final IconData unlockedIcon;
  final double height;
  final double? width;

  const M3SwipeLock({
    super.key,
    required this.onConfirmed,
    this.label = 'Swipe to Confirm',
    this.confirmColor,
    this.trackColor,
    this.textColor,
    this.lockIcon = Icons.lock_outline_rounded,
    this.unlockedIcon = Icons.lock_open_rounded,
    this.height = 56.0,
    this.width,
  });

  @override
  State<M3SwipeLock> createState() => _M3SwipeLockState();
}

class _M3SwipeLockState extends State<M3SwipeLock> with SingleTickerProviderStateMixin {
  final GlobalKey _trackKey = GlobalKey();
  late AnimationController _animController;
  late Animation<double> _resetAnimation;
  double _dragOffset = 0.0;
  double _trackWidth = 280.0;
  bool _isConfirmed = false;
  bool _halfwayVibrated = false;

  @override
  void initState() {
    super.initState();
    _trackWidth = widget.width ?? 280.0;
    _animController = AnimationController(
      vsync: this,
      duration: M3Motion.durationFastSpatial,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        final oldWidth = _trackWidth;
        _updateTrackWidth();
        if ((oldWidth - _trackWidth).abs() > 1.0) {
          setState(() {});
        }
      }
    });
  }

  void _updateTrackWidth() {
    if (widget.width != null) {
      _trackWidth = widget.width!;
      return;
    }
    final RenderBox? box = _trackKey.currentContext?.findRenderObject() as RenderBox?;
    if (box != null && box.hasSize && box.size.width > 0) {
      _trackWidth = box.size.width;
    }
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  void _animateTo(double targetOffset) {
    _resetAnimation = Tween<double>(
      begin: _dragOffset,
      end: targetOffset,
    ).animate(
      CurvedAnimation(
        parent: _animController,
        curve: M3Motion.expressiveFastSpatial,
      ),
    )..addListener(() {
        setState(() {
          _dragOffset = _resetAnimation.value;
        });
      });

    _animController.forward(from: 0.0);
  }

  @override
  Widget build(BuildContext context) {
    _updateTrackWidth();
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final primaryColor = widget.confirmColor ?? colorScheme.error;
    final baseTrackColor = widget.trackColor ?? primaryColor.withValues(alpha: 0.12);
    final thumbSize = widget.height - 8.0; // 4dp internal padding all around

    final effectiveWidth = widget.width ?? _trackWidth;
    final maxDragDistance = (effectiveWidth - thumbSize - 8.0).clamp(0.0, double.infinity);
    final progress = maxDragDistance > 0 ? (_dragOffset / maxDragDistance).clamp(0.0, 1.0) : 0.0;
    final isNearThreshold = progress >= 0.85;

    return Container(
      key: _trackKey,
      width: widget.width,
      height: widget.height,
          decoration: BoxDecoration(
            color: baseTrackColor,
            borderRadius: BorderRadius.circular(M3Shape.cornerFull),
            border: Border.all(
              color: primaryColor.withValues(alpha: 0.30),
              width: 1.2,
            ),
          ),
          child: Stack(
            alignment: Alignment.centerLeft,
            children: [
              // 1. Shaded progress bar tracking the thumb
              Positioned(
                left: 0,
                top: 0,
                bottom: 0,
                width: _dragOffset + thumbSize + 8.0,
                child: Container(
                  decoration: BoxDecoration(
                    color: primaryColor.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(M3Shape.cornerFull),
                  ),
                ),
              ),

              // 2. Track Centered Label with dynamic fade as slider advances
              Center(
                child: Opacity(
                  opacity: (1.0 - (progress * 1.8)).clamp(0.0, 1.0),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 48.0),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Flexible(
                          child: Text(
                            widget.label,
                            style: theme.textTheme.labelLarge?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: widget.textColor ?? colorScheme.onSurfaceVariant,
                              letterSpacing: 0.2,
                            ),
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Icon(
                          Icons.chevron_right_rounded,
                          size: 18,
                          color: widget.textColor?.withValues(alpha: 0.6) ??
                              colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
                        ),
                        Icon(
                          Icons.chevron_right_rounded,
                          size: 18,
                          color: widget.textColor?.withValues(alpha: 0.3) ??
                              colorScheme.onSurfaceVariant.withValues(alpha: 0.3),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              // 3. Sliding Draggable Thumb
              Positioned(
                left: 4.0 + _dragOffset,
                child: GestureDetector(
                  onHorizontalDragUpdate: (details) {
                    if (_isConfirmed) return;
                    setState(() {
                      _dragOffset = (_dragOffset + details.delta.dx).clamp(0.0, maxDragDistance);
                      final currentProgress = maxDragDistance > 0 ? _dragOffset / maxDragDistance : 0.0;

                      // Subtle click feedback when passing halfway mark
                      if (currentProgress >= 0.5 && !_halfwayVibrated) {
                        _halfwayVibrated = true;
                        M3Haptics.vibrateSelection();
                      } else if (currentProgress < 0.5 && _halfwayVibrated) {
                        _halfwayVibrated = false;
                      }
                    });
                  },
                  onHorizontalDragEnd: (details) {
                    if (_isConfirmed) return;
                    final currentProgress = maxDragDistance > 0 ? _dragOffset / maxDragDistance : 0.0;

                    if (currentProgress >= 0.85) {
                      // Confirmed! Lock to end and trigger action
                      _isConfirmed = true;
                      _animateTo(maxDragDistance);
                      M3Haptics.vibrateAction();
                      widget.onConfirmed();
                    } else {
                      // Released before threshold: spring bounce back to start
                      _halfwayVibrated = false;
                      _animateTo(0.0);
                    }
                  },
                  child: Container(
                    width: thumbSize,
                    height: thumbSize,
                    decoration: BoxDecoration(
                      color: primaryColor,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: primaryColor.withValues(alpha: 0.35),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Center(
                      child: AnimatedSwitcher(
                        duration: M3Motion.durationFastEffects,
                        transitionBuilder: (child, anim) => ScaleTransition(scale: anim, child: child),
                        child: Icon(
                          isNearThreshold ? widget.unlockedIcon : widget.lockIcon,
                          key: ValueKey<bool>(isNearThreshold),
                          color: colorScheme.onError,
                          size: 22,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
  }
}
