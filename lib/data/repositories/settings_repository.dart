import 'dart:convert';

import 'package:diary/data/models/webdav_config.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
  static const _keyPendingHardDeletes = 'pending_hard_delete_ids';
  static const _keyEntrySyncStates = 'entry_sync_states';
  static const _keySyncDeviceId = 'sync_device_id';
  static const _keySyncClock = 'sync_clock';

  Future<SharedPreferences> get _prefs => SharedPreferences.getInstance();

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
    if (raw == null || raw.isEmpty) {
      return const WebDavConfig();
    }
    final map = jsonDecode(raw) as Map<String, dynamic>;
    return WebDavConfig.fromJson(map);
  }

  Future<void> saveWebDavConfig(WebDavConfig config) async {
    final prefs = await _prefs;
    await prefs.setString(_keyWebDavConfig, jsonEncode(config.toJson()));
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
    // Default for first install: grid view.
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
    final prefs = await _prefs;
    final raw = (prefs.getString(_keyPendingHardDeletes) ?? '').trim();
    if (raw.isEmpty) {
      return const [];
    }
    try {
      final parsed = jsonDecode(raw);
      if (parsed is! List<dynamic>) {
        return const [];
      }
      final seen = <String>{};
      final records = <Map<String, dynamic>>[];
      for (final item in parsed) {
        if (item is String) {
          final id = item.trim();
          if (id.isEmpty || !seen.add(id)) {
            continue;
          }
          records.add(<String, dynamic>{'id': id});
          continue;
        }
        if (item is! Map<String, dynamic>) {
          continue;
        }
        final id = (item['id'] ?? '') as String;
        final normalizedId = id.trim();
        if (normalizedId.isEmpty || !seen.add(normalizedId)) {
          continue;
        }
        records.add(<String, dynamic>{
          'id': normalizedId,
          if (item['revision'] is String) 'revision': item['revision'],
          if (item['targetRevision'] is String)
            'targetRevision': item['targetRevision'],
          if (item['deletedAt'] is String) 'deletedAt': item['deletedAt'],
        });
      }
      records.sort(
        (a, b) => ((a['id'] ?? '') as String).compareTo((b['id'] ?? '') as String),
      );
      return records;
    } catch (_) {
      return const [];
    }
  }

  Future<void> savePendingHardDeleteRecords(
    List<Map<String, dynamic>> records,
  ) async {
    final normalized = <Map<String, dynamic>>[];
    final seen = <String>{};
    for (final record in records) {
      final id = ((record['id'] ?? '') as String).trim();
      if (id.isEmpty || !seen.add(id)) {
        continue;
      }
      normalized.add(<String, dynamic>{
        'id': id,
        if (record['revision'] is String &&
            ((record['revision'] as String).trim().isNotEmpty))
          'revision': (record['revision'] as String).trim(),
        if (record['targetRevision'] is String &&
            ((record['targetRevision'] as String).trim().isNotEmpty))
          'targetRevision': (record['targetRevision'] as String).trim(),
        if (record['deletedAt'] is String &&
            ((record['deletedAt'] as String).trim().isNotEmpty))
          'deletedAt': (record['deletedAt'] as String).trim(),
      });
    }
    normalized.sort(
      (a, b) => ((a['id'] ?? '') as String).compareTo((b['id'] ?? '') as String),
    );
    final prefs = await _prefs;
    if (normalized.isEmpty) {
      await prefs.remove(_keyPendingHardDeletes);
      return;
    }
    await prefs.setString(_keyPendingHardDeletes, jsonEncode(normalized));
  }

  Future<Map<String, dynamic>> loadEntrySyncStates() async {
    final prefs = await _prefs;
    final raw = (prefs.getString(_keyEntrySyncStates) ?? '').trim();
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

  Future<void> saveEntrySyncStates(Map<String, dynamic> states) async {
    final prefs = await _prefs;
    if (states.isEmpty) {
      await prefs.remove(_keyEntrySyncStates);
      return;
    }
    await prefs.setString(_keyEntrySyncStates, jsonEncode(states));
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
}
