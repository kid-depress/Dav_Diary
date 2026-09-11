import 'dart:convert';
import 'dart:io';

import 'package:diary/data/models/diary_entry.dart';
import 'package:diary/ui/preview/entry_preview_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Hero landing shows the resolved image without a placeholder frame', (
    tester,
  ) async {
    final directory = await tester.runAsync(
      () => Directory.systemTemp.createTemp('diary-preview-'),
    );
    final file = File('${directory!.path}/image.png');
    await tester.runAsync(
      () => file.writeAsBytes(
        base64Decode(
          'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jRZkAAAAASUVORK5CYII=',
        ),
      ),
    );
    addTearDown(() => directory.delete(recursive: true));
    final now = DateTime(2026, 9, 11);
    final entry = DiaryEntry(
      id: 'hero-entry',
      title: 'Preview',
      deltaJson: '[{"insert":"Hello\\n"}]',
      plainText: 'Hello',
      createdAt: now,
      updatedAt: now,
      eventAt: now,
      mood: '',
      weather: '',
      location: '',
      attachments: [
        DiaryAttachment(path: file.path, type: AttachmentType.file),
        DiaryAttachment(path: file.path, type: AttachmentType.image),
      ],
    );
    Widget app(Widget child) => MaterialApp(
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        FlutterQuillLocalizations.delegate,
      ],
      home: child,
    );
    await tester.runAsync(() async {
      await tester.pumpWidget(app(EntryPreviewPage(entry: entry)));
      final futures = tester
          .widgetList<FutureBuilder<String?>>(
            find.byType(FutureBuilder<String?>),
          )
          .map((widget) => widget.future!)
          .toList();
      await Future.wait(futures);
      await tester.pump();
      final hero = tester.widget<Hero>(find.byType(Hero));
      expect(
        find.descendant(of: find.byType(Hero), matching: find.byType(Image)),
        findsOneWidget,
      );

      // Like the Hero overlay/landing, create a fresh subtree for the same image.
      // Check its very first frame, before another pump can hide the regression.
      await tester.pumpWidget(app(Scaffold(body: hero.child)));
      expect(find.byType(Image), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  });
}
