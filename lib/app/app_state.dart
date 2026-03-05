import 'package:diary/data/models/diary_entry.dart';
import 'package:diary/data/models/webdav_config.dart';
import 'package:diary/data/repositories/diary_repository.dart';
import 'package:diary/data/repositories/settings_repository.dart';
import 'package:diary/services/sync_service.dart';
import 'package:flutter/material.dart';

class DiaryAppState extends ChangeNotifier {
  DiaryAppState({
    required DiaryRepository diaryRepository,
    required SettingsRepository settingsRepository,
    required SyncService syncService,
  }) : _diaryRepository = diaryRepository,
       _settingsRepository = settingsRepository,
       _syncService = syncService;

  final DiaryRepository _diaryRepository;
  final SettingsRepository _settingsRepository;
  final SyncService _syncService;

  bool _loading = true;
  bool _syncing = false;
  ThemeMode _themeMode = ThemeMode.system;
  DateTime? _lastSyncAt;
  WebDavConfig _webDavConfig = const WebDavConfig();
  List<DiaryEntry> _entries = const [];

  bool get loading => _loading;
  bool get syncing => _syncing;
  ThemeMode get themeMode => _themeMode;
  DateTime? get lastSyncAt => _lastSyncAt;
  WebDavConfig get webDavConfig => _webDavConfig;
  List<DiaryEntry> get entries => _entries;

  Future<void> initialize() async {
    _themeMode = await _settingsRepository.loadThemeMode();
    _webDavConfig = await _settingsRepository.loadWebDavConfig();
    _lastSyncAt = await _settingsRepository.loadLastSyncAt();
    await refreshEntries();
    _loading = false;
    notifyListeners();
  }

  Future<void> refreshEntries() async {
    _entries = await _diaryRepository.listActive();
    notifyListeners();
  }

  List<DiaryEntry> entriesOfDay(DateTime day) {
    return _entries.where((entry) {
      return entry.eventAt.year == day.year &&
          entry.eventAt.month == day.month &&
          entry.eventAt.day == day.day;
    }).toList();
  }

  Set<DateTime> get markedDays {
    return _entries
        .map(
          (entry) => DateTime(
            entry.eventAt.year,
            entry.eventAt.month,
            entry.eventAt.day,
          ),
        )
        .toSet();
  }

  Future<void> saveEntry(DiaryEntry entry) async {
    await _diaryRepository.upsert(entry);
    await refreshEntries();
  }

  Future<void> deleteEntry(String id) async {
    await _diaryRepository.softDelete(id);
    await refreshEntries();
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    _themeMode = mode;
    await _settingsRepository.saveThemeMode(mode);
    notifyListeners();
  }

  Future<void> updateWebDavConfig(WebDavConfig config) async {
    _webDavConfig = config;
    await _settingsRepository.saveWebDavConfig(config);
    notifyListeners();
  }

  Future<bool> testWebDavConnection() {
    return _syncService.testConnection();
  }

  Future<SyncResult> syncNow() async {
    _syncing = true;
    notifyListeners();
    final result = await _syncService.syncNow();
    _lastSyncAt = await _settingsRepository.loadLastSyncAt();
    _syncing = false;
    await refreshEntries();
    return result;
  }
}
