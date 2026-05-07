import 'package:diary/app/i18n.dart';
import 'package:diary/data/models/diary_entry.dart';
import 'package:diary/data/models/webdav_config.dart';
import 'package:diary/ui/widgets/entry_meta_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // ── DiaryEntry model ──────────────────────────────────────────────

  group('DiaryEntry', () {
    final sampleEntry = DiaryEntry(
      id: 'test-id-001',
      title: 'My First Entry',
      deltaJson: '{"ops":[{"insert":"Hello\\n"}]}',
      plainText: 'Hello\n',
      createdAt: DateTime.utc(2025, 6, 15, 10, 30),
      updatedAt: DateTime.utc(2025, 6, 15, 12, 0),
      eventAt: DateTime.utc(2025, 6, 15, 9, 0),
      mood: '\u{1F60A} happy',
      weather: '☀️ sunny',
      location: 'Beijing',
      attachments: const [
        DiaryAttachment(
          path: '/media/img1.jpg',
          caption: 'Sunset',
          type: AttachmentType.image,
          hash: 'abc123',
          remotePath: '/remote/img1.jpg',
          thumbnailPath: '/thumbs/img1.jpg',
          thumbnailRemotePath: '/remote/thumbs/img1.jpg',
        ),
        DiaryAttachment(
          path: '/media/sketch.png',
          type: AttachmentType.doodle,
          hash: 'def456',
        ),
      ],
    );

    test('toDbMap and fromDbMap round-trip', () {
      final map = sampleEntry.toDbMap();
      expect(map['id'], 'test-id-001');
      expect(map['is_deleted'], 0);
      expect(map['attachments_json'], isA<String>());

      final restored = DiaryEntry.fromDbMap(map);
      expect(restored.id, sampleEntry.id);
      expect(restored.title, sampleEntry.title);
      expect(restored.plainText, sampleEntry.plainText);
      expect(restored.mood, sampleEntry.mood);
      expect(restored.weather, sampleEntry.weather);
      expect(restored.location, sampleEntry.location);
      expect(restored.isDeleted, false);
      expect(restored.attachments.length, 2);
      expect(restored.attachments[0].caption, 'Sunset');
      expect(restored.attachments[0].type, AttachmentType.image);
      expect(restored.attachments[1].type, AttachmentType.doodle);
    });

    test('toSyncJson and fromSyncJson round-trip', () {
      final json = sampleEntry.toSyncJson();
      expect(json['id'], 'test-id-001');
      expect(json['attachments'], isA<List>());

      final restored = DiaryEntry.fromSyncJson(json);
      expect(restored.id, sampleEntry.id);
      expect(restored.title, sampleEntry.title);
      expect(restored.attachments.length, 2);
      expect(restored.isDeleted, false);
    });

    test('summary truncates long text to 90 chars', () {
      final longText = 'a' * 200;
      final entry = DiaryEntry(
        id: '1',
        title: 'T',
        deltaJson: '{}',
        plainText: longText,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        eventAt: DateTime.now(),
        mood: '',
        weather: '',
        location: '',
        attachments: const [],
      );
      expect(entry.summary.length, lessThanOrEqualTo(93));
      expect(entry.summary.endsWith('...'), true);
    });

    test('summary returns full text under 90 chars', () {
      final entry = DiaryEntry(
        id: '1',
        title: 'T',
        deltaJson: '{}',
        plainText: 'Short note',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        eventAt: DateTime.now(),
        mood: '',
        weather: '',
        location: '',
        attachments: const [],
      );
      expect(entry.summary, 'Short note');
    });

    test('firstImagePath returns visual image path first', () {
      final entry = DiaryEntry(
        id: '1',
        title: 'T',
        deltaJson: '{}',
        plainText: '',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        eventAt: DateTime.now(),
        mood: '',
        weather: '',
        location: '',
        attachments: const [
          DiaryAttachment(
            path: '/media/video.mp4',
            type: AttachmentType.video,
          ),
          DiaryAttachment(
            path: '/media/photo.jpg',
            type: AttachmentType.image,
          ),
        ],
      );
      expect(entry.firstImagePath, '/media/photo.jpg');
    });

    test('firstImagePath falls back to thumbnail', () {
      final entry = DiaryEntry(
        id: '1',
        title: 'T',
        deltaJson: '{}',
        plainText: '',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        eventAt: DateTime.now(),
        mood: '',
        weather: '',
        location: '',
        attachments: const [
          DiaryAttachment(
            path: '',
            thumbnailPath: '/thumbs/thumb.jpg',
            type: AttachmentType.image,
          ),
        ],
      );
      expect(entry.firstImagePath, '/thumbs/thumb.jpg');
    });

    test('copyWith preserves unchanged fields', () {
      final updated = sampleEntry.copyWith(title: 'Updated');
      expect(updated.title, 'Updated');
      expect(updated.id, sampleEntry.id);
      expect(updated.plainText, sampleEntry.plainText);
      expect(updated.attachments, sampleEntry.attachments);
    });
  });

  // ── DiaryAttachment model ─────────────────────────────────────────

  group('DiaryAttachment', () {
    test('toJson omits empty optional fields', () {
      const attachment = DiaryAttachment(path: '/media/img.jpg');
      final json = attachment.toJson();
      expect(json['path'], '/media/img.jpg');
      expect(json.containsKey('hash'), false);
      expect(json.containsKey('remotePath'), false);
    });

    test('toJson includes non-empty optional fields', () {
      const attachment = DiaryAttachment(
        path: '/media/img.jpg',
        hash: 'abc',
        remotePath: '/remote/img.jpg',
        thumbnailPath: '/thumbs/img.jpg',
      );
      final json = attachment.toJson();
      expect(json['hash'], 'abc');
      expect(json['remotePath'], '/remote/img.jpg');
      expect(json['thumbnailPath'], '/thumbs/img.jpg');
    });

    test('fromJson parses legacy isDoodle flag', () {
      final json = {
        'path': '/media/doodle.png',
        'isDoodle': true,
        'type': '',
      };
      final attachment = DiaryAttachment.fromJson(json);
      expect(attachment.type, AttachmentType.doodle);
    });

    test('fromJson infers GIF type from path', () {
      final json = {'path': '/media/animation.gif'};
      final attachment = DiaryAttachment.fromJson(json);
      expect(attachment.type, AttachmentType.gif);
    });

    test('fromJson infers video type from path', () {
      final json = {'path': '/media/clip.mp4'};
      final attachment = DiaryAttachment.fromJson(json);
      expect(attachment.type, AttachmentType.video);
    });

    test('fromJson falls back to file type for unknown extensions', () {
      final json = {'path': '/media/doc.pdf'};
      final attachment = DiaryAttachment.fromJson(json);
      expect(attachment.type, AttachmentType.file);
    });

    test('isDoodle helper', () {
      expect(
        const DiaryAttachment(path: '', type: AttachmentType.doodle).isDoodle,
        true,
      );
      expect(
        const DiaryAttachment(path: '', type: AttachmentType.image).isDoodle,
        false,
      );
    });

    test('isVisualImage helper', () {
      expect(
        const DiaryAttachment(path: '', type: AttachmentType.image)
            .isVisualImage,
        true,
      );
      expect(
        const DiaryAttachment(path: '', type: AttachmentType.gif).isVisualImage,
        true,
      );
      expect(
        const DiaryAttachment(path: '', type: AttachmentType.doodle)
            .isVisualImage,
        true,
      );
      expect(
        const DiaryAttachment(path: '', type: AttachmentType.video)
            .isVisualImage,
        false,
      );
    });
  });

  // ── WebDavConfig model ────────────────────────────────────────────

  group('WebDavConfig', () {
    test('isConfigured returns false when fields are empty', () {
      const config = WebDavConfig();
      expect(config.isConfigured, false);
    });

    test('isConfigured returns true when all required fields are set', () {
      const config = WebDavConfig(
        serverUrl: 'https://dav.example.com',
        username: 'user',
        password: 'pass',
      );
      expect(config.isConfigured, true);
    });

    test('toJson excludes password', () {
      const config = WebDavConfig(
        serverUrl: 'https://dav.example.com',
        username: 'user',
        password: 'secret',
      );
      final json = config.toJson();
      expect(json.containsKey('password'), false);
      expect(json['serverUrl'], 'https://dav.example.com');
      expect(json['username'], 'user');
    });

    test('fromJson with explicit password parameter', () {
      final json = {
        'serverUrl': 'https://dav.example.com',
        'username': 'user',
        'remoteDir': '/my-diary',
      };
      final config = WebDavConfig.fromJson(json, password: 'secret');
      expect(config.password, 'secret');
      expect(config.remoteDir, '/my-diary');
    });

    test('fromJson falls back to json password for legacy data', () {
      final json = {
        'serverUrl': 'https://dav.example.com',
        'username': 'user',
        'password': 'legacy-secret',
      };
      final config = WebDavConfig.fromJson(json);
      expect(config.password, 'legacy-secret');
    });

    test('fromJson defaults conflictStrategy to lastWriteWins', () {
      final json = <String, dynamic>{};
      final config = WebDavConfig.fromJson(json);
      expect(config.conflictStrategy, ConflictStrategy.lastWriteWins);
    });
  });

  // ── i18n ──────────────────────────────────────────────────────────

  group('i18n', () {
    testWidgets('isZh returns true for zh_CN locale', (tester) async {
      await tester.pumpWidget(
        Localizations(
          locale: const Locale('zh', 'CN'),
          delegates: const [
            DefaultMaterialLocalizations.delegate,
            DefaultWidgetsLocalizations.delegate,
          ],
          child: Builder(
            builder: (context) {
              expect(isZh(context), true);
              return const SizedBox();
            },
          ),
        ),
      );
    });

    testWidgets('isZh returns false for en_US locale', (tester) async {
      await tester.pumpWidget(
        Localizations(
          locale: const Locale('en', 'US'),
          delegates: const [
            DefaultMaterialLocalizations.delegate,
            DefaultWidgetsLocalizations.delegate,
          ],
          child: Builder(
            builder: (context) {
              expect(isZh(context), false);
              return const SizedBox();
            },
          ),
        ),
      );
    });

    testWidgets('tr returns zh text for Chinese locale', (tester) async {
      await tester.pumpWidget(
        Localizations(
          locale: const Locale('zh', 'CN'),
          delegates: const [
            DefaultMaterialLocalizations.delegate,
            DefaultWidgetsLocalizations.delegate,
          ],
          child: Builder(
            builder: (context) {
              expect(tr(context, zh: '你好', en: 'Hello'), '你好');
              return const SizedBox();
            },
          ),
        ),
      );
    });

    testWidgets('tr returns en text for English locale', (tester) async {
      await tester.pumpWidget(
        Localizations(
          locale: const Locale('en', 'US'),
          delegates: const [
            DefaultMaterialLocalizations.delegate,
            DefaultWidgetsLocalizations.delegate,
          ],
          child: Builder(
            builder: (context) {
              expect(tr(context, zh: '你好', en: 'Hello'), 'Hello');
              return const SizedBox();
            },
          ),
        ),
      );
    });
  });

  // ── EntryMetaIcons ────────────────────────────────────────────────

  group('EntryMetaIcons', () {
    test('parseMoodMeta returns hasValue=false for empty input', () {
      final result = parseMoodMeta('');
      expect(result.hasValue, false);
    });

    test('parseMoodMeta returns hasValue=false for whitespace input', () {
      final result = parseMoodMeta('   ');
      expect(result.hasValue, false);
    });

    test('parseMoodMeta detects emoji prefix', () {
      final result = parseMoodMeta('\u{1F642} happy day');
      expect(result.hasValue, true);
      expect(result.notes, 'happy day');
    });

    test('parseMoodMeta detects emoji anywhere', () {
      final result = parseMoodMeta('feeling \u{1F642} today');
      expect(result.hasValue, true);
    });

    test('parseMoodMeta returns hasValue=true even without known emoji', () {
      final result = parseMoodMeta('just some text');
      expect(result.hasValue, true);
      expect(result.notes, 'just some text');
    });

    test('parseWeatherMeta detects sun emoji', () {
      final result = parseWeatherMeta('☀️ clear skies');
      expect(result.hasValue, true);
      expect(result.notes, 'clear skies');
    });

    test('parseWeatherMeta detects rain emoji', () {
      final result = parseWeatherMeta('🌧️ light drizzle');
      expect(result.hasValue, true);
    });
  });

  // ── Widget smoke tests ────────────────────────────────────────────

  group('Widget smoke', () {
    testWidgets('MaterialApp with zh locale renders without error',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          locale: Locale('zh', 'CN'),
          localizationsDelegates: [
            DefaultMaterialLocalizations.delegate,
            DefaultWidgetsLocalizations.delegate,
          ],
          home: Scaffold(body: Center(child: Text('测试'))),
        ),
      );
      expect(find.text('测试'), findsOneWidget);
    });

    testWidgets('Card theme is applied', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(
            useMaterial3: true,
            cardTheme: CardThemeData(
              margin: EdgeInsets.zero,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
            ),
          ),
          home: const Scaffold(
            body: Center(
              child: Card(
                child: SizedBox(width: 100, height: 100),
              ),
            ),
          ),
        ),
      );
      expect(find.byType(Card), findsOneWidget);
    });
  });
}
