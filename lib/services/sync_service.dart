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

class _Revision {
  const _Revision({
    required this.deviceId,
    required this.counter,
    required this.wallTimeMs,
  });

  final String deviceId;
  final int counter;
  final int wallTimeMs;

  static const zero = _Revision(deviceId: '', counter: 0, wallTimeMs: 0);

  bool get isZero => deviceId.isEmpty && counter == 0 && wallTimeMs == 0;

  String encode() => '$wallTimeMs:$counter:$deviceId';

  static _Revision decode(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) {
      return zero;
    }
    final parts = trimmed.split(':');
    if (parts.length < 3) {
      return zero;
    }
    final wallTimeMs = int.tryParse(parts[0]) ?? 0;
    final counter = int.tryParse(parts[1]) ?? 0;
    final deviceId = parts.sublist(2).join(':').trim();
    if (deviceId.isEmpty || wallTimeMs <= 0 || counter <= 0) {
      return zero;
    }
    return _Revision(
      deviceId: deviceId,
      counter: counter,
      wallTimeMs: wallTimeMs,
    );
  }
}

class _SyncState {
  const _SyncState({
    required this.lastSyncedRevision,
    required this.contentFingerprint,
    this.lastRemoteUpdatedAt,
    this.lastRemoteDeletedAt,
  });

  final String lastSyncedRevision;
  final String contentFingerprint;
  final DateTime? lastRemoteUpdatedAt;
  final DateTime? lastRemoteDeletedAt;

  bool get isInitialized =>
      lastSyncedRevision.trim().isNotEmpty || contentFingerprint.trim().isNotEmpty;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'lastSyncedRevision': lastSyncedRevision,
    'contentFingerprint': contentFingerprint,
    if (lastRemoteUpdatedAt != null)
      'lastRemoteUpdatedAt': lastRemoteUpdatedAt!.toIso8601String(),
    if (lastRemoteDeletedAt != null)
      'lastRemoteDeletedAt': lastRemoteDeletedAt!.toIso8601String(),
  };

  static const empty = _SyncState(lastSyncedRevision: '', contentFingerprint: '');

  static _SyncState fromJson(Map<String, dynamic> json) {
    return _SyncState(
      lastSyncedRevision: (json['lastSyncedRevision'] ?? '') as String,
      contentFingerprint: (json['contentFingerprint'] ?? '') as String,
      lastRemoteUpdatedAt: DateTime.tryParse(
        (json['lastRemoteUpdatedAt'] ?? '') as String,
      ),
      lastRemoteDeletedAt: DateTime.tryParse(
        (json['lastRemoteDeletedAt'] ?? '') as String,
      ),
    );
  }
}

class _EntryEnvelope {
  const _EntryEnvelope({
    required this.entry,
    required this.revision,
    required this.updatedAt,
    required this.deletedAt,
    required this.contentFingerprint,
  });

  final DiaryEntry entry;
  final String revision;
  final DateTime updatedAt;
  final DateTime? deletedAt;
  final String contentFingerprint;

  bool get isDeleted => entry.isDeleted;

  Map<String, dynamic> toJson() {
    final payload = Map<String, dynamic>.from(entry.toSyncJson());
    payload['revision'] = revision;
    payload['updatedAt'] = updatedAt.toIso8601String();
    payload['contentFingerprint'] = contentFingerprint;
    if (deletedAt != null) {
      payload['deletedAt'] = deletedAt!.toIso8601String();
    }
    return payload;
  }

  static _EntryEnvelope fromJson(Map<String, dynamic> json) {
    final entry = DiaryEntry.fromSyncJson(json);
    final updatedAt =
        DateTime.tryParse((json['updatedAt'] ?? '') as String) ?? entry.updatedAt;
    return _EntryEnvelope(
      entry: entry.copyWith(updatedAt: updatedAt),
      revision: (json['revision'] ?? '') as String,
      updatedAt: updatedAt,
      deletedAt: DateTime.tryParse((json['deletedAt'] ?? '') as String),
      contentFingerprint: (json['contentFingerprint'] ?? '') as String,
    );
  }
}

class _TombstoneRecord {
  const _TombstoneRecord({
    required this.id,
    required this.revision,
    required this.deletedAt,
    required this.targetRevision,
  });

  final String id;
  final String revision;
  final DateTime deletedAt;
  final String targetRevision;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'revision': revision,
    'deletedAt': deletedAt.toIso8601String(),
    if (targetRevision.trim().isNotEmpty) 'targetRevision': targetRevision,
  };

  static _TombstoneRecord fromJson(Map<String, dynamic> json) {
    return _TombstoneRecord(
      id: (json['id'] ?? '') as String,
      revision: (json['revision'] ?? '') as String,
      deletedAt:
          DateTime.tryParse((json['deletedAt'] ?? '') as String) ??
          DateTime.fromMillisecondsSinceEpoch(0),
      targetRevision: (json['targetRevision'] ?? '') as String,
    );
  }
}

class _RemoteSnapshot {
  const _RemoteSnapshot({required this.entries, required this.tombstones});

  final Map<String, _RemoteFile<_EntryEnvelope>> entries;
  final Map<String, _RemoteFile<_TombstoneRecord>> tombstones;
}

class _RemoteFile<T> {
  const _RemoteFile({
    required this.path,
    required this.payload,
    required this.modifiedAt,
    required this.eTag,
  });

  final String path;
  final T payload;
  final DateTime modifiedAt;
  final String eTag;
}

class _PendingHardDelete {
  const _PendingHardDelete({
    required this.id,
    required this.revision,
    required this.deletedAt,
    required this.targetRevision,
  });

  final String id;
  final String revision;
  final DateTime deletedAt;
  final String targetRevision;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'revision': revision,
    'deletedAt': deletedAt.toIso8601String(),
    if (targetRevision.trim().isNotEmpty) 'targetRevision': targetRevision,
  };

  static _PendingHardDelete fromJson(Map<String, dynamic> json) {
    return _PendingHardDelete(
      id: (json['id'] ?? '') as String,
      revision: (json['revision'] ?? '') as String,
      deletedAt:
          DateTime.tryParse((json['deletedAt'] ?? '') as String) ??
          DateTime.now(),
      targetRevision: (json['targetRevision'] ?? '') as String,
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
  String _thumbDir(String root) => '${_attachmentDir(root)}/thumbs';
  String _tombstoneDir(String root) => '$root/tombstones';

  String _entryPath(String root, String id) => '${_entryDir(root)}/$id.json.gz';
  String _tombstonePath(String root, String id) =>
      '${_tombstoneDir(root)}/$id.json';

  Future<void> markEntryHardDeleted(String id) async {
    final local = await _diaryRepository.getById(id);
    final state = await _loadSyncStateForEntry(id);
    final revision = state.lastSyncedRevision.trim().isNotEmpty
        ? state.lastSyncedRevision
        : await _newRevisionString();
    final deletedAt = DateTime.now();
    final record = _PendingHardDelete(
      id: id,
      revision: revision,
      deletedAt: deletedAt,
      targetRevision: state.lastSyncedRevision,
    );
    await _upsertPendingHardDeletes([record]);
    if (local != null) {
      await _clearEntrySyncState(id);
    }
  }

  Future<void> markEntriesHardDeleted(List<String> ids) async {
    for (final id in ids) {
      await markEntryHardDeleted(id);
    }
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

  int _compareRevision(String a, String b) {
    if (a.isEmpty && b.isEmpty) {
      return 0;
    }
    if (a.isEmpty) {
      return -1;
    }
    if (b.isEmpty) {
      return 1;
    }
    final ra = _Revision.decode(a);
    final rb = _Revision.decode(b);
    if (ra.wallTimeMs != rb.wallTimeMs) {
      return ra.wallTimeMs.compareTo(rb.wallTimeMs);
    }
    if (ra.counter != rb.counter) {
      return ra.counter.compareTo(rb.counter);
    }
    return ra.deviceId.compareTo(rb.deviceId);
  }

  String _contentFingerprint(DiaryEntry entry) {
    final payload = utf8.encode(jsonEncode(<String, dynamic>{
      'title': entry.title,
      'plainText': entry.plainText,
      'mood': entry.mood,
      'weather': entry.weather,
      'location': entry.location,
      'attachments': entry.attachments
          .map((a) => <String, dynamic>{
                'hash': a.hash,
                'remotePath': a.remotePath,
              })
          .toList(),
    }));
    return sha256.convert(payload).toString();
  }

  Future<String> _newRevisionString() async {
    final clockData = await _settingsRepository.loadSyncClock();
    final wallTimeMs = DateTime.now().millisecondsSinceEpoch;
    final lastWallTime = (clockData['wallTimeMs'] ?? 0) as int;
    var counter = (clockData['counter'] ?? 0) as int;
    if (wallTimeMs > lastWallTime) {
      counter = 1;
    } else {
      counter++;
    }
    await _settingsRepository.saveSyncClock(
      wallTimeMs: wallTimeMs,
      counter: counter,
    );
    final deviceId = await _resolveSyncDeviceId();
    return _Revision(
      deviceId: deviceId,
      counter: counter,
      wallTimeMs: wallTimeMs,
    ).encode();
  }

  Future<String> _resolveSyncDeviceId() async {
    var id = await _settingsRepository.loadSyncDeviceId();
    if (id.isNotEmpty) {
      return id;
    }
    id = const Uuid().v4();
    await _settingsRepository.saveSyncDeviceId(id);
    return id;
  }

  Future<_SyncState> _loadSyncStateForEntry(String id) async {
    final states = await _settingsRepository.loadEntrySyncStates();
    final raw = states[id];
    if (raw is! Map<String, dynamic>) {
      return _SyncState.empty;
    }
    return _SyncState.fromJson(raw);
  }

  Future<void> _clearEntrySyncState(String id) async {
    final states = await _settingsRepository.loadEntrySyncStates();
    states.remove(id);
    await _settingsRepository.saveEntrySyncStates(states);
  }

  Future<void> _saveSyncStates(
    Map<String, _SyncState> syncStates,
  ) async {
    final states = await _settingsRepository.loadEntrySyncStates();
    for (final entry in syncStates.entries) {
      states[entry.key] = entry.value.toJson();
    }
    await _settingsRepository.saveEntrySyncStates(states);
  }

  Future<void> _upsertPendingHardDeletes(
    List<_PendingHardDelete> records,
  ) async {
    final existing = await _settingsRepository.loadPendingHardDeleteRecords();
    final existingMap = <String, Map<String, dynamic>>{};
    for (final rec in existing) {
      final id = (rec['id'] ?? '') as String;
      if (id.isNotEmpty) {
        existingMap[id] = rec;
      }
    }
    for (final record in records) {
      existingMap[record.id] = record.toJson();
    }
    await _settingsRepository.savePendingHardDeleteRecords(
      existingMap.values.toList(),
    );
  }

  Future<void> _ensureRemoteLayout(webdav.Client client, String remoteRoot) async {
    await client.mkdirAll(_entryDir(remoteRoot));
    await client.mkdirAll(_attachmentDir(remoteRoot));
    await client.mkdirAll(_thumbDir(remoteRoot));
    await client.mkdirAll(_tombstoneDir(remoteRoot));
  }

  Future<_RemoteSnapshot> _loadRemoteSnapshot(
    webdav.Client client,
    String remoteRoot,
  ) async {
    final entries = <String, _RemoteFile<_EntryEnvelope>>{};
    final tombstones = <String, _RemoteFile<_TombstoneRecord>>{};

    Future<void> loadEntries() async {
      final listing = await client.readDir(_entryDir(remoteRoot));
      for (final item in listing) {
        if (item.isDir == true || !(item.name ?? '').endsWith('.json.gz')) {
          continue;
        }
        final path = item.path ?? '';
        if (path.isEmpty) {
          continue;
        }
        final decoded = utf8.decode(gzip.decode(await client.read(path)));
        final json = jsonDecode(decoded) as Map<String, dynamic>;
        final envelope = _EntryEnvelope.fromJson(json);
        final id = envelope.entry.id.trim();
        if (id.isEmpty) {
          continue;
        }
        final modifiedAt = item.mTime ?? envelope.updatedAt;
        final current = entries[id];
        if (current != null &&
            _compareRevision(current.payload.revision, envelope.revision) >= 0) {
          continue;
        }
        entries[id] = _RemoteFile<_EntryEnvelope>(
          path: path,
          payload: envelope,
          modifiedAt: modifiedAt,
          eTag: item.eTag ?? '',
        );
      }
    }

    Future<void> loadTombstones() async {
      final listing = await client.readDir(_tombstoneDir(remoteRoot));
      for (final item in listing) {
        if (item.isDir == true || !(item.name ?? '').endsWith('.json')) {
          continue;
        }
        final path = item.path ?? '';
        if (path.isEmpty) {
          continue;
        }
        final json = jsonDecode(utf8.decode(await client.read(path)))
            as Map<String, dynamic>;
        final record = _TombstoneRecord.fromJson(json);
        if (record.id.trim().isEmpty) {
          continue;
        }
        final current = tombstones[record.id];
        if (current != null &&
            _compareRevision(current.payload.revision, record.revision) >= 0) {
          continue;
        }
        tombstones[record.id] = _RemoteFile<_TombstoneRecord>(
          path: path,
          payload: record,
          modifiedAt: item.mTime ?? record.deletedAt,
          eTag: item.eTag ?? '',
        );
      }
    }

    await loadEntries();
    await loadTombstones();
    return _RemoteSnapshot(entries: entries, tombstones: tombstones);
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
          ? '${_thumbDir(remoteRoot)}/${const Uuid().v4()}.jpg'
          : '${_thumbDir(remoteRoot)}/$hash.jpg';
      await client.write(thumbRemote, bytes);
      payload['thumbnailRemotePath'] = thumbRemote;
    } else if (attachment.thumbnailRemotePath.isNotEmpty) {
      payload['thumbnailRemotePath'] = attachment.thumbnailRemotePath;
    }

    return payload;
  }

  Future<_EntryEnvelope> _uploadEntry(
    webdav.Client client,
    String remoteRoot,
    DiaryEntry entry, {
    required String revision,
  }) async {
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
    final mergedEntry = entry.copyWith(attachments: mergedAttachments);
    final envelope = _EntryEnvelope(
      entry: mergedEntry,
      revision: revision,
      updatedAt: mergedEntry.updatedAt,
      deletedAt: mergedEntry.isDeleted ? mergedEntry.updatedAt : null,
      contentFingerprint: _contentFingerprint(mergedEntry),
    );
    final writable = envelope.toJson()..['attachments'] = syncAttachments;
    final compressed = gzip.encode(utf8.encode(jsonEncode(writable)));
    await client.write(
      _entryPath(remoteRoot, mergedEntry.id),
      Uint8List.fromList(compressed),
    );
    return envelope;
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

  Future<Set<String>> _collectReferencedAttachmentPaths(
    webdav.Client client,
    String remoteRoot,
    Map<String, _RemoteFile<_EntryEnvelope>> entries,
  ) async {
    final result = <String>{};
    for (final remote in entries.values) {
      for (final attachment in remote.payload.entry.attachments) {
        final main = attachment.remotePath.trim();
        final thumb = attachment.thumbnailRemotePath.trim();
        if (main.isNotEmpty) {
          result.add(main);
        }
        if (thumb.isNotEmpty) {
          result.add(thumb);
        }
      }
    }
    return result;
  }

  Future<void> _cleanupRemoteAttachmentGarbage(
    webdav.Client client,
    String remoteRoot,
    Map<String, _RemoteFile<_EntryEnvelope>> entries,
  ) async {
    final cutoff = DateTime.now().subtract(const Duration(days: 30));
    final referenced = await _collectReferencedAttachmentPaths(
      client,
      remoteRoot,
      entries,
    );
    final attachments = await client.readDir(_attachmentDir(remoteRoot));
    for (final item in attachments) {
      if (item.isDir == true) {
        continue;
      }
      final path = item.path ?? '';
      final modifiedAt = item.mTime;
      if (path.isEmpty ||
          referenced.contains(path) ||
          modifiedAt == null ||
          modifiedAt.isAfter(cutoff)) {
        continue;
      }
      await client.remove(path);
    }
    final thumbs = await client.readDir(_thumbDir(remoteRoot));
    for (final item in thumbs) {
      if (item.isDir == true) {
        continue;
      }
      final path = item.path ?? '';
      final modifiedAt = item.mTime;
      if (path.isEmpty ||
          referenced.contains(path) ||
          modifiedAt == null ||
          modifiedAt.isAfter(cutoff)) {
        continue;
      }
      await client.remove(path);
    }
  }

  Future<void> _writeTombstone(
    webdav.Client client,
    String remoteRoot,
    _PendingHardDelete record,
  ) async {
    final payload = _TombstoneRecord(
      id: record.id,
      revision: record.revision,
      deletedAt: record.deletedAt,
      targetRevision: record.targetRevision,
    );
    await client.write(
      _tombstonePath(remoteRoot, record.id),
      Uint8List.fromList(utf8.encode(jsonEncode(payload.toJson()))),
    );
    await client.remove(_entryPath(remoteRoot, record.id));
  }

  Future<bool> testConnection() async {
    final config = await _settingsRepository.loadWebDavConfig();
    if (!config.isConfigured) {
      return false;
    }
    final client = _buildClient(config);
    await client.ping();
    final remoteRoot = _normalizeDir(config.remoteDir);
    await _ensureRemoteLayout(client, remoteRoot);
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
    int uploaded = 0;
    int downloaded = 0;
    int conflicts = 0;

    try {
      await client.ping();
      await _ensureRemoteLayout(client, remoteRoot);

      // ── Load remote state ────────────────────────────────────────
      final remote = await _loadRemoteSnapshot(client, remoteRoot);

      // ── Process pending hard deletes ─────────────────────────────
      final pendingRecords = await _settingsRepository
          .loadPendingHardDeleteRecords();
      final processedIds = <String>[];
      for (final raw in pendingRecords) {
        final id = (raw['id'] ?? '') as String;
        final trimmed = id.trim();
        if (trimmed.isEmpty) {
          continue;
        }
        final record = _PendingHardDelete.fromJson(raw);
        try {
          await _writeTombstone(client, remoteRoot, record);
        } catch (_) {
          // Will retry on next sync.
          continue;
        }
        processedIds.add(trimmed);
      }
      if (processedIds.isNotEmpty) {
        final remaining = pendingRecords
            .where((r) => !processedIds.contains(((r['id'] ?? '') as String).trim()))
            .toList();
        await _settingsRepository.savePendingHardDeleteRecords(remaining);
      }

      // ── Collect sync states ──────────────────────────────────────
      final localAll = await _diaryRepository.listAll();
      final syncStates = <String, _SyncState>{};
      for (final entry in localAll) {
        syncStates[entry.id] = await _loadSyncStateForEntry(entry.id);
      }

      // ── Upload local changes ─────────────────────────────────────
      for (final entry in localAll) {
        final state = syncStates[entry.id] ?? _SyncState.empty;
        final fingerprint = _contentFingerprint(entry);
        final remoteFile = remote.entries[entry.id];
        final remoteFingerprint = remoteFile?.payload.contentFingerprint ?? '';
        final isContentSame = fingerprint == remoteFingerprint &&
            remoteFingerprint.isNotEmpty;

        if (isContentSame) {
          // Content unchanged — just update sync state if needed.
          if (remoteFile != null &&
              remoteFile.payload.revision != state.lastSyncedRevision) {
            syncStates[entry.id] = _SyncState(
              lastSyncedRevision: remoteFile.payload.revision,
              contentFingerprint: fingerprint,
              lastRemoteUpdatedAt: remoteFile.modifiedAt,
            );
          }
          continue;
        }

        final revision = await _newRevisionString();
        await _uploadEntry(
          client,
          remoteRoot,
          entry,
          revision: revision,
        );
        syncStates[entry.id] = _SyncState(
          lastSyncedRevision: revision,
          contentFingerprint: fingerprint,
          lastRemoteUpdatedAt: DateTime.now(),
        );
        uploaded++;
      }

      // ── Download new / updated remote entries ────────────────────
      for (final entry in remote.entries.values) {
        final id = entry.payload.entry.id;
        final local = await _diaryRepository.getById(id);
        final state = syncStates[id] ?? _SyncState.empty;

        // Already synced this revision.
        if (state.lastSyncedRevision == entry.payload.revision) {
          if (!await _needsAttachmentHydration(local)) {
            continue;
          }
        }

        // Check if local has unsynced changes.
        if (local != null &&
            state.lastSyncedRevision.isNotEmpty &&
            state.lastSyncedRevision != entry.payload.revision &&
            state.contentFingerprint != _contentFingerprint(local)) {
          // Both local and remote modified — conflict.
          if (config.conflictStrategy == ConflictStrategy.keepBoth) {
            await _diaryRepository.upsert(
              local.copyWith(
                id: const Uuid().v4(),
                title: '${local.title} (冲突副本)',
                updatedAt: DateTime.now(),
              ),
            );
            conflicts++;
          }
          // For lastWriteWins, remote overwrites local silently.
        }

        final raw = entry.payload.entry.toSyncJson()
          ..['attachments'] =
              entry.payload.entry.attachments.map((a) => a.toJson()).toList();
        final hydrated = await _materializeRemoteEntry(
          client,
          raw,
          local,
        );
        final readyEntry = DiaryEntry.fromSyncJson(hydrated)
            .copyWith(updatedAt: entry.payload.updatedAt);
        await _diaryRepository.upsert(readyEntry);
        syncStates[id] = _SyncState(
          lastSyncedRevision: entry.payload.revision,
          contentFingerprint: entry.payload.contentFingerprint,
          lastRemoteUpdatedAt: entry.modifiedAt,
        );
        downloaded++;
      }

      // ── Apply remote tombstones ──────────────────────────────────
      for (final entry in remote.tombstones.values) {
        final id = entry.payload.id;
        final local = await _diaryRepository.getById(id);
        if (local == null) {
          continue;
        }
        final state = syncStates[id] ?? _SyncState.empty;
        if (_compareRevision(state.lastSyncedRevision, entry.payload.revision) >= 0) {
          continue;
        }
        await _diaryRepository.deleteForever(id);
        await _clearEntrySyncState(id);
        syncStates.remove(id);
      }

      // ── Persist sync state and cleanup ───────────────────────────
      await _saveSyncStates(syncStates);
      await _cleanupRemoteAttachmentGarbage(
        client,
        remoteRoot,
        remote.entries,
      );
      final now = DateTime.now();
      await _settingsRepository.saveLastSyncAt(now);

      return SyncResult(
        success: true,
        message: _l10n(locale, zh: '同步完成', en: 'Sync completed'),
        uploaded: uploaded,
        downloaded: downloaded,
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
