import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:diary/data/models/diary_entry.dart';
import 'package:diary/data/models/webdav_config.dart';
import 'package:diary/data/repositories/diary_repository.dart';
import 'package:diary/data/repositories/settings_repository.dart';
import 'package:uuid/uuid.dart';
import 'package:webdav_client/webdav_client.dart' as webdav;

class SyncResult {
  const SyncResult({
    required this.success,
    required this.message,
    this.uploaded = 0,
    this.downloaded = 0,
    this.conflicts = 0,
  });

  final bool success;
  final String message;
  final int uploaded;
  final int downloaded;
  final int conflicts;
}

class SyncService {
  SyncService(this._diaryRepository, this._settingsRepository);

  final DiaryRepository _diaryRepository;
  final SettingsRepository _settingsRepository;

  webdav.Client _buildClient(WebDavConfig config) {
    final client = webdav.newClient(
      config.serverUrl.trim(),
      user: config.username.trim(),
      password: config.password.trim(),
      debug: false,
    );
    client.setConnectTimeout(10000);
    client.setSendTimeout(10000);
    client.setReceiveTimeout(10000);
    client.setHeaders({'accept-charset': 'utf-8'});
    return client;
  }

  String _normalizeDir(String dir) {
    final withPrefix = dir.startsWith('/') ? dir : '/$dir';
    if (withPrefix.endsWith('/')) {
      return withPrefix.substring(0, withPrefix.length - 1);
    }
    return withPrefix;
  }

  Future<void> _uploadEntry(
    webdav.Client client,
    String remotePath,
    DiaryEntry entry,
  ) async {
    final jsonStr = jsonEncode(entry.toSyncJson());
    final compressed = gzip.encode(utf8.encode(jsonStr));
    await client.write(remotePath, Uint8List.fromList(compressed));
  }

  Future<bool> testConnection() async {
    final config = await _settingsRepository.loadWebDavConfig();
    if (!config.isConfigured) {
      return false;
    }
    final client = _buildClient(config);
    await client.ping();
    await client.mkdirAll(_normalizeDir(config.remoteDir));
    return true;
  }

  Future<SyncResult> syncNow() async {
    final config = await _settingsRepository.loadWebDavConfig();
    if (!config.isConfigured) {
      return const SyncResult(success: false, message: '请先完成 WebDAV 配置');
    }

    final client = _buildClient(config);
    final remoteRoot = _normalizeDir(config.remoteDir);
    final entryDir = '$remoteRoot/entries';
    final now = DateTime.now();
    final lastSync =
        await _settingsRepository.loadLastSyncAt() ??
        DateTime.fromMillisecondsSinceEpoch(0);

    int uploaded = 0;
    int downloaded = 0;
    int conflicts = 0;

    try {
      await client.ping();
      await client.mkdirAll(entryDir);

      final changedEntries = await _diaryRepository.listUpdatedAfter(lastSync);
      for (final entry in changedEntries) {
        await _uploadEntry(client, '$entryDir/${entry.id}.json.gz', entry);
        uploaded++;
      }

      final remoteFiles = await client.readDir(entryDir);
      for (final file in remoteFiles) {
        if (file.isDir == true) {
          continue;
        }
        final name = file.name ?? '';
        final path = file.path;
        if (!name.endsWith('.json.gz') || path == null) {
          continue;
        }

        final bytes = await client.read(path);
        final decoded = utf8.decode(gzip.decode(bytes));
        final map = jsonDecode(decoded) as Map<String, dynamic>;
        final remoteEntry = DiaryEntry.fromSyncJson(map);
        final local = await _diaryRepository.getById(remoteEntry.id);
        if (local == null) {
          await _diaryRepository.upsert(remoteEntry);
          downloaded++;
          continue;
        }

        if (local.updatedAt.isAtSameMomentAs(remoteEntry.updatedAt)) {
          continue;
        }

        final localDirty = local.updatedAt.isAfter(lastSync);
        final remoteDirty = remoteEntry.updatedAt.isAfter(lastSync);

        if (remoteEntry.updatedAt.isAfter(local.updatedAt)) {
          if (localDirty &&
              remoteDirty &&
              config.conflictStrategy == ConflictStrategy.keepBoth) {
            await _diaryRepository.upsert(
              local.copyWith(
                id: const Uuid().v4(),
                title: '${local.title} (冲突副本)',
                updatedAt: now,
              ),
            );
            conflicts++;
          }
          await _diaryRepository.upsert(remoteEntry);
          downloaded++;
        } else {
          if (localDirty &&
              remoteDirty &&
              config.conflictStrategy == ConflictStrategy.keepBoth) {
            await _diaryRepository.upsert(
              remoteEntry.copyWith(
                id: const Uuid().v4(),
                title: '${remoteEntry.title} (远端副本)',
                updatedAt: now,
              ),
            );
            conflicts++;
          }
        }
      }

      await _settingsRepository.saveLastSyncAt(now);
      return SyncResult(
        success: true,
        message: '同步完成',
        uploaded: uploaded,
        downloaded: downloaded,
        conflicts: conflicts,
      );
    } catch (e) {
      return SyncResult(
        success: false,
        message: '同步失败: $e',
        uploaded: uploaded,
        downloaded: downloaded,
        conflicts: conflicts,
      );
    }
  }
}
