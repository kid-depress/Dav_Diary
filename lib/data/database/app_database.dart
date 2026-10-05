import 'dart:io';

import 'package:diary/services/app_paths.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart' as sqflite;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class AppDatabase {
  AppDatabase._() : _databasePath = null;

  @visibleForTesting
  AppDatabase.forTesting(String path) : _databasePath = path;

  static final AppDatabase instance = AppDatabase._();

  final String? _databasePath;

  Database? _database;
  Future<Database>? _openFuture;

  Future<Database> get database async {
    final existing = _database;
    if (existing != null) {
      return existing;
    }
    final pending = _openFuture;
    if (pending != null) {
      return pending;
    }
    _openFuture = _open()
        .then((db) {
          _database = db;
          return db;
        })
        .whenComplete(() {
          _openFuture = null;
        });
    return _openFuture!;
  }

  Future<Database> _open() async {
    final path =
        _databasePath ??
        p.join((await getDiaryDataDirectory()).path, 'diary.db');
    final factory = Platform.isWindows
        ? databaseFactoryFfi
        : sqflite.databaseFactory;
    if (Platform.isWindows) {
      sqfliteFfiInit();
    }
    return factory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 2,
        onCreate: (db, version) async {
          await db.execute('''
CREATE TABLE entries (
  id TEXT PRIMARY KEY,
  title TEXT NOT NULL,
  delta_json TEXT NOT NULL,
  plain_text TEXT NOT NULL,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL,
  event_at INTEGER NOT NULL,
  mood TEXT NOT NULL,
  weather TEXT NOT NULL,
  location TEXT NOT NULL,
  attachments_json TEXT NOT NULL,
  is_deleted INTEGER NOT NULL DEFAULT 0
)
''');
          await db.execute(
            'CREATE INDEX idx_entries_event_at ON entries(event_at)',
          );
          await db.execute(
            'CREATE INDEX idx_entries_updated_at ON entries(updated_at)',
          );
          await db.execute(
            'CREATE INDEX idx_entries_is_deleted ON entries(is_deleted)',
          );
          await db.execute('''
CREATE TABLE sync_entry_states (
  id TEXT PRIMARY KEY,
  last_synced_revision TEXT NOT NULL DEFAULT '',
  content_fingerprint TEXT NOT NULL DEFAULT '',
  last_remote_updated_at INTEGER,
  last_remote_deleted_at INTEGER
)
''');
          await db.execute('''
CREATE TABLE pending_hard_deletes (
  id TEXT PRIMARY KEY,
  revision TEXT NOT NULL DEFAULT '',
  deleted_at INTEGER NOT NULL,
  target_revision TEXT NOT NULL DEFAULT ''
)
''');
        },
        onUpgrade: (db, oldVersion, newVersion) async {
          if (oldVersion < 2) {
            await db.execute('''
CREATE TABLE IF NOT EXISTS sync_entry_states (
  id TEXT PRIMARY KEY,
  last_synced_revision TEXT NOT NULL DEFAULT '',
  content_fingerprint TEXT NOT NULL DEFAULT '',
  last_remote_updated_at INTEGER,
  last_remote_deleted_at INTEGER
)
''');
            await db.execute('''
CREATE TABLE IF NOT EXISTS pending_hard_deletes (
  id TEXT PRIMARY KEY,
  revision TEXT NOT NULL DEFAULT '',
  deleted_at INTEGER NOT NULL,
  target_revision TEXT NOT NULL DEFAULT ''
)
''');
          }
        },
      ),
    );
  }
}
