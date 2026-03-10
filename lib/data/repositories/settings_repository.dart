import 'dart:convert';

import 'package:diary/data/models/webdav_config.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SettingsRepository {
  static const _keyThemeMode = 'theme_mode';
  static const _keyLocale = 'locale';
  static const _keyWebDavConfig = 'webdav_config';
  static const _keyLastSyncAt = 'last_sync_at';
  static const _keyHomeLayoutMode = 'home_layout_mode';

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
    if (value == 'timeline' || value == 'grid') {
      return value;
    }
    // Default for first install: grid view.
    return 'grid';
  }

  Future<void> saveHomeLayoutMode(String mode) async {
    final normalized = mode == 'timeline' ? 'timeline' : 'grid';
    final prefs = await _prefs;
    await prefs.setString(_keyHomeLayoutMode, normalized);
  }
}
