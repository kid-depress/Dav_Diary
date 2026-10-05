import 'dart:io';

import 'package:diary/data/database/app_database.dart';
import 'package:diary/data/models/diary_entry.dart';
import 'package:diary/data/repositories/diary_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

void main() {
  group('Windows SQLite', () {
    late Directory directory;
    late String path;

    setUp(() async {
      directory = await Directory.systemTemp.createTemp('diary-database-');
      path = p.join(directory.path, 'diary.db');
    });

    tearDown(() => directory.delete(recursive: true));

    DiaryEntry entry() {
      final date = DateTime(2026, 10, 4);
      return DiaryEntry(
        id: 'windows-entry',
        title: '桌面日记',
        deltaJson: '[{"insert":"你好 Windows 🙂\\n"}]',
        plainText: '你好 Windows 🙂',
        createdAt: date,
        updatedAt: date,
        eventAt: date,
        mood: '🙂',
        weather: '☀️',
        location: '31.2304, 121.4737',
        attachments: const [
          DiaryAttachment(path: r'C:\Users\diary\media\photo.jpg'),
        ],
      );
    }

    test('persists entries and attachments across reopen', () async {
      final database = AppDatabase.forTesting(path);
      final repository = DiaryRepository(database);
      await repository.upsert(entry());
      await (await database.database).close();

      final reopened = AppDatabase.forTesting(path);
      final db = await reopened.database;
      try {
        final entries = await DiaryRepository(reopened).listActive();
        expect(entries.single.toDbMap(), entry().toDbMap());
        expect(await db.getVersion(), 2);
        final tables = await db.rawQuery(
          "SELECT name FROM sqlite_master WHERE type = 'table'",
        );
        expect(
          tables.map((row) => row['name']),
          containsAll(['entries', 'sync_entry_states', 'pending_hard_deletes']),
        );
      } finally {
        await db.close();
      }
    });

    test('supports trash, restore and permanent deletion', () async {
      final database = AppDatabase.forTesting(path);
      final db = await database.database;
      final repository = DiaryRepository(database);
      try {
        await repository.upsert(entry());
        await repository.softDelete(entry().id);
        expect(await repository.listActive(), isEmpty);
        expect((await repository.listDeleted()).single.id, entry().id);
        await repository.restore(entry().id);
        expect((await repository.listActive()).single.id, entry().id);
        await repository.deleteForever(entry().id);
        expect(await repository.listAll(), isEmpty);
      } finally {
        await db.close();
      }
    });

    test('upgrades v1 data and shares concurrent initialization', () async {
      final database = AppDatabase.forTesting(path);
      final db = await database.database;
      await DiaryRepository(database).upsert(entry());
      await db.execute('DROP TABLE sync_entry_states');
      await db.execute('DROP TABLE pending_hard_deletes');
      await db.setVersion(1);
      await db.close();

      final reopened = AppDatabase.forTesting(path);
      final connections = await Future.wait([
        reopened.database,
        reopened.database,
        reopened.database,
      ]);
      final upgraded = connections.first;
      try {
        expect(connections.every((item) => identical(item, upgraded)), isTrue);
        expect(await upgraded.getVersion(), 2);
        expect(
          (await DiaryRepository(reopened).listActive()).single.plainText,
          entry().plainText,
        );
        expect(await upgraded.query('sync_entry_states'), isEmpty);
        expect(await upgraded.query('pending_hard_deletes'), isEmpty);
      } finally {
        await upgraded.close();
      }
    });
  }, skip: !Platform.isWindows);
}
