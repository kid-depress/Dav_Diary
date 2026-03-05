import 'dart:convert';

import 'package:diary/data/models/webdav_config.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SettingsRepository {
  static const _keyThemeMode = 'theme_mode';
  static const _keyWebDavConfig = 'webdav_config';
  static const _keyLastSyncAt = 'last_sync_at';

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
}
