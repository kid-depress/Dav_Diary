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

class _ManifestEntry {
  const _ManifestEntry({
    required this.id,
    required this.path,
    required this.revision,
    required this.contentFingerprint,
    this.attachmentRefs = const <String>[],
  });

  final String id;
  final String path;
  final String revision;
  final String contentFingerprint;
  final List<String> attachmentRefs;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'path': path,
    'revision': revision,
    'contentFingerprint': contentFingerprint,
    if (attachmentRefs.isNotEmpty) 'attachmentRefs': attachmentRefs,
  };

  static _ManifestEntry fromJson(Map<String, dynamic> json) {
    return _ManifestEntry(
      id: (json['id'] ?? '') as String,
      path: (json['path'] ?? '') as String,
      revision: (json['revision'] ?? '') as String,
      contentFingerprint: (json['contentFingerprint'] ?? '') as String,
      attachmentRefs: (json['attachmentRefs'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const <String>[],
    );
  }
}

class _RemoteManifest {
  const _RemoteManifest({
    required this.entries,
    required this.tombstones,
  });

  final Map<String, _ManifestEntry> entries;
  final Map<String, _TombstoneRecord> tombstones;
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
    client.setConnectTimeout(5000);
    client.setSendTimeout(5000);
    client.setReceiveTimeout(5000);
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

  Future<T> _retryWithBackoff<T>(
    Future<T> Function() operation, {
    int maxAttempts = 3,
    int baseDelayMs = 300,
  }) async {
    var attempt = 0;
    while (true) {
      attempt++;
      try {
        return await operation();
      } catch (e) {
        if (attempt >= maxAttempts || _isPermanentError(e)) {
          rethrow;
        }
        final delay = baseDelayMs * (1 << (attempt - 1));
        await Future<void>.delayed(Duration(milliseconds: delay));
      }
    }
  }

  bool _isPermanentError(Object e) {
    final msg = e.toString().toLowerCase();
    if (msg.contains('401') || msg.contains('403') || msg.contains('404') ||
        msg.contains('409')) {
      return true;
    }
    if (msg.contains('not found') || msg.contains('unauthorized') ||
        msg.contains('forbidden') || msg.contains('not a directory')) {
      return true;
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
      'isDeleted': entry.isDeleted,
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

  _SyncState _parseSyncState(Map<String, dynamic> states, String id) {
    final raw = states[id];
    if (raw is! Map<String, dynamic>) {
      return _SyncState.empty;
    }
    return _SyncState.fromJson(raw);
  }

  Future<_SyncState> _loadSyncStateForEntry(String id) async {
    final states = await _settingsRepository.loadEntrySyncStates();
    return _parseSyncState(states, id);
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

  String _manifestPath(String root) => '$root/manifest.json';

  Future<_RemoteManifest> _loadRemoteManifest(
    webdav.Client client,
    String remoteRoot,
  ) async {
    final entries = <String, _ManifestEntry>{};
    final tombstones = <String, _TombstoneRecord>{};
    var manifestVersion = 0;

    // ── Load manifest index ─────────────────────────────────────────
    try {
      final bytes = await client.read(_manifestPath(remoteRoot));
      final decoded = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
      manifestVersion = (decoded['version'] ?? 0) as int;
      final list = (decoded['entries'] ?? <dynamic>[]) as List<dynamic>;
      for (final item in list.whereType<Map<String, dynamic>>()) {
        final me = _ManifestEntry.fromJson(item);
        if (me.id.isNotEmpty && me.path.isNotEmpty) {
          entries[me.id] = me;
        }
      }
      // ── Load tombstones from manifest (v2+) ──────────────────────
      if (manifestVersion >= 2) {
        final tsList = (decoded['tombstones'] ?? <dynamic>[]) as List<dynamic>;
        for (final item in tsList.whereType<Map<String, dynamic>>()) {
          final record = _TombstoneRecord.fromJson(item);
          if (record.id.trim().isNotEmpty) {
            final existing = tombstones[record.id];
            if (existing == null ||
                _compareRevision(existing.revision, record.revision) < 0) {
              tombstones[record.id] = record;
            }
          }
        }
      }
    } catch (_) {
      // Manifest missing or corrupted — rebuild from directory scan.
    }

    // ── Orphan recovery: only when manifest is missing ────────────
    if (manifestVersion == 0) {
      try {
        final listing = await client.readDir(_entryDir(remoteRoot));
        for (final item in listing) {
          if (item.isDir == true || !(item.name ?? '').endsWith('.json.gz')) {
            continue;
          }
          final path = item.path ?? '';
          if (path.isEmpty) continue;
          final id = item.name!.substring(
            0,
            item.name!.length - '.json.gz'.length,
          );
          if (id.isEmpty || entries.containsKey(id)) continue;
          try {
            final decoded = utf8.decode(gzip.decode(await client.read(path)));
            final json = jsonDecode(decoded) as Map<String, dynamic>;
            final envelope = _EntryEnvelope.fromJson(json);
            entries[id] = _ManifestEntry(
              id: id,
              path: path,
              revision: envelope.revision,
              contentFingerprint: envelope.contentFingerprint,
              attachmentRefs: _collectAttachmentRefs(envelope.entry),
            );
          } catch (_) {}
        }
      } catch (_) {}
    }

    // ── Backward compat: load legacy tombstone files (v1) ─────────
    if (manifestVersion < 2) {
      try {
        final listing = await client.readDir(_tombstoneDir(remoteRoot));
        for (final item in listing) {
          if (item.isDir == true || !(item.name ?? '').endsWith('.json')) {
            continue;
          }
          final path = item.path ?? '';
          if (path.isEmpty) continue;
          try {
            final json = jsonDecode(utf8.decode(await client.read(path)))
                as Map<String, dynamic>;
            final record = _TombstoneRecord.fromJson(json);
            if (record.id.trim().isEmpty) continue;
            final existing = tombstones[record.id];
            if (existing != null &&
                _compareRevision(existing.revision, record.revision) >= 0) {
              continue;
            }
            tombstones[record.id] = record;
          } catch (_) {}
        }
      } catch (_) {}
    }

    return _RemoteManifest(entries: entries, tombstones: tombstones);
  }

  Future<void> _saveRemoteManifest(
    webdav.Client client,
    String remoteRoot,
    _RemoteManifest manifest,
  ) async {
    final list = manifest.entries.values
        .map((e) => e.toJson())
        .toList()
      ..sort((a, b) => ((a['id'] ?? '') as String)
          .compareTo((b['id'] ?? '') as String));
    final tsList = manifest.tombstones.values
        .map((t) => t.toJson())
        .toList()
      ..sort((a, b) => ((a['id'] ?? '') as String)
          .compareTo((b['id'] ?? '') as String));
    final payload = <String, dynamic>{
      'version': 2,
      'updatedAt': DateTime.now().toIso8601String(),
      'entries': list,
      if (tsList.isNotEmpty) 'tombstones': tsList,
    };
    await client.write(
      _manifestPath(remoteRoot),
      Uint8List.fromList(utf8.encode(jsonEncode(payload))),
    );
  }

  Future<Map<String, DateTime>> _listRemoteAttachmentFiles(
    webdav.Client client,
    String remoteRoot,
  ) async {
    final files = <String, DateTime>{};
    try {
      final attachments = await client.readDir(_attachmentDir(remoteRoot));
      for (final item in attachments) {
        if (item.isDir != true && (item.path ?? '').isNotEmpty) {
          files[item.path!] = item.mTime ?? DateTime.fromMillisecondsSinceEpoch(0);
        }
      }
    } catch (_) {}
    try {
      final thumbs = await client.readDir(_thumbDir(remoteRoot));
      for (final item in thumbs) {
        if (item.isDir != true && (item.path ?? '').isNotEmpty) {
          files[item.path!] = item.mTime ?? DateTime.fromMillisecondsSinceEpoch(0);
        }
      }
    } catch (_) {}
    return files;
  }

  Future<_EntryEnvelope> _downloadRemoteEntry(
    webdav.Client client,
    String remoteRoot,
    _ManifestEntry manifestEntry,
  ) async {
    final bytes = await _retryWithBackoff(
      () => client.read(manifestEntry.path),
      baseDelayMs: 400,
    );
    final decoded = utf8.decode(gzip.decode(bytes));
    final json = jsonDecode(decoded) as Map<String, dynamic>;
    return _EntryEnvelope.fromJson(json);
  }

  Future<Map<String, dynamic>> _buildRemoteAttachment(
    webdav.Client client,
    String remoteRoot,
    DiaryAttachment attachment, {
    Set<String> existingRemoteFiles = const <String>{},
  }) async {
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
      if (!existingRemoteFiles.contains(remotePath)) {
        await client.write(remotePath, bytes);
      }
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
      if (!existingRemoteFiles.contains(thumbRemote)) {
        await client.write(thumbRemote, bytes);
      }
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
    Set<String> existingRemoteFiles = const <String>{},
  }) async {
    final syncAttachments = <Map<String, dynamic>>[];
    final mergedAttachments = <DiaryAttachment>[];
    for (final attachment in entry.attachments) {
      final remoteMeta = await _buildRemoteAttachment(
        client,
        remoteRoot,
        attachment,
        existingRemoteFiles: existingRemoteFiles,
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
    await _retryWithBackoff(
      () => client.write(
        _entryPath(remoteRoot, mergedEntry.id),
        Uint8List.fromList(compressed),
      ),
      baseDelayMs: 400,
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
    Map<String, _ManifestEntry> entries,
  ) async {
    final result = <String>{};
    for (final me in entries.values) {
      if (me.attachmentRefs.isNotEmpty) {
        result.addAll(me.attachmentRefs);
        continue;
      }
      // Backward compat: manifest entry without attachmentRefs.
      try {
        final envelope = await _downloadRemoteEntry(client, remoteRoot, me);
        for (final attachment in envelope.entry.attachments) {
          final main = attachment.remotePath.trim();
          final thumb = attachment.thumbnailRemotePath.trim();
          if (main.isNotEmpty) {
            result.add(main);
          }
          if (thumb.isNotEmpty) {
            result.add(thumb);
          }
        }
      } catch (_) {
        // Skip unreadable entries during cleanup.
      }
    }
    return result;
  }

  List<String> _collectAttachmentRefs(DiaryEntry entry) {
    final refs = <String>[];
    for (final a in entry.attachments) {
      if (a.remotePath.isNotEmpty) {
        refs.add(a.remotePath);
      }
      if (a.thumbnailRemotePath.isNotEmpty) {
        refs.add(a.thumbnailRemotePath);
      }
    }
    return refs;
  }

  Future<void> _cleanupRemoteAttachmentGarbage(
    webdav.Client client,
    String remoteRoot,
    Map<String, _ManifestEntry> entries,
    Map<String, DateTime> existingRemoteFiles,
  ) async {
    final cutoff = DateTime.now().subtract(const Duration(days: 30));
    final referenced = await _collectReferencedAttachmentPaths(
      client,
      remoteRoot,
      entries,
    );
    for (final entry in existingRemoteFiles.entries) {
      final path = entry.key;
      final modifiedAt = entry.value;
      if (referenced.contains(path) || modifiedAt.isAfter(cutoff)) {
        continue;
      }
      try {
        await client.remove(path);
      } catch (_) {}
    }
  }

  Future<void> _writeTombstone(
    webdav.Client client,
    String remoteRoot,
    _PendingHardDelete record,
    _RemoteManifest manifest,
  ) async {
    manifest.tombstones[record.id] = _TombstoneRecord(
      id: record.id,
      revision: record.revision,
      deletedAt: record.deletedAt,
      targetRevision: record.targetRevision,
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

      final syncStartTime = DateTime.now();

      // ── Load remote manifest (lightweight index) ──────────────────
      final manifest = await _loadRemoteManifest(client, remoteRoot);

      // ── Process pending hard deletes ─────────────────────────────
      final pendingRecords =
          await _settingsRepository.loadPendingHardDeleteRecords();
      final processedIds = <String>[];
      for (final raw in pendingRecords) {
        final id = (raw['id'] ?? '') as String;
        final trimmed = id.trim();
        if (trimmed.isEmpty) {
          continue;
        }
        final record = _PendingHardDelete.fromJson(raw);
        try {
          await _writeTombstone(client, remoteRoot, record, manifest);
        } catch (_) {
          continue;
        }
        manifest.entries.remove(trimmed);
        processedIds.add(trimmed);
      }
      if (processedIds.isNotEmpty) {
        final remaining = pendingRecords
            .where((r) => !processedIds.contains(((r['id'] ?? '') as String).trim()))
            .toList();
        await _settingsRepository.savePendingHardDeleteRecords(remaining);
      }

      // ── Build combined entry set (lightweight) ────────────────────
      final localHeads = await _diaryRepository.listSyncHeads();
      final lastSyncAt = await _settingsRepository.loadLastSyncAt();

      // Only load entries that changed since last sync.
      final List<DiaryEntry> changedLocal;
      if (lastSyncAt != null) {
        changedLocal = await _diaryRepository.listUpdatedAfter(lastSyncAt);
      } else {
        changedLocal = await _diaryRepository.listAll();
      }
      final localMap = <String, DiaryEntry>{};
      for (final entry in changedLocal) {
        localMap[entry.id] = entry;
      }

      final allIds = <String>{
        ...localHeads.keys,
        ...manifest.entries.keys,
      };
      final allRawStates = await _settingsRepository.loadEntrySyncStates();
      final syncStates = <String, _SyncState>{};
      for (final id in allIds) {
        syncStates[id] = _parseSyncState(allRawStates, id);
      }

      // ── Collect existing remote files for upload dedup ────────────
      final existingRemoteFiles = await _listRemoteAttachmentFiles(
        client,
        remoteRoot,
      );

      // ── Pre-compute change flags ──────────────────────────────────
      final remoteChangedIds = <String>{};
      final localChangedIds = <String>{};
      final conflictIds = <String>{};

      for (final id in allIds) {
        final local = localMap[id];
        final state = syncStates[id] ?? _SyncState.empty;
        final me = manifest.entries[id];

        if (!localHeads.containsKey(id) && me == null) {
          syncStates.remove(id);
          continue;
        }

        final localChanged = local != null &&
            _contentFingerprint(local) != state.contentFingerprint;
        final remoteChanged = me != null &&
            me.revision != state.lastSyncedRevision;

        if (localChanged) localChangedIds.add(id);
        if (remoteChanged) remoteChangedIds.add(id);
        if (localChanged && remoteChanged) conflictIds.add(id);
      }

      // ── Phase 1: Download remote changes ──────────────────────────
      for (final id in remoteChangedIds) {
        if (conflictIds.contains(id)) continue;

        final me = manifest.entries[id]!;
        final envelope = await _downloadRemoteEntry(client, remoteRoot, me);
        final raw = envelope.entry.toSyncJson()
          ..['attachments'] =
              envelope.entry.attachments.map((a) => a.toJson()).toList();
        DiaryEntry? local = localMap[id];
        if (localHeads.containsKey(id) && local == null) {
          local = await _diaryRepository.getById(id);
        }
        final hydrated = await _materializeRemoteEntry(client, raw, local);
        final readyEntry = DiaryEntry.fromSyncJson(hydrated)
            .copyWith(updatedAt: envelope.updatedAt);
        await _diaryRepository.upsert(readyEntry);
        final refs = _collectAttachmentRefs(envelope.entry);
        manifest.entries[id] = _ManifestEntry(
          id: id,
          path: _entryPath(remoteRoot, id),
          revision: me.revision,
          contentFingerprint: me.contentFingerprint,
          attachmentRefs: refs,
        );
        syncStates[id] = _SyncState(
          lastSyncedRevision: me.revision,
          contentFingerprint: me.contentFingerprint,
        );
        downloaded++;
      }

      // ── Phase 2: Upload local changes ─────────────────────────────
      for (final id in localChangedIds) {
        if (conflictIds.contains(id)) continue;

        final local = localMap[id]!;
        final localFingerprint = _contentFingerprint(local);
        final revision = await _newRevisionString();
        final envelope = await _uploadEntry(
          client,
          remoteRoot,
          local,
          revision: revision,
          existingRemoteFiles: existingRemoteFiles.keys.toSet(),
        );
        final refs = _collectAttachmentRefs(envelope.entry);
        manifest.entries[id] = _ManifestEntry(
          id: id,
          path: _entryPath(remoteRoot, id),
          revision: revision,
          contentFingerprint: envelope.contentFingerprint,
          attachmentRefs: refs,
        );
        syncStates[id] = _SyncState(
          lastSyncedRevision: revision,
          contentFingerprint: localFingerprint,
          lastRemoteUpdatedAt: DateTime.now(),
        );
        uploaded++;
      }

      // Recover local entries missing from manifest (e.g. after corruption)
      for (final id in localHeads.keys) {
        if (manifest.entries.containsKey(id)) continue;
        final state = syncStates[id] ?? _SyncState.empty;
        if (!state.isInitialized) continue;

        final local = localMap[id] ?? await _diaryRepository.getById(id);
        if (local == null) continue;

        final localFingerprint = _contentFingerprint(local);
        final revision = await _newRevisionString();
        final envelope = await _uploadEntry(
          client,
          remoteRoot,
          local,
          revision: revision,
          existingRemoteFiles: existingRemoteFiles.keys.toSet(),
        );
        final refs = _collectAttachmentRefs(envelope.entry);
        manifest.entries[id] = _ManifestEntry(
          id: id,
          path: _entryPath(remoteRoot, id),
          revision: revision,
          contentFingerprint: envelope.contentFingerprint,
          attachmentRefs: refs,
        );
        syncStates[id] = _SyncState(
          lastSyncedRevision: revision,
          contentFingerprint: localFingerprint,
          lastRemoteUpdatedAt: DateTime.now(),
        );
        uploaded++;
      }

      // ── Phase 3: Resolve conflicts ────────────────────────────────
      for (final id in conflictIds) {
        final local = localMap[id]!;
        final me = manifest.entries[id]!;

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
        final envelope = await _downloadRemoteEntry(client, remoteRoot, me);
        final raw = envelope.entry.toSyncJson()
          ..['attachments'] =
              envelope.entry.attachments.map((a) => a.toJson()).toList();
        final hydrated = await _materializeRemoteEntry(client, raw, local);
        final readyEntry = DiaryEntry.fromSyncJson(hydrated)
            .copyWith(updatedAt: envelope.updatedAt);
        await _diaryRepository.upsert(readyEntry);
        final refs = _collectAttachmentRefs(envelope.entry);
        manifest.entries[id] = _ManifestEntry(
          id: id,
          path: _entryPath(remoteRoot, id),
          revision: me.revision,
          contentFingerprint: me.contentFingerprint,
          attachmentRefs: refs,
        );
        syncStates[id] = _SyncState(
          lastSyncedRevision: me.revision,
          contentFingerprint: me.contentFingerprint,
        );
        downloaded++;
      }

      // ── Apply remote tombstones ──────────────────────────────────
      for (final record in manifest.tombstones.values) {
        final id = record.id;
        if (!localHeads.containsKey(id)) {
          continue;
        }
        final state = syncStates[id] ?? _SyncState.empty;
        if (_compareRevision(state.lastSyncedRevision, record.revision) >= 0) {
          continue;
        }
        await _diaryRepository.deleteForever(id);
        await _clearEntrySyncState(id);
        syncStates.remove(id);
      }

      // ── Persist and cleanup ──────────────────────────────────────
      await _saveSyncStates(syncStates);
      await _saveRemoteManifest(client, remoteRoot, manifest);
      await _cleanupRemoteAttachmentGarbage(
        client,
        remoteRoot,
        manifest.entries,
        existingRemoteFiles,
      );
      await _settingsRepository.saveLastSyncAt(syncStartTime);

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
