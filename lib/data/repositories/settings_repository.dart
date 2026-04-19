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
  static const _keyPendingHardDeleteIds = 'pending_hard_delete_ids';

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

  Future<List<String>> loadPendingHardDeleteIds() async {
    final prefs = await _prefs;
    final raw = (prefs.getString(_keyPendingHardDeleteIds) ?? '').trim();
    if (raw.isEmpty) {
      return const [];
    }
    try {
      final parsed = jsonDecode(raw);
      if (parsed is! List<dynamic>) {
        return const [];
      }
      return parsed
          .whereType<String>()
          .map((id) => id.trim())
          .where((id) => id.isNotEmpty)
          .toSet()
          .toList()
        ..sort();
    } catch (_) {
      return const [];
    }
  }

  Future<void> savePendingHardDeleteIds(List<String> ids) async {
    final normalized =
        ids.map((id) => id.trim()).where((id) => id.isNotEmpty).toSet().toList()
          ..sort();
    final prefs = await _prefs;
    if (normalized.isEmpty) {
      await prefs.remove(_keyPendingHardDeleteIds);
      return;
    }
    await prefs.setString(_keyPendingHardDeleteIds, jsonEncode(normalized));
  }
}
