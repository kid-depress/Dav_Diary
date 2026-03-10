import 'dart:async';
import 'dart:io';

import 'package:diary/data/models/diary_entry.dart';
import 'package:diary/data/models/webdav_config.dart';
import 'package:diary/data/repositories/diary_repository.dart';
import 'package:diary/data/repositories/settings_repository.dart';
import 'package:diary/services/storage_service.dart';
import 'package:diary/services/sync_service.dart';
import 'package:flutter/material.dart';

class DiaryAppState extends ChangeNotifier {
  DiaryAppState({
    required DiaryRepository diaryRepository,
    required SettingsRepository settingsRepository,
    required SyncService syncService,
    required StorageService storageService,
  }) : _diaryRepository = diaryRepository,
       _settingsRepository = settingsRepository,
       _syncService = syncService,
       _storageService = storageService;

  final DiaryRepository _diaryRepository;
  final SettingsRepository _settingsRepository;
  final SyncService _syncService;
  final StorageService _storageService;

  bool _loading = true;
  bool _syncing = false;
  ThemeMode _themeMode = ThemeMode.system;
  Locale _locale = const Locale('zh', 'CN');
  DateTime? _lastSyncAt;
  WebDavConfig _webDavConfig = const WebDavConfig();
  List<DiaryEntry> _entries = const [];

  bool get loading => _loading;
  bool get syncing => _syncing;
  ThemeMode get themeMode => _themeMode;
  Locale get locale => _locale;
  DateTime? get lastSyncAt => _lastSyncAt;
  WebDavConfig get webDavConfig => _webDavConfig;
  List<DiaryEntry> get entries => _entries;

  Future<void> initialize() async {
    _themeMode = await _settingsRepository.loadThemeMode();
    _locale = await _settingsRepository.loadLocale();
    _webDavConfig = await _settingsRepository.loadWebDavConfig();
    _lastSyncAt = await _settingsRepository.loadLastSyncAt();
    await refreshEntries();

    if (_webDavConfig.isConfigured) {
      _syncing = true;
      notifyListeners();
      await _syncService.syncNow();
      _lastSyncAt = await _settingsRepository.loadLastSyncAt();
      _syncing = false;
      await refreshEntries();
    }

    await _storageService.cleanupOrphanedMedia(_entries);
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
    _triggerAutoSyncAfterLocalChange();
  }

  Future<void> deleteEntry(String id) async {
    await _diaryRepository.softDelete(id);
    await refreshEntries();
    _triggerAutoSyncAfterLocalChange();
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    _themeMode = mode;
    await _settingsRepository.saveThemeMode(mode);
    notifyListeners();
  }

  Future<void> setLocale(Locale locale) async {
    _locale = locale;
    await _settingsRepository.saveLocale(locale);
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
    await _storageService.cleanupOrphanedMedia(_entries);
    return result;
  }

  void _triggerAutoSyncAfterLocalChange() {
    if (!_webDavConfig.isConfigured || _syncing) {
      return;
    }
    unawaited(syncNow());
  }

  Future<DiaryAttachment?> restoreAttachmentForEntry(
    String entryId,
    DiaryAttachment attachment,
  ) async {
    final restored = await _syncService.restoreAttachment(attachment);
    if (restored == null) {
      return null;
    }
    final current = await _diaryRepository.getById(entryId);
    if (current == null) {
      return restored;
    }

    var changed = false;
    final nextAttachments = current.attachments.map((item) {
      final sameHash = item.hash.isNotEmpty && item.hash == attachment.hash;
      final sameRemote =
          item.remotePath.isNotEmpty &&
          item.remotePath == attachment.remotePath;
      final samePath = item.path.isNotEmpty && item.path == attachment.path;
      if (sameHash || sameRemote || samePath) {
        changed = true;
        return restored;
      }
      return item;
    }).toList();

    if (changed) {
      await _diaryRepository.upsert(
        current.copyWith(attachments: nextAttachments),
      );
      await refreshEntries();
    }
    return restored;
  }

  Future<int> clearSyncedAttachmentCache() async {
    final removed = await _storageService.cleanupSyncedAttachmentCache(
      _entries,
    );
    var touched = 0;
    for (final entry in _entries) {
      var changed = false;
      final updatedAttachments = <DiaryAttachment>[];
      for (final attachment in entry.attachments) {
        if (attachment.remotePath.trim().isNotEmpty &&
            attachment.path.trim().isNotEmpty) {
          final stillExists = await File(attachment.path).exists();
          if (!stillExists) {
            changed = true;
            updatedAttachments.add(attachment.copyWith(path: ''));
            continue;
          }
        }
        updatedAttachments.add(attachment);
      }
      if (!changed) {
        continue;
      }
      touched++;
      await _diaryRepository.upsert(
        entry.copyWith(attachments: updatedAttachments),
      );
    }
    if (touched > 0) {
      await refreshEntries();
    }
    return removed;
  }
}
