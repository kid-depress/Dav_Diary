import 'package:diary/ui/motion/motion_spec.dart';
import 'package:flutter/material.dart';

/// Keeps tab state alive and retargets interrupted fades without a visual jump.
class MotionTabSwitcher extends StatefulWidget {
  const MotionTabSwitcher({
    required this.index,
    required this.children,
    super.key,
  });

  final int index;
  final List<Widget> children;

  @override
  State<MotionTabSwitcher> createState() => _MotionTabSwitcherState();
}

class _MotionTabSwitcherState extends State<MotionTabSwitcher>
    with SingleTickerProviderStateMixin {
  late int _visibleIndex = widget.index;
  late final Set<int> _visited = {widget.index};
  bool _reduceMotion = false;
  late final AnimationController _controller = AnimationController(
    vsync: this,
    value: 1,
    duration: MotionSpec.short3,
    reverseDuration: MotionSpec.short2,
  )..addStatusListener(_onStatus);
  late final Animation<double> _opacity = _controller.drive(
    CurveTween(curve: MotionSpec.standard),
  );

  void _onStatus(AnimationStatus status) {
    if (status != AnimationStatus.dismissed) return;
    setState(() => _visibleIndex = widget.index);
    _controller.forward();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = MotionSpec.reduceMotion(context);
    if (_reduceMotion) {
      _visibleIndex = widget.index;
      _controller.value = 1;
    }
  }

  @override
  void didUpdateWidget(covariant MotionTabSwitcher oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.index == widget.index) return;
    _visited.add(widget.index);
    if (_reduceMotion) {
      _visibleIndex = widget.index;
      _controller.value = 1;
    } else if (widget.index == _visibleIndex) {
      _controller.forward();
    } else {
      // Reverse from the current opacity; further taps only change the target.
      _controller.reverse();
    }
  }

  @override
  void dispose() {
    _controller
      ..removeStatusListener(_onStatus)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      ignoring: _visibleIndex != widget.index,
      child: FadeTransition(
        opacity: _opacity,
        child: IndexedStack(
          index: _visibleIndex,
          children: [
            for (var i = 0; i < widget.children.length; i++)
              TickerMode(
                enabled: i == _visibleIndex,
                child: ExcludeFocus(
                  excluding: i != _visibleIndex,
                  child: _visited.contains(i)
                      ? RepaintBoundary(child: widget.children[i])
                      : const SizedBox.expand(),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
