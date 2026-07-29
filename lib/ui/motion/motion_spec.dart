import 'package:flutter/material.dart';

/// Centralised Material Design 3 motion tokens.
///
/// Easing maps to Flutter's built-in [Easing] set, which mirrors the official
/// M3 easing specs, and durations follow the M3 duration scale:
/// https://m3.material.io/styles/motion/easing-and-duration/tokens-specs
///
/// Semantic aliases at the bottom keep existing call sites working while
/// re-pointing them at the M3 values.
class MotionSpec {
  const MotionSpec._();

  // ---- Easing tokens (M3) ----
  /// Signature M3 curve: a slow-in/strong-out feel for prominent transitions.
  /// Defined explicitly as the official M3 three-point cubic (not all Flutter
  /// versions expose `Easing.emphasized`).
  static const Curve emphasized = ThreePointCubic(
    Offset(0.05, 0),
    Offset(0.133, 0.06),
    Offset(0.166, 0.4),
    Offset(0.208, 0.82),
    Offset(0.25, 1),
  );

  /// Enter / appear — decelerates into place. Use for incoming content.
  static const Curve emphasizedDecelerate = Easing.emphasizedDecelerate;

  /// Exit / disappear — accelerates away. Use for outgoing content.
  static const Curve emphasizedAccelerate = Easing.emphasizedAccelerate;

  /// Functional, small-area transitions (state changes, toggles).
  static const Curve standard = Easing.standard;
  static const Curve standardDecelerate = Easing.standardDecelerate;
  static const Curve standardAccelerate = Easing.standardAccelerate;

  // ---- Duration tokens (M3) ----
  static const Duration short2 = Duration(milliseconds: 100);
  static const Duration short3 = Duration(milliseconds: 150);
  static const Duration short4 = Duration(milliseconds: 200);
  static const Duration medium1 = Duration(milliseconds: 250);
  static const Duration medium2 = Duration(milliseconds: 300);
  static const Duration medium4 = Duration(milliseconds: 400);

  // ---- Semantic aliases (existing call sites) ----

  // Page transitions — shared-axis feel.
  static const Duration pageTransitionDuration = medium2;
  static const Curve pageTransitionCurve = emphasized;
  static const Curve pageTransitionReverseCurve = emphasizedAccelerate;

  // Card -> detail expand (paired with a Hero).
  static const Duration cardExpandDuration = medium2;
  static const Curve cardExpandCurve = emphasizedDecelerate;

  // Press / state-layer feedback.
  static const Duration clickDuration = short2;
  static const Curve clickCurve = standard;

  // Popups, dialogs, floating toolbars.
  static const Duration popupDuration = short4;
  static const Curve popupCurve = emphasizedDecelerate;
  static const Curve popupReverseCurve = emphasizedAccelerate;

  // Tab / view switching (fade-through).
  static const Duration tabSwitchDuration = medium1;

  // ---- Accessibility: reduce motion ----

  /// Whether the platform "remove animations" accessibility setting is on.
  ///
  /// When true, we follow the M3-recommended degraded mode: drop spatial
  /// motion (slides, scales, staggers) but keep short opacity cross-fades so
  /// the UI stays legible without vestibular-triggering movement.
  static bool reduceMotion(BuildContext context) =>
      MediaQuery.maybeOf(context)?.disableAnimations ?? false;
}
