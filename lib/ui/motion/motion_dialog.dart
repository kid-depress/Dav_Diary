import 'package:diary/ui/motion/motion_spec.dart';
import 'package:flutter/material.dart';

Future<T?> showMotionDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool barrierDismissible = true,
  Color? barrierColor,
  String? barrierLabel,
  bool useRootNavigator = true,
}) {
  final capturedThemes = InheritedTheme.capture(
    from: context,
    to: Navigator.of(context, rootNavigator: useRootNavigator).context,
  );

  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: barrierDismissible,
    barrierLabel:
        barrierLabel ??
        MaterialLocalizations.of(context).modalBarrierDismissLabel,
    barrierColor: barrierColor ?? Colors.black54,
    transitionDuration: MotionSpec.popupDuration,
    pageBuilder: (dialogContext, animation, secondaryAnimation) {
      final child = Builder(builder: builder);
      return capturedThemes.wrap(
        SafeArea(
          child: Builder(
            builder: (safeContext) {
              final dialogChild = Align(
                alignment: Alignment.center,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 560),
                  child: child,
                ),
              );
              return Material(
                type: MaterialType.transparency,
                child: dialogChild,
              );
            },
          ),
        ),
      );
    },
    transitionBuilder: (dialogContext, animation, secondaryAnimation, child) {
      if (MotionSpec.reduceMotion(dialogContext)) {
        return FadeTransition(
          opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
          child: child,
        );
      }
      final curved = CurvedAnimation(
        parent: animation,
        curve: MotionSpec.popupCurve,
        reverseCurve: MotionSpec.popupReverseCurve,
      );
      return FadeTransition(
        opacity: curved,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.92, end: 1.0).animate(curved),
          child: child,
        ),
      );
    },
  );
}
