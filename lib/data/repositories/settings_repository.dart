import 'dart:convert';

import 'package:diary/data/credential_store.dart';
import 'package:diary/data/database/app_database.dart';
import 'package:diary/data/models/webdav_config.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

class DailyQuoteCache {
  const DailyQuoteCache({required this.text, required this.dayStartEpochMs});

  final String text;
  final int dayStartEpochMs;
}

class SettingsRepository {
  static const _keyThemeMode = 'theme_mode';
  static const _keyThemeSeedColor = 'theme_seed_color';
  static const _keyLocale = 'locale';
  static const _keyWebDavConfig = 'webdav_config';
  static const _keyLastSyncAt = 'last_sync_at';
  static const _keyHomeLayoutMode = 'home_layout_mode';
  static const _keyEnableDailyQuote = 'enable_daily_quote';
  static const _keyDailyQuoteText = 'daily_quote_text';
  static const _keyDailyQuoteDay = 'daily_quote_day';
  static const _keyEntrySyncStates = 'entry_sync_states';
  static const _keySyncDeviceId = 'sync_device_id';
  static const _keySyncClock = 'sync_clock';
  static const _keyRemoteAttachmentCleanupAt = 'remote_attachment_cleanup_at';

  Future<SharedPreferences> get _prefs => SharedPreferences.getInstance();
  Future<Database> get _db => AppDatabase.instance.database;

  Future<ThemeMode> loadThemeMode() async {
    final prefs = await _prefs;
    final value = prefs.getString(_keyThemeMode);
    switch (value) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      default:
        return ThemeMode.system;
    }
  }

  Future<void> saveThemeMode(ThemeMode mode) async {
    final prefs = await _prefs;
    await prefs.setString(_keyThemeMode, mode.name);
  }

  Future<Color> loadThemeSeedColor() async {
    const fallback = Color(0xFF7A8DA1);
    final prefs = await _prefs;
    final value = prefs.getInt(_keyThemeSeedColor);
    if (value == null) {
      return fallback;
    }
    return Color(value);
  }

  Future<void> saveThemeSeedColor(Color color) async {
    final prefs = await _prefs;
    await prefs.setInt(_keyThemeSeedColor, color.toARGB32());
  }

  Future<Locale> loadLocale() async {
    final prefs = await _prefs;
    final value = prefs.getString(_keyLocale) ?? 'zh_CN';
    switch (value) {
      case 'en_US':
        return const Locale('en', 'US');
      default:
        return const Locale('zh', 'CN');
    }
  }

  Future<void> saveLocale(Locale locale) async {
    final prefs = await _prefs;
    final languageCode = locale.languageCode.toLowerCase();
    if (languageCode == 'en') {
      await prefs.setString(_keyLocale, 'en_US');
      return;
    }
    await prefs.setString(_keyLocale, 'zh_CN');
  }

  Future<WebDavConfig> loadWebDavConfig() async {
    final prefs = await _prefs;
    final raw = prefs.getString(_keyWebDavConfig);
    final password = await CredentialStore.loadPassword();
    if (raw == null || raw.isEmpty) {
      return WebDavConfig(password: password);
    }
    final map = jsonDecode(raw) as Map<String, dynamic>;
    return WebDavConfig.fromJson(map, password: password);
  }

  Future<void> saveWebDavConfig(WebDavConfig config) async {
    final prefs = await _prefs;
    final safeJson = jsonEncode(config.toJson());
    await prefs.setString(_keyWebDavConfig, safeJson);
    await CredentialStore.savePassword(config.password);
  }

  Future<DateTime?> loadLastSyncAt() async {
    final prefs = await _prefs;
    final value = prefs.getInt(_keyLastSyncAt);
    if (value == null) {
      return null;
    }
    return DateTime.fromMillisecondsSinceEpoch(value);
  }

  Future<void> saveLastSyncAt(DateTime time) async {
    final prefs = await _prefs;
    await prefs.setInt(_keyLastSyncAt, time.millisecondsSinceEpoch);
  }

  Future<String> loadHomeLayoutMode() async {
    final prefs = await _prefs;
    final value = (prefs.getString(_keyHomeLayoutMode) ?? '').trim();
    if (value == 'grid' || value == 'masonry') {
      return value;
    }
    if (value == 'timeline') {
      return 'masonry';
    }
    return 'grid';
  }

  Future<void> saveHomeLayoutMode(String mode) async {
    final normalized = mode == 'masonry' ? 'masonry' : 'grid';
    final prefs = await _prefs;
    await prefs.setString(_keyHomeLayoutMode, normalized);
  }

  Future<bool> loadEnableDailyQuote() async {
    final prefs = await _prefs;
    return prefs.getBool(_keyEnableDailyQuote) ?? true;
  }

  Future<void> saveEnableDailyQuote(bool enabled) async {
    final prefs = await _prefs;
    await prefs.setBool(_keyEnableDailyQuote, enabled);
  }

  Future<DailyQuoteCache?> loadDailyQuoteCache() async {
    final prefs = await _prefs;
    final text = (prefs.getString(_keyDailyQuoteText) ?? '').trim();
    final day = prefs.getInt(_keyDailyQuoteDay);
    if (text.isEmpty || day == null) {
      return null;
    }
    return DailyQuoteCache(text: text, dayStartEpochMs: day);
  }

  Future<void> saveDailyQuoteCache({
    required String text,
    required int dayStartEpochMs,
  }) async {
    final prefs = await _prefs;
    await prefs.setString(_keyDailyQuoteText, text.trim());
    await prefs.setInt(_keyDailyQuoteDay, dayStartEpochMs);
  }

  Future<List<Map<String, dynamic>>> loadPendingHardDeleteRecords() async {
    final db = await _db;
    final rows = await db.query('pending_hard_deletes', orderBy: 'id ASC');
    if (rows.isEmpty) {
      final prefs = await _prefs;
      final raw = (prefs.getString('pending_hard_delete_ids') ?? '').trim();
      if (raw.isNotEmpty) {
        try {
          final parsed = jsonDecode(raw);
          if (parsed is List<dynamic>) {
            final records = <Map<String, dynamic>>[];
            for (final item in parsed) {
              if (item is String) {
                final id = item.trim();
                if (id.isNotEmpty) {
                  records.add(<String, dynamic>{'id': id});
                }
                continue;
              }
              if (item is Map<String, dynamic>) {
                records.add(item);
              }
            }
            if (records.isNotEmpty) {
              await savePendingHardDeleteRecords(records);
              return records;
            }
          }
        } catch (_) {}
      }
    }
    return rows
        .map(
          (row) => <String, dynamic>{
            'id': (row['id'] ?? '') as String,
            if (((row['revision'] ?? '') as String).trim().isNotEmpty)
              'revision': row['revision'],
            if (((row['target_revision'] ?? '') as String).trim().isNotEmpty)
              'targetRevision': row['target_revision'],
            if ((row['deleted_at'] ?? 0) is int)
              'deletedAt': DateTime.fromMillisecondsSinceEpoch(
                row['deleted_at'] as int,
              ).toIso8601String(),
          },
        )
        .toList();
  }

  Future<void> savePendingHardDeleteRecords(
    List<Map<String, dynamic>> records,
  ) async {
    final db = await _db;
    await db.transaction((txn) async {
      await txn.delete('pending_hard_deletes');
      for (final record in records) {
        final id = ((record['id'] ?? '') as String).trim();
        if (id.isEmpty) {
          continue;
        }
        final revision = ((record['revision'] ?? '') as String).trim();
        final targetRevision = ((record['targetRevision'] ?? '') as String)
            .trim();
        final deletedAtRaw = record['deletedAt'];
        final deletedAt = deletedAtRaw is String
            ? DateTime.tryParse(deletedAtRaw) ?? DateTime.now()
            : DateTime.now();
        await txn.insert('pending_hard_deletes', <String, Object?>{
          'id': id,
          'revision': revision,
          'deleted_at': deletedAt.millisecondsSinceEpoch,
          'target_revision': targetRevision,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
    });
    final prefs = await _prefs;
    await prefs.remove('pending_hard_delete_ids');
  }

  Future<Map<String, dynamic>> loadEntrySyncStates() async {
    final db = await _db;
    final rows = await db.query('sync_entry_states');
    if (rows.isEmpty) {
      final prefs = await _prefs;
      final raw = (prefs.getString(_keyEntrySyncStates) ?? '').trim();
      if (raw.isNotEmpty) {
        try {
          final parsed = jsonDecode(raw);
          if (parsed is Map<String, dynamic>) {
            await saveEntrySyncStates(parsed);
            return parsed;
          }
        } catch (_) {}
      }
    }
    final result = <String, dynamic>{};
    for (final row in rows) {
      final id = (row['id'] ?? '') as String;
      if (id.isEmpty) {
        continue;
      }
      result[id] = <String, dynamic>{
        'lastSyncedRevision': (row['last_synced_revision'] ?? '') as String,
        'contentFingerprint': (row['content_fingerprint'] ?? '') as String,
        if (row['last_remote_updated_at'] != null)
          'lastRemoteUpdatedAt': DateTime.fromMillisecondsSinceEpoch(
            row['last_remote_updated_at'] as int,
          ).toIso8601String(),
        if (row['last_remote_deleted_at'] != null)
          'lastRemoteDeletedAt': DateTime.fromMillisecondsSinceEpoch(
            row['last_remote_deleted_at'] as int,
          ).toIso8601String(),
      };
    }
    return result;
  }

  Future<void> saveEntrySyncStates(Map<String, dynamic> states) async {
    final db = await _db;
    await db.transaction((txn) async {
      await txn.delete('sync_entry_states');
      for (final entry in states.entries) {
        final id = entry.key.trim();
        if (id.isEmpty || entry.value is! Map<String, dynamic>) {
          continue;
        }
        final map = entry.value as Map<String, dynamic>;
        await txn.insert('sync_entry_states', <String, Object?>{
          'id': id,
          'last_synced_revision': (map['lastSyncedRevision'] ?? '') as String,
          'content_fingerprint': (map['contentFingerprint'] ?? '') as String,
          'last_remote_updated_at': _parseTimeMs(map['lastRemoteUpdatedAt']),
          'last_remote_deleted_at': _parseTimeMs(map['lastRemoteDeletedAt']),
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
    });
  }

  Future<String> loadSyncDeviceId() async {
    final prefs = await _prefs;
    return (prefs.getString(_keySyncDeviceId) ?? '').trim();
  }

  Future<void> saveSyncDeviceId(String id) async {
    final prefs = await _prefs;
    final normalized = id.trim();
    if (normalized.isEmpty) {
      await prefs.remove(_keySyncDeviceId);
      return;
    }
    await prefs.setString(_keySyncDeviceId, normalized);
  }

  Future<Map<String, dynamic>> loadSyncClock() async {
    final prefs = await _prefs;
    final raw = (prefs.getString(_keySyncClock) ?? '').trim();
    if (raw.isEmpty) {
      return const <String, dynamic>{};
    }
    try {
      final parsed = jsonDecode(raw);
      if (parsed is! Map<String, dynamic>) {
        return const <String, dynamic>{};
      }
      return parsed;
    } catch (_) {
      return const <String, dynamic>{};
    }
  }

  Future<void> saveSyncClock({
    required int wallTimeMs,
    required int counter,
  }) async {
    final prefs = await _prefs;
    await prefs.setString(
      _keySyncClock,
      jsonEncode(<String, dynamic>{
        'wallTimeMs': wallTimeMs,
        'counter': counter,
      }),
    );
  }

  Future<DateTime?> loadRemoteAttachmentCleanupAt() async {
    final prefs = await _prefs;
    final value = prefs.getInt(_keyRemoteAttachmentCleanupAt);
    if (value == null) {
      return null;
    }
    return DateTime.fromMillisecondsSinceEpoch(value);
  }

  Future<void> saveRemoteAttachmentCleanupAt(DateTime time) async {
    final prefs = await _prefs;
    await prefs.setInt(
      _keyRemoteAttachmentCleanupAt,
      time.millisecondsSinceEpoch,
    );
  }

  int? _parseTimeMs(Object? value) {
    if (value == null) {
      return null;
    }
    if (value is int) {
      return value;
    }
    if (value is String) {
      return DateTime.tryParse(value)?.millisecondsSinceEpoch;
    }
    return null;
  }
}
