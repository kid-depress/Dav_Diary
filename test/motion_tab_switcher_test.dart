import 'package:diary/ui/motion/motion_tab_switcher.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('rapid switches keep opacity continuous and show latest tab', (
    tester,
  ) async {
    var index = 0;
    late StateSetter update;
    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) {
            update = setState;
            return MotionTabSwitcher(
              index: index,
              children: const [
                Text('Home'),
                Text('Calendar'),
                Text('Settings'),
              ],
            );
          },
        ),
      ),
    );
    double opacity() => tester
        .widget<FadeTransition>(
          find.descendant(
            of: find.byType(MotionTabSwitcher),
            matching: find.byType(FadeTransition),
          ),
        )
        .opacity
        .value;
    update(() => index = 1);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 40));
    final before = opacity();
    update(() => index = 2);
    await tester.pump();
    expect(opacity(), closeTo(before, 0.001));
    await tester.pumpAndSettle();
    expect(find.text('Settings'), findsOneWidget);
    expect(find.text('Home'), findsNothing);
    expect(opacity(), 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('reduced motion switches immediately and retains page state', (
    tester,
  ) async {
    var index = 0;
    late StateSetter update;
    final fieldKey = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) {
            update = setState;
            return MediaQuery(
              data: const MediaQueryData(disableAnimations: true),
              child: Material(
                child: MotionTabSwitcher(
                  index: index,
                  children: [
                    TextField(key: fieldKey),
                    const Text('Calendar'),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
    await tester.enterText(find.byType(TextField), 'Saved draft');
    final originalState = fieldKey.currentState;
    update(() => index = 1);
    await tester.pump();
    expect(find.text('Calendar'), findsOneWidget);
    expect(fieldKey.currentState, same(originalState));
    update(() => index = 0);
    await tester.pump();
    expect(find.text('Saved draft'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
