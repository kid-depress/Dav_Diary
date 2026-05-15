import 'package:flutter/material.dart';

class StaggeredEntrance extends StatefulWidget {
  const StaggeredEntrance({
    required this.index,
    required this.child,
    this.skipAnimation = false,
    super.key,
  });

  final int index;
  final Widget child;
  final bool skipAnimation;

  static const perItemMs = 22;
  static const maxStaggerMs = 140;

  @override
  State<StaggeredEntrance> createState() => _StaggeredEntranceState();
}

class _StaggeredEntranceState extends State<StaggeredEntrance>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _opacity;
  late final Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    if (widget.skipAnimation) {
      _controller = AnimationController(
        duration: Duration.zero,
        vsync: this,
      )..forward();
      _opacity = const AlwaysStoppedAnimation(1.0);
      _slide = const AlwaysStoppedAnimation(Offset.zero);
      return;
    }

    final delayMs =
        (widget.index * StaggeredEntrance.perItemMs)
            .clamp(0, StaggeredEntrance.maxStaggerMs);
    const totalMs = 340;
    final delayFraction = delayMs / totalMs;

    _controller = AnimationController(
      duration: const Duration(milliseconds: totalMs),
      vsync: this,
    );

    _opacity = CurvedAnimation(
      parent: _controller,
      curve: Interval(delayFraction, 1.0, curve: Curves.easeOut),
    );
    _slide = Tween<Offset>(
      begin: const Offset(0, 0.05),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Interval(delayFraction, 1.0, curve: Curves.easeOutCubic),
    ));

    Future.microtask(() {
      if (mounted) _controller.forward();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _opacity,
      child: SlideTransition(position: _slide, child: widget.child),
    );
  }
}
