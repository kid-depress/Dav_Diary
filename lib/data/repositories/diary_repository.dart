import 'package:diary/data/database/app_database.dart';
import 'package:diary/data/models/diary_entry.dart';
import 'package:sqflite/sqflite.dart';

class DiaryRepository {
  DiaryRepository(this._database);

  final AppDatabase _database;

  Future<Database> get _db => _database.database;

  Future<List<DiaryEntry>> listActive() async {
    final db = await _db;
    final rows = await db.query(
      'entries',
      where: 'is_deleted = 0',
      orderBy: 'event_at DESC, updated_at DESC',
    );
    return rows.map(DiaryEntry.fromDbMap).toList();
  }

  Future<List<DiaryEntry>> listByDate(DateTime day) async {
    final db = await _db;
    final start = DateTime(day.year, day.month, day.day);
    final end = start.add(const Duration(days: 1));
    final rows = await db.query(
      'entries',
      where: 'event_at >= ? AND event_at < ? AND is_deleted = 0',
      whereArgs: [start.millisecondsSinceEpoch, end.millisecondsSinceEpoch],
      orderBy: 'event_at DESC, updated_at DESC',
    );
    return rows.map(DiaryEntry.fromDbMap).toList();
  }

  Future<Set<DateTime>> daysWithEntriesInMonth(DateTime month) async {
    final db = await _db;
    final start = DateTime(month.year, month.month, 1);
    final end = DateTime(month.year, month.month + 1, 1);
    final rows = await db.query(
      'entries',
      columns: ['event_at'],
      where: 'event_at >= ? AND event_at < ? AND is_deleted = 0',
      whereArgs: [start.millisecondsSinceEpoch, end.millisecondsSinceEpoch],
    );
    return rows
        .map(
          (row) => DateTime.fromMillisecondsSinceEpoch(
            (row['event_at'] ?? 0) as int,
          ),
        )
        .map((dt) => DateTime(dt.year, dt.month, dt.day))
        .toSet();
  }

  Future<List<DiaryEntry>> listUpdatedAfter(DateTime time) async {
    final db = await _db;
    final rows = await db.query(
      'entries',
      where: 'updated_at > ?',
      whereArgs: [time.millisecondsSinceEpoch],
      orderBy: 'updated_at DESC',
    );
    return rows.map(DiaryEntry.fromDbMap).toList();
  }

  Future<Map<String, DateTime>> listSyncHeads() async {
    final db = await _db;
    final rows = await db.query('entries', columns: ['id', 'updated_at']);
    final result = <String, DateTime>{};
    for (final row in rows) {
      final id = (row['id'] ?? '') as String;
      if (id.isEmpty) {
        continue;
      }
      final updatedAtEpoch = (row['updated_at'] ?? 0) as int;
      result[id] = DateTime.fromMillisecondsSinceEpoch(updatedAtEpoch);
    }
    return result;
  }

  Future<DiaryEntry?> getById(String id) async {
    final db = await _db;
    final rows = await db.query(
      'entries',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }
    return DiaryEntry.fromDbMap(rows.first);
  }

  Future<void> upsert(DiaryEntry entry) async {
    final db = await _db;
    await db.insert(
      'entries',
      entry.toDbMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> softDelete(String id) async {
    final db = await _db;
    await db.update(
      'entries',
      <String, Object>{
        'is_deleted': 1,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<List<DiaryEntry>> listDeleted() async {
    final db = await _db;
    final rows = await db.query(
      'entries',
      where: 'is_deleted = 1',
      orderBy: 'updated_at DESC, event_at DESC',
    );
    return rows.map(DiaryEntry.fromDbMap).toList();
  }

  Future<void> restore(String id) async {
    final db = await _db;
    await db.update(
      'entries',
      <String, Object>{
        'is_deleted': 0,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> deleteForever(String id) async {
    final db = await _db;
    await db.delete('entries', where: 'id = ?', whereArgs: [id]);
  }

  Future<int> clearDeleted() async {
    final db = await _db;
    return db.delete('entries', where: 'is_deleted = 1');
  }
}
