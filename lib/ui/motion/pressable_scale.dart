import 'package:diary/ui/motion/motion_spec.dart';
import 'package:flutter/material.dart';

/// A subtle press-scale wrapper for tappable surfaces (cards, tiles).
///
/// Follows the M3 state-layer feel: a small, quick scale-down on press and a
/// softer, decelerating release. The motion is a single [AnimatedScale]
/// (transform only), so it adds no measurable raster cost.
class PressableScale extends StatefulWidget {
  const PressableScale({
    required this.child,
    this.pressedScale = 0.97,
    super.key,
  });

  final Widget child;
  final double pressedScale;

  @override
  State<PressableScale> createState() => _PressableScaleState();
}

class _PressableScaleState extends State<PressableScale> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (_pressed == value) {
      return;
    }
    setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    // Honour the system "remove animations" setting: skip the scale transform
    // entirely (it's spatial motion) but keep the tap target fully functional.
    if (MotionSpec.reduceMotion(context)) {
      return GestureDetector(
        behavior: HitTestBehavior.translucent,
        child: widget.child,
      );
    }
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTapDown: (_) => _setPressed(true),
      onTapUp: (_) => _setPressed(false),
      onTapCancel: () => _setPressed(false),
      child: AnimatedScale(
        scale: _pressed ? widget.pressedScale : 1,
        // Press-down is snappy; release decelerates for a tactile rebound.
        duration: _pressed ? MotionSpec.short2 : MotionSpec.short4,
        curve: _pressed
            ? MotionSpec.standardAccelerate
            : MotionSpec.emphasizedDecelerate,
        child: widget.child,
      ),
    );
  }
}
