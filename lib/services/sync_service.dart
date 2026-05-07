import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:diary/data/models/diary_entry.dart';
import 'package:diary/data/models/webdav_config.dart';
import 'package:diary/data/repositories/diary_repository.dart';
import 'package:diary/data/repositories/settings_repository.dart';
import 'package:diary/services/storage_service.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
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

class _ManifestItem {
  const _ManifestItem({
    required this.id,
    required this.path,
    required this.updatedAt,
    required this.isDeleted,
  });

  final String id;
  final String path;
  final DateTime updatedAt;
  final bool isDeleted;

  Map<String, dynamic> toJson() => {
    'id': id,
    'path': path,
    'updatedAt': updatedAt.toIso8601String(),
    'isDeleted': isDeleted,
  };

  static _ManifestItem fromJson(Map<String, dynamic> json) {
    return _ManifestItem(
      id: (json['id'] ?? '') as String,
      path: (json['path'] ?? '') as String,
      updatedAt:
          DateTime.tryParse((json['updatedAt'] ?? '') as String) ??
          DateTime.fromMillisecondsSinceEpoch(0),
      isDeleted: (json['isDeleted'] ?? false) as bool,
    );
  }
}

class SyncService {
  SyncService(this._diaryRepository, this._settingsRepository);

  final DiaryRepository _diaryRepository;
  final SettingsRepository _settingsRepository;
  final StorageService _storageService = const StorageService();

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

  String _entryDir(String root) => '$root/entries';
  String _attachmentDir(String root) => '$root/attachments';
  String _manifestPath(String root) => '$root/manifest.json';

  Future<void> markEntryHardDeleted(String id) async {
    await markEntriesHardDeleted([id]);
  }

  Future<void> markEntriesHardDeleted(List<String> ids) async {
    final existing = await _settingsRepository.loadPendingHardDeleteIds();
    final merged = {...existing};
    for (final id in ids) {
      final normalized = id.trim();
      if (normalized.isNotEmpty) {
        merged.add(normalized);
      }
    }
    await _settingsRepository.savePendingHardDeleteIds(merged.toList());
  }

  Future<bool> _needsAttachmentHydration(DiaryEntry? localEntry) async {
    if (localEntry == null) {
      return false;
    }
    for (final attachment in localEntry.attachments) {
      final hasRemoteMain = attachment.remotePath.trim().isNotEmpty;
      final hasRemoteThumb = attachment.thumbnailRemotePath.trim().isNotEmpty;
      if (!hasRemoteMain && !hasRemoteThumb) {
        continue;
      }

      final localPath = attachment.path.trim();
      final mainMissing = localPath.isEmpty || !await File(localPath).exists();
      if (mainMissing && hasRemoteMain) {
        return true;
      }

      if (!attachment.isVisualImage) {
        continue;
      }
      final thumbPath = attachment.thumbnailPath.trim();
      final thumbMissing = thumbPath.isEmpty || !await File(thumbPath).exists();
      if (thumbMissing && hasRemoteThumb) {
        return true;
      }
    }
    return false;
  }

  Future<Map<String, _ManifestItem>> _loadManifest(
    webdav.Client client,
    String remoteRoot,
  ) async {
    final bytes = await client.read(_manifestPath(remoteRoot));
    final decoded = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
    final list = (decoded['entries'] ?? <dynamic>[]) as List<dynamic>;
    final result = <String, _ManifestItem>{};
    for (final item in list.whereType<Map<String, dynamic>>()) {
      final parsed = _ManifestItem.fromJson(item);
      if (parsed.id.isNotEmpty && parsed.path.isNotEmpty) {
        result[parsed.id] = parsed;
      }
    }
    return result;
  }

  /// Returns null when the manifest cannot be read (network error, not found, etc.).
  Future<Map<String, _ManifestItem>?> _tryLoadManifest(
    webdav.Client client,
    String remoteRoot,
  ) async {
    try {
      return await _loadManifest(client, remoteRoot);
    } catch (_) {
      return null;
    }
  }

  /// Lists .json.gz entry files in the remote entries directory.
  Future<List<webdav.File>> _listRemoteEntryFiles(
    webdav.Client client,
    String remoteRoot,
  ) async {
    try {
      final dir = _entryDir(remoteRoot);
      final items = await client.readDir(dir);
      return items
          .where((f) => f.name != null && f.name!.endsWith('.json.gz'))
          .toList();
    } catch (_) {
      return <webdav.File>[];
    }
  }

  Future<void> _saveManifest(
    webdav.Client client,
    String remoteRoot,
    Map<String, _ManifestItem> manifest,
  ) async {
    final list = manifest.values.toList()..sort((a, b) => a.id.compareTo(b.id));
    final payload = <String, dynamic>{
      'version': 1,
      'updatedAt': DateTime.now().toIso8601String(),
      'entries': list.map((item) => item.toJson()).toList(),
    };
    await client.write(
      _manifestPath(remoteRoot),
      Uint8List.fromList(utf8.encode(jsonEncode(payload))),
    );
  }

  Future<Map<String, dynamic>> _buildRemoteAttachment(
    webdav.Client client,
    String remoteRoot,
    DiaryAttachment attachment,
  ) async {
    final payload = <String, dynamic>{
      'caption': attachment.caption,
      'type': attachment.type.name,
    };

    final localPath = attachment.path.trim();
    final localFile = localPath.isEmpty ? null : File(localPath);
    if (localFile != null && await localFile.exists()) {
      final bytes = await localFile.readAsBytes();
      final ext = p.extension(localPath).toLowerCase().isEmpty
          ? '.bin'
          : p.extension(localPath).toLowerCase();
      final hash = sha256.convert(bytes).toString();
      final remotePath = '${_attachmentDir(remoteRoot)}/$hash$ext';
      await client.write(remotePath, bytes);
      payload['hash'] = hash;
      payload['remotePath'] = remotePath;
    } else {
      if (attachment.hash.isNotEmpty) {
        payload['hash'] = attachment.hash;
      }
      if (attachment.remotePath.isNotEmpty) {
        payload['remotePath'] = attachment.remotePath;
      }
    }

    final thumbPath = attachment.thumbnailPath.trim();
    final thumbFile = thumbPath.isEmpty ? null : File(thumbPath);
    if (thumbFile != null && await thumbFile.exists()) {
      final bytes = await thumbFile.readAsBytes();
      final hash = (payload['hash'] ?? attachment.hash) as String;
      final thumbRemote = hash.isEmpty
          ? '${_attachmentDir(remoteRoot)}/thumbs/${const Uuid().v4()}.jpg'
          : '${_attachmentDir(remoteRoot)}/thumbs/$hash.jpg';
      await client.write(thumbRemote, bytes);
      payload['thumbnailRemotePath'] = thumbRemote;
    } else if (attachment.thumbnailRemotePath.isNotEmpty) {
      payload['thumbnailRemotePath'] = attachment.thumbnailRemotePath;
    }

    return payload;
  }

  Future<DiaryEntry> _uploadEntry(
    webdav.Client client,
    String remoteRoot,
    DiaryEntry entry,
  ) async {
    final payload = Map<String, dynamic>.from(entry.toSyncJson());
    final syncAttachments = <Map<String, dynamic>>[];
    final mergedAttachments = <DiaryAttachment>[];
    for (final attachment in entry.attachments) {
      final remoteMeta = await _buildRemoteAttachment(
        client,
        remoteRoot,
        attachment,
      );
      syncAttachments.add(remoteMeta);
      mergedAttachments.add(
        attachment.copyWith(
          hash: (remoteMeta['hash'] ?? attachment.hash) as String,
          remotePath:
              (remoteMeta['remotePath'] ?? attachment.remotePath) as String,
          thumbnailRemotePath:
              (remoteMeta['thumbnailRemotePath'] ??
                      attachment.thumbnailRemotePath)
                  as String,
        ),
      );
    }
    payload['attachments'] = syncAttachments;
    final compressed = gzip.encode(utf8.encode(jsonEncode(payload)));
    await client.write(
      '${_entryDir(remoteRoot)}/${entry.id}.json.gz',
      Uint8List.fromList(compressed),
    );
    return entry.copyWith(attachments: mergedAttachments);
  }

  Future<String> _downloadThumb(webdav.Client client, String remotePath) async {
    final bytes = Uint8List.fromList(await client.read(remotePath));
    final saved = await _storageService.saveAttachmentBytesWithThumbnail(
      bytes,
      sourceName: p.basename(remotePath),
      defaultExt: '.jpg',
      withThumbnail: false,
    );
    return saved.path;
  }

  Future<Map<String, dynamic>> _materializeRemoteEntry(
    webdav.Client client,
    Map<String, dynamic> raw,
    DiaryEntry? localEntry,
  ) async {
    final result = Map<String, dynamic>.from(raw);
    final attachmentsRaw =
        (result['attachments'] ?? <dynamic>[]) as List<dynamic>;
    final localByHash = <String, DiaryAttachment>{};
    final localByRemote = <String, DiaryAttachment>{};
    if (localEntry != null) {
      for (final item in localEntry.attachments) {
        if (item.hash.isNotEmpty) {
          localByHash[item.hash] = item;
        }
        if (item.remotePath.isNotEmpty) {
          localByRemote[item.remotePath] = item;
        }
      }
    }

    final hydrated = <Map<String, dynamic>>[];
    for (final item in attachmentsRaw.whereType<Map<String, dynamic>>()) {
      final attachment = Map<String, dynamic>.from(item);
      final hash = (attachment['hash'] ?? '') as String;
      final remotePath = (attachment['remotePath'] ?? '') as String;
      final thumbRemotePath =
          (attachment['thumbnailRemotePath'] ?? '') as String;
      final localMatched = localByHash[hash] ?? localByRemote[remotePath];
      var localPath = localMatched?.path ?? '';
      var thumbPath = localMatched?.thumbnailPath ?? '';

      final legacyBase64 = (attachment.remove('bytesBase64') ?? '') as String;
      if (legacyBase64.isNotEmpty) {
        try {
          final bytes = base64Decode(legacyBase64);
          final saved = await _storageService.saveAttachmentBytesWithThumbnail(
            bytes,
            sourceName: attachment['filename'] as String?,
            defaultExt: '.jpg',
            withThumbnail: true,
          );
          localPath = saved.path;
          thumbPath = saved.thumbnailPath;
          attachment['hash'] = saved.hash;
        } catch (_) {
          // ignore malformed legacy payload
        }
      }

      if (localPath.isNotEmpty && !await File(localPath).exists()) {
        localPath = '';
      }
      if (thumbPath.isNotEmpty && !await File(thumbPath).exists()) {
        thumbPath = '';
      }

      if (thumbPath.isEmpty && thumbRemotePath.isNotEmpty) {
        try {
          thumbPath = await _downloadThumb(client, thumbRemotePath);
        } catch (_) {
          // thumb download is optional
        }
      }

      attachment['path'] = localPath;
      attachment['thumbnailPath'] = thumbPath;
      attachment['remotePath'] = remotePath;
      attachment['thumbnailRemotePath'] = thumbRemotePath;
      hydrated.add(attachment);
    }
    result['attachments'] = hydrated;
    return result;
  }

  Future<void> _reconcileEntriesMissingFromManifest(
    Map<String, _ManifestItem> manifest,
    DateTime lastSync,
  ) async {
    final remoteIds = manifest.keys.toSet();
    final localHeads = await _diaryRepository.listSyncHeads();
    for (final localId in localHeads.keys) {
      if (remoteIds.contains(localId)) {
        continue;
      }
      final localEntry = await _diaryRepository.getById(localId);
      if (localEntry == null) {
        continue;
      }
      // Preserve unsynced local edits; only prune entries that are confirmed
      // stale against the current manifest snapshot.
      if (localEntry.updatedAt.isAfter(lastSync)) {
        continue;
      }
      await _diaryRepository.deleteForever(localId);
    }
  }

  Future<bool> testConnection() async {
    final config = await _settingsRepository.loadWebDavConfig();
    if (!config.isConfigured) {
      return false;
    }
    final client = _buildClient(config);
    await client.ping();
    final remoteRoot = _normalizeDir(config.remoteDir);
    await client.mkdirAll(_entryDir(remoteRoot));
    await client.mkdirAll(_attachmentDir(remoteRoot));
    await client.mkdirAll('${_attachmentDir(remoteRoot)}/thumbs');
    return true;
  }

  Future<DiaryAttachment?> restoreAttachment(DiaryAttachment attachment) async {
    final remotePath = attachment.remotePath.trim();
    if (remotePath.isEmpty) {
      return null;
    }
    final config = await _settingsRepository.loadWebDavConfig();
    if (!config.isConfigured) {
      return null;
    }
    final client = _buildClient(config);
    await client.ping();

    final bytes = Uint8List.fromList(await client.read(remotePath));
    final saved = await _storageService.saveAttachmentBytesWithThumbnail(
      bytes,
      sourceName: p.basename(remotePath),
      defaultExt: '.bin',
      withThumbnail: attachment.thumbnailPath.trim().isEmpty,
    );

    var thumbPath = attachment.thumbnailPath;
    if (thumbPath.trim().isEmpty &&
        attachment.thumbnailRemotePath.trim().isNotEmpty) {
      try {
        thumbPath = await _downloadThumb(
          client,
          attachment.thumbnailRemotePath,
        );
      } catch (_) {
        thumbPath = saved.thumbnailPath;
      }
    }

    return attachment.copyWith(
      path: saved.path,
      hash: attachment.hash.isEmpty ? saved.hash : attachment.hash,
      thumbnailPath: thumbPath,
    );
  }

  Future<SyncResult> syncNow({Locale locale = const Locale('zh', 'CN')}) async {
    final config = await _settingsRepository.loadWebDavConfig();
    if (!config.isConfigured) {
      return SyncResult(
        success: false,
        message: _l10n(
          locale,
          zh: '请先完成 WebDAV 配置',
          en: 'Please configure WebDAV first',
        ),
      );
    }

    final client = _buildClient(config);
    final remoteRoot = _normalizeDir(config.remoteDir);
    final now = DateTime.now();
    final lastSync =
        await _settingsRepository.loadLastSyncAt() ??
        DateTime.fromMillisecondsSinceEpoch(0);

    int uploaded = 0;
    int downloaded = 0;
    int conflicts = 0;
    int recovered = 0;

    try {
      await client.ping();
      await client.mkdirAll(_entryDir(remoteRoot));
      await client.mkdirAll(_attachmentDir(remoteRoot));
      await client.mkdirAll('${_attachmentDir(remoteRoot)}/thumbs');

      final manifest = await _tryLoadManifest(client, remoteRoot) ??
          <String, _ManifestItem>{};
      final pendingHardDeleteIds =
          await _settingsRepository.loadPendingHardDeleteIds();
      final processedHardDeleteIds = <String>[];
      for (final id in pendingHardDeleteIds) {
        final removed = manifest.remove(id);
        if (removed != null) {
          await client.remove(removed.path);
        }
        processedHardDeleteIds.add(id);
      }

      // ── Upload local changes ─────────────────────────────────────
      final changedEntries = await _diaryRepository.listUpdatedAfter(lastSync);
      for (final entry in changedEntries) {
        final uploadedEntry = await _uploadEntry(client, remoteRoot, entry);
        await _diaryRepository.upsert(uploadedEntry);
        manifest[uploadedEntry.id] = _ManifestItem(
          id: uploadedEntry.id,
          path: '${_entryDir(remoteRoot)}/${uploadedEntry.id}.json.gz',
          updatedAt: uploadedEntry.updatedAt,
          isDeleted: uploadedEntry.isDeleted,
        );
        uploaded++;
      }

      // ── Recover orphaned entry files not referenced by manifest ──
      final remoteFiles = await _listRemoteEntryFiles(client, remoteRoot);
      for (final file in remoteFiles) {
        final fileName = file.name!;
        final entryId = fileName.substring(0, fileName.length - '.json.gz'.length);
        if (manifest.containsKey(entryId)) {
          continue;
        }
        final filePath = '${_entryDir(remoteRoot)}/$fileName';
        try {
          final bytes = await client.read(filePath);
          final decoded = utf8.decode(gzip.decode(bytes));
          final map = jsonDecode(decoded) as Map<String, dynamic>;
          final hydratedMap = await _materializeRemoteEntry(client, map, null);
          final remoteEntry = DiaryEntry.fromSyncJson(hydratedMap);
          await _diaryRepository.upsert(remoteEntry);
          manifest[remoteEntry.id] = _ManifestItem(
            id: remoteEntry.id,
            path: filePath,
            updatedAt: remoteEntry.updatedAt,
            isDeleted: remoteEntry.isDeleted,
          );
          recovered++;
        } catch (_) {
          // Skip unreadable files.
        }
      }

      // ── Download entries from manifest ───────────────────────────
      final localHeads = await _diaryRepository.listSyncHeads();
      final remoteItems = manifest.values.toList()
        ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

      for (final item in remoteItems) {
        final local = await _diaryRepository.getById(item.id);
        final localUpdated = localHeads[item.id];
        final upToDate =
            localUpdated != null && !item.updatedAt.isAfter(localUpdated);
        if (upToDate && !await _needsAttachmentHydration(local)) {
          continue;
        }

        final localDirty = local != null && local.updatedAt.isAfter(lastSync);
        final remoteDirty = item.updatedAt.isAfter(lastSync);
        if (local != null &&
            localDirty &&
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

        try {
          final bytes = await client.read(item.path);
          final decoded = utf8.decode(gzip.decode(bytes));
          final map = jsonDecode(decoded) as Map<String, dynamic>;
          final hydratedMap = await _materializeRemoteEntry(client, map, local);
          final remoteEntry = DiaryEntry.fromSyncJson(hydratedMap);
          await _diaryRepository.upsert(remoteEntry);
          downloaded++;
        } catch (_) {
          // Skip entries whose remote file is missing / corrupted.
          manifest.remove(item.id);
        }
      }

      await _reconcileEntriesMissingFromManifest(manifest, lastSync);
      await _saveManifest(client, remoteRoot, manifest);
      if (processedHardDeleteIds.isNotEmpty) {
        final pendingSet = pendingHardDeleteIds.toSet()
          ..removeAll(processedHardDeleteIds);
        await _settingsRepository.savePendingHardDeleteIds(pendingSet.toList());
      }
      await _settingsRepository.saveLastSyncAt(now);

      final message = recovered > 0
          ? _l10n(
              locale,
              zh: '同步完成，恢复 $recovered 条日记',
              en: 'Sync completed, recovered $recovered entries',
            )
          : _l10n(locale, zh: '同步完成', en: 'Sync completed');
      return SyncResult(
        success: true,
        message: message,
        uploaded: uploaded,
        downloaded: downloaded + recovered,
        conflicts: conflicts,
      );
    } catch (e) {
      return SyncResult(
        success: false,
        message: _l10n(
          locale,
          zh: '同步失败: $e',
          en: 'Sync failed: $e',
        ),
        uploaded: uploaded,
        downloaded: downloaded,
        conflicts: conflicts,
      );
    }
  }

  String _l10n(Locale locale, {required String zh, required String en}) {
    return locale.languageCode.toLowerCase() == 'zh' ? zh : en;
  }
}
