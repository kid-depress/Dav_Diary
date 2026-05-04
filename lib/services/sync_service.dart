import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:diary/data/models/diary_entry.dart';
import 'package:diary/data/models/webdav_config.dart';
import 'package:diary/data/repositories/diary_repository.dart';
import 'package:diary/data/repositories/settings_repository.dart';
import 'package:diary/services/storage_service.dart';
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

class _SyncClock {
  const _SyncClock({required this.wallTimeMs, required this.counter});

  final int wallTimeMs;
  final int counter;
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
    final revision =
        state.lastSyncedRevision.trim().isNotEmpty
            ? state.lastSyncedRevision
            : _newRevisionString();
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

  String _contentFingerprint(DiaryEntry entry) {
    final attachments = entry.attachments
        .map((attachment) => <String, dynamic>{
              'caption': attachment.caption,
              'type': attachment.type.name,
              'hash': attachment.hash,
              'remotePath': attachment.remotePath,
              'thumbnailRemotePath': attachment.thumbnailRemotePath,
            })
        .toList()
      ..sort((a, b) {
        final left = jsonEncode(a);
        final right = jsonEncode(b);
        return left.compareTo(right);
      });
    final payload = <String, dynamic>{
      'id': entry.id,
      'title': entry.title,
      'deltaJson': entry.deltaJson,
      'plainText': entry.plainText,
      'createdAt': entry.createdAt.toIso8601String(),
      'updatedAt': entry.updatedAt.toIso8601String(),
      'eventAt': entry.eventAt.toIso8601String(),
      'mood': entry.mood,
      'weather': entry.weather,
      'location': entry.location,
      'attachments': attachments,
      'isDeleted': entry.isDeleted,
    };
    return sha256.convert(utf8.encode(jsonEncode(payload))).toString();
  }

  Future<String> _deviceId() async {
    final existing = await _settingsRepository.loadSyncDeviceId();
    if (existing.isNotEmpty) {
      return existing;
    }
    final created = const Uuid().v4();
    await _settingsRepository.saveSyncDeviceId(created);
    return created;
  }

  Future<_SyncClock> _loadClock() async {
    final raw = await _settingsRepository.loadSyncClock();
    return _SyncClock(
      wallTimeMs: (raw['wallTimeMs'] ?? 0) as int,
      counter: (raw['counter'] ?? 0) as int,
    );
  }

  Future<_Revision> _nextRevision() async {
    final deviceId = await _deviceId();
    final existing = await _loadClock();
    final wallTimeMs = DateTime.now().millisecondsSinceEpoch;
    final nextWallTime =
        wallTimeMs > existing.wallTimeMs ? wallTimeMs : existing.wallTimeMs;
    final counter = existing.counter + 1;
    await _settingsRepository.saveSyncClock(
      wallTimeMs: nextWallTime,
      counter: counter,
    );
    return _Revision(
      deviceId: deviceId,
      counter: counter,
      wallTimeMs: nextWallTime,
    );
  }

  String _newRevisionString() {
    final wallTimeMs = DateTime.now().millisecondsSinceEpoch;
    return '$wallTimeMs:1:${const Uuid().v4()}';
  }

  int _compareRevision(String left, String right) {
    final a = _Revision.decode(left);
    final b = _Revision.decode(right);
    if (a.wallTimeMs != b.wallTimeMs) {
      return a.wallTimeMs.compareTo(b.wallTimeMs);
    }
    if (a.counter != b.counter) {
      return a.counter.compareTo(b.counter);
    }
    return a.deviceId.compareTo(b.deviceId);
  }

  bool _sameLogicalChange(String leftRevision, String rightRevision) {
    return leftRevision.trim().isNotEmpty &&
        rightRevision.trim().isNotEmpty &&
        leftRevision.trim() == rightRevision.trim();
  }

  Future<Map<String, _SyncState>> _loadSyncStates() async {
    final raw = await _settingsRepository.loadEntrySyncStates();
    final result = <String, _SyncState>{};
    raw.forEach((key, value) {
      if (value is Map<String, dynamic>) {
        result[key] = _SyncState.fromJson(value);
      }
    });
    return result;
  }

  Future<void> _saveSyncStates(Map<String, _SyncState> states) async {
    final payload = <String, dynamic>{};
    states.forEach((key, value) {
      if (value.isInitialized) {
        payload[key] = value.toJson();
      }
    });
    await _settingsRepository.saveEntrySyncStates(payload);
  }

  Future<_SyncState> _loadSyncStateForEntry(String id) async {
    final states = await _loadSyncStates();
    return states[id] ?? _SyncState.empty;
  }

  Future<void> _clearEntrySyncState(String id) async {
    final states = await _loadSyncStates();
    if (states.remove(id) != null) {
      await _saveSyncStates(states);
    }
  }

  Future<List<_PendingHardDelete>> _loadPendingHardDeletes() async {
    final raw = await _settingsRepository.loadPendingHardDeleteRecords();
    return raw.map(_PendingHardDelete.fromJson).toList();
  }

  Future<void> _savePendingHardDeletes(List<_PendingHardDelete> records) {
    return _settingsRepository.savePendingHardDeleteRecords(
      records.map((record) => record.toJson()).toList(),
    );
  }

  Future<void> _upsertPendingHardDeletes(List<_PendingHardDelete> records) async {
    final existing = await _loadPendingHardDeletes();
    final byId = <String, _PendingHardDelete>{};
    for (final item in existing) {
      byId[item.id] = item;
    }
    for (final item in records) {
      final current = byId[item.id];
      if (current == null ||
          _compareRevision(item.revision, current.revision) >= 0) {
        byId[item.id] = item;
      }
    }
    await _savePendingHardDeletes(byId.values.toList());
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

  Future<SyncResult> syncNow() async {
    final config = await _settingsRepository.loadWebDavConfig();
    if (!config.isConfigured) {
      return const SyncResult(success: false, message: '请先完成 WebDAV 配置');
    }

    final client = _buildClient(config);
    final remoteRoot = _normalizeDir(config.remoteDir);
    int uploaded = 0;
    int downloaded = 0;
    int conflicts = 0;

    try {
      await client.ping();
      await _ensureRemoteLayout(client, remoteRoot);

      final localEntries = await _diaryRepository.listAll();
      final localById = <String, DiaryEntry>{
        for (final entry in localEntries) entry.id: entry,
      };
      final syncStates = await _loadSyncStates();
      final remote = await _loadRemoteSnapshot(client, remoteRoot);

      final pendingDeletes = await _loadPendingHardDeletes();
      final remainingDeletes = <_PendingHardDelete>[];
      for (final record in pendingDeletes) {
        final remoteTombstone = remote.tombstones[record.id];
        if (remoteTombstone == null ||
            _compareRevision(record.revision, remoteTombstone.payload.revision) > 0) {
          await _writeTombstone(client, remoteRoot, record);
          remote.tombstones[record.id] = _RemoteFile<_TombstoneRecord>(
            path: _tombstonePath(remoteRoot, record.id),
            payload: _TombstoneRecord(
              id: record.id,
              revision: record.revision,
              deletedAt: record.deletedAt,
              targetRevision: record.targetRevision,
            ),
            modifiedAt: record.deletedAt,
            eTag: '',
          );
        }
        remote.entries.remove(record.id);
      }
      await _savePendingHardDeletes(remainingDeletes);

      for (final entry in localEntries) {
        final localFingerprint = _contentFingerprint(entry);
        final localState = syncStates[entry.id] ?? _SyncState.empty;
        final remoteEntry = remote.entries[entry.id];
        final remoteTombstone = remote.tombstones[entry.id];
        final remoteRevision = remoteEntry?.payload.revision ?? '';
        final tombstoneRevision = remoteTombstone?.payload.revision ?? '';
        final remoteDeletionWins =
            remoteTombstone != null &&
            _compareRevision(tombstoneRevision, remoteRevision) >= 0;

        final localDirty =
            localState.contentFingerprint.trim() != localFingerprint ||
            remoteEntry == null;

        if (remoteDeletionWins) {
          if (!localDirty ||
              _sameLogicalChange(
                localState.lastSyncedRevision,
                remoteTombstone.payload.targetRevision,
              )) {
            await _diaryRepository.deleteForever(entry.id);
            syncStates.remove(entry.id);
            localById.remove(entry.id);
            downloaded++;
            continue;
          }

          if (config.conflictStrategy == ConflictStrategy.keepBoth) {
            await _diaryRepository.upsert(
              entry.copyWith(
                id: const Uuid().v4(),
                title: '${entry.title} (冲突副本)',
                updatedAt: DateTime.now(),
                isDeleted: false,
              ),
            );
            conflicts++;
          }
          continue;
        }

        if (remoteEntry != null) {
          final remoteFingerprint = remoteEntry.payload.contentFingerprint;
          final sameRevision = _sameLogicalChange(
            localState.lastSyncedRevision,
            remoteEntry.payload.revision,
          );
          final remoteChanged = !sameRevision;

          if (localDirty && remoteChanged) {
            if (config.conflictStrategy == ConflictStrategy.keepBoth) {
              await _diaryRepository.upsert(
                entry.copyWith(
                  id: const Uuid().v4(),
                  title: '${entry.title} (冲突副本)',
                  updatedAt: DateTime.now(),
                  isDeleted: false,
                ),
              );
              conflicts++;
            }
            final hydratedMap = await _materializeRemoteEntry(
              client,
              remoteEntry.payload.toJson(),
              entry,
            );
            final remoteMaterialized = DiaryEntry.fromSyncJson(hydratedMap);
            await _diaryRepository.upsert(remoteMaterialized);
            syncStates[entry.id] = _SyncState(
              lastSyncedRevision: remoteEntry.payload.revision,
              contentFingerprint:
                  remoteFingerprint.isNotEmpty
                      ? remoteFingerprint
                      : _contentFingerprint(remoteMaterialized),
              lastRemoteUpdatedAt: remoteEntry.payload.updatedAt,
              lastRemoteDeletedAt: null,
            );
            downloaded++;
            continue;
          }

          if (remoteChanged || await _needsAttachmentHydration(entry)) {
            final hydratedMap = await _materializeRemoteEntry(
              client,
              remoteEntry.payload.toJson(),
              entry,
            );
            final remoteMaterialized = DiaryEntry.fromSyncJson(hydratedMap);
            await _diaryRepository.upsert(remoteMaterialized);
            syncStates[entry.id] = _SyncState(
              lastSyncedRevision: remoteEntry.payload.revision,
              contentFingerprint:
                  remoteFingerprint.isNotEmpty
                      ? remoteFingerprint
                      : _contentFingerprint(remoteMaterialized),
              lastRemoteUpdatedAt: remoteEntry.payload.updatedAt,
              lastRemoteDeletedAt: null,
            );
            downloaded++;
            continue;
          }
        }

        if (!localDirty) {
          continue;
        }

        final revision = (await _nextRevision()).encode();
        final uploadedEntry = await _uploadEntry(
          client,
          remoteRoot,
          entry,
          revision: revision,
        );
        await _diaryRepository.upsert(uploadedEntry.entry);
        await client.remove(_tombstonePath(remoteRoot, entry.id));
        remote.entries[entry.id] = _RemoteFile<_EntryEnvelope>(
          path: _entryPath(remoteRoot, entry.id),
          payload: uploadedEntry,
          modifiedAt: uploadedEntry.updatedAt,
          eTag: '',
        );
        remote.tombstones.remove(entry.id);
        syncStates[entry.id] = _SyncState(
          lastSyncedRevision: revision,
          contentFingerprint: uploadedEntry.contentFingerprint,
          lastRemoteUpdatedAt: uploadedEntry.updatedAt,
          lastRemoteDeletedAt: null,
        );
        uploaded++;
      }

      for (final remoteEntry in remote.entries.values) {
        if (localById.containsKey(remoteEntry.payload.entry.id)) {
          continue;
        }
        final remoteTombstone = remote.tombstones[remoteEntry.payload.entry.id];
        if (remoteTombstone != null &&
            _compareRevision(
                  remoteTombstone.payload.revision,
                  remoteEntry.payload.revision,
                ) >=
                0) {
          continue;
        }
        final hydratedMap = await _materializeRemoteEntry(
          client,
          remoteEntry.payload.toJson(),
          null,
        );
        final remoteMaterialized = DiaryEntry.fromSyncJson(hydratedMap);
        await _diaryRepository.upsert(remoteMaterialized);
        syncStates[remoteMaterialized.id] = _SyncState(
          lastSyncedRevision: remoteEntry.payload.revision,
          contentFingerprint:
              remoteEntry.payload.contentFingerprint.isNotEmpty
                  ? remoteEntry.payload.contentFingerprint
                  : _contentFingerprint(remoteMaterialized),
          lastRemoteUpdatedAt: remoteEntry.payload.updatedAt,
          lastRemoteDeletedAt: null,
        );
        downloaded++;
      }

      await _saveSyncStates(syncStates);
      await _cleanupRemoteAttachmentGarbage(client, remoteRoot, remote.entries);
      final now = DateTime.now();
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
