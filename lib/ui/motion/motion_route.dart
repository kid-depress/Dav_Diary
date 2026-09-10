import 'package:diary/ui/motion/motion_spec.dart';
import 'package:flutter/material.dart';

/// Shared M3 "shared-axis" transition used by both pushed routes and the
/// app-wide [PageTransitionsTheme]. The incoming page fades in while sliding a
/// short distance from the trailing edge; the outgoing page eases slightly the
/// opposite way, giving a coordinated, spatial sense of forward/back movement.
///
/// All motion is opacity + transform only (no layout passes, no clips), so it
/// stays cheap on the raster thread.
class MotionPageTransition extends StatelessWidget {
  const MotionPageTransition({
    required this.animation,
    required this.secondaryAnimation,
    required this.child,
    super.key,
  });

  final Animation<double> animation;
  final Animation<double> secondaryAnimation;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    // Reduce-motion: a plain opacity cross-fade, no slide.
    if (MotionSpec.reduceMotion(context)) {
      return FadeTransition(
        opacity: animation.drive(CurveTween(curve: Curves.easeOut)),
        child: child,
      );
    }

    final enter = animation.drive(
      CurveTween(curve: MotionSpec.standardDecelerate),
    );
    final exit = secondaryAnimation.drive(
      CurveTween(curve: MotionSpec.standardDecelerate),
    );

    return FadeTransition(
      opacity: enter,
      child: SlideTransition(
        textDirection: Directionality.of(context),
        position: Tween<Offset>(
          begin: const Offset(0.035, 0),
          end: Offset.zero,
        ).animate(enter),
        child: SlideTransition(
          textDirection: Directionality.of(context),
          position: Tween<Offset>(
            begin: Offset.zero,
            end: const Offset(-0.015, 0),
          ).animate(exit),
          child: child,
        ),
      ),
    );
  }
}

/// Plugs [MotionPageTransition] into [ThemeData.pageTransitionsTheme] so that
/// default `MaterialPageRoute`s (e.g. ones pushed by dependencies) match the
/// custom routes below.
class MotionPageTransitionsBuilder extends PageTransitionsBuilder {
  const MotionPageTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    return MotionPageTransition(
      animation: animation,
      secondaryAnimation: secondaryAnimation,
      child: child,
    );
  }
}

Route<T> buildPageTransitionRoute<T>(Widget page) {
  return PageRouteBuilder<T>(
    transitionDuration: MotionSpec.pageTransitionDuration,
    reverseTransitionDuration: MotionSpec.short4,
    pageBuilder: (context, animation, secondaryAnimation) => page,
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      return MotionPageTransition(
        animation: animation,
        secondaryAnimation: secondaryAnimation,
        child: child,
      );
    },
  );
}

Route<T> buildCardExpandPreviewRoute<T>(Widget page) {
  return PageRouteBuilder<T>(
    transitionDuration: MotionSpec.cardExpandDuration,
    reverseTransitionDuration: MotionSpec.popupDuration,
    pageBuilder: (context, animation, secondaryAnimation) => page,
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      if (MotionSpec.reduceMotion(context)) {
        return FadeTransition(
          opacity: animation.drive(CurveTween(curve: Curves.easeOut)),
          child: child,
        );
      }
      final curved = animation.drive(
        CurveTween(curve: MotionSpec.standardDecelerate),
      );
      return FadeTransition(
        opacity: curved,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.98, end: 1).animate(curved),
          child: child,
        ),
      );
    },
  );
}
