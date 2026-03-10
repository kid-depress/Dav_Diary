import 'dart:io';

import 'package:diary/data/models/diary_entry.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

class StoredAttachmentData {
  const StoredAttachmentData({
    required this.path,
    required this.hash,
    this.thumbnailPath = '',
  });

  final String path;
  final String hash;
  final String thumbnailPath;
}

Future<Map<String, Uint8List>> _processImageInIsolate(
  Map<String, Object> payload,
) async {
  final bytes = payload['bytes'] as Uint8List;
  final maxEdge = (payload['maxEdge'] ?? 2300) as int;
  final thumbEdge = (payload['thumbEdge'] ?? 560) as int;
  final quality = (payload['quality'] ?? 88) as int;
  final thumbQuality = (payload['thumbQuality'] ?? 84) as int;
  final sourceName = (payload['sourceName'] ?? '') as String;

  final decoded = img.decodeImage(bytes);
  if (decoded == null) {
    return <String, Uint8List>{'main': bytes};
  }

  final ext = p.extension(sourceName).toLowerCase();
  final keepPng = ext == '.png';

  final resized = img.copyResize(
    decoded,
    width: decoded.width >= decoded.height ? maxEdge : null,
    height: decoded.height > decoded.width ? maxEdge : null,
    interpolation: img.Interpolation.average,
  );
  final thumb = img.copyResize(
    decoded,
    width: decoded.width >= decoded.height ? thumbEdge : null,
    height: decoded.height > decoded.width ? thumbEdge : null,
    interpolation: img.Interpolation.average,
  );

  final main = keepPng
      ? Uint8List.fromList(img.encodePng(resized, level: 6))
      : Uint8List.fromList(img.encodeJpg(resized, quality: quality));
  final thumbnail = Uint8List.fromList(
    img.encodeJpg(thumb, quality: thumbQuality),
  );

  return <String, Uint8List>{'main': main, 'thumb': thumbnail};
}

class StorageService {
  const StorageService();

  Future<bool> _hasUsableThumbnail(DiaryAttachment attachment) async {
    final thumbPath = attachment.thumbnailPath.trim();
    if (thumbPath.isEmpty) {
      return false;
    }
    return File(thumbPath).exists();
  }

  Future<Directory> _mediaDir() async {
    final dir = await getApplicationDocumentsDirectory();
    final media = Directory(p.join(dir.path, 'media'));
    if (!await media.exists()) {
      await media.create(recursive: true);
    }
    return media;
  }

  Future<Directory> _thumbDir() async {
    final media = await _mediaDir();
    final thumbs = Directory(p.join(media.path, 'thumbs'));
    if (!await thumbs.exists()) {
      await thumbs.create(recursive: true);
    }
    return thumbs;
  }

  Future<String> _copyToMedia(String sourcePath, {String? defaultExt}) async {
    final media = await _mediaDir();
    final ext = p.extension(sourcePath).toLowerCase();
    final normalizedExt = ext.isEmpty ? (defaultExt ?? '.bin') : ext;
    final fileName = '${const Uuid().v4()}$normalizedExt';
    final target = File(p.join(media.path, fileName));
    await File(sourcePath).copy(target.path);
    return target.path;
  }

  Future<StoredAttachmentData> saveImageAttachment(String sourcePath) async {
    final raw = await File(sourcePath).readAsBytes();
    final processed = await compute(_processImageInIsolate, <String, Object>{
      'bytes': raw,
      'sourceName': p.basename(sourcePath),
      'maxEdge': 2300,
      'thumbEdge': 560,
      'quality': 88,
      'thumbQuality': 84,
    });

    final ext = p.extension(sourcePath).toLowerCase();
    final normalizedExt = ext.isEmpty ? '.jpg' : ext;
    final media = await _mediaDir();
    final fileName = '${const Uuid().v4()}$normalizedExt';
    final target = File(p.join(media.path, fileName));
    final mainBytes = processed['main'] ?? raw;
    await target.writeAsBytes(mainBytes, flush: true);

    var thumbPath = '';
    final thumbBytes = processed['thumb'];
    if (thumbBytes != null) {
      final thumbDir = await _thumbDir();
      final thumbName = '${const Uuid().v4()}.jpg';
      final thumbTarget = File(p.join(thumbDir.path, thumbName));
      await thumbTarget.writeAsBytes(thumbBytes, flush: true);
      thumbPath = thumbTarget.path;
    }

    final hash = sha256.convert(mainBytes).toString();
    return StoredAttachmentData(
      path: target.path,
      hash: hash,
      thumbnailPath: thumbPath,
    );
  }

  Future<String> saveImage(String sourcePath) async {
    final saved = await saveImageAttachment(sourcePath);
    return saved.path;
  }

  Future<String> saveAttachment(String sourcePath) {
    return _copyToMedia(sourcePath);
  }

  Future<String?> resolveAttachmentPath(String rawPath) async {
    final trimmed = rawPath.trim();
    if (trimmed.isEmpty) {
      return null;
    }

    final tried = <String>{};

    Future<String?> probe(String candidate) async {
      final normalized = p.normalize(candidate);
      if (!tried.add(normalized)) {
        return null;
      }
      final file = File(normalized);
      if (await file.exists()) {
        return file.path;
      }
      return null;
    }

    final direct = await probe(trimmed);
    if (direct != null) {
      return direct;
    }

    if (trimmed.startsWith('file://')) {
      try {
        final uriPath = Uri.parse(
          trimmed,
        ).toFilePath(windows: Platform.isWindows);
        final fromUri = await probe(uriPath);
        if (fromUri != null) {
          return fromUri;
        }
      } catch (_) {
        // Ignore malformed URI and continue fallback probing.
      }
    }

    if (trimmed.contains('%')) {
      try {
        final decoded = Uri.decodeFull(trimmed);
        final fromDecoded = await probe(decoded);
        if (fromDecoded != null) {
          return fromDecoded;
        }
      } catch (_) {
        // Ignore decode errors and continue fallback probing.
      }
    }

    final media = await _mediaDir();
    final baseName = p.basename(trimmed);
    if (baseName.isNotEmpty) {
      final fromMedia = await probe(p.join(media.path, baseName));
      if (fromMedia != null) {
        return fromMedia;
      }
    }

    return null;
  }

  Future<String> saveAttachmentBytes(
    Uint8List bytes, {
    String? sourceName,
    String defaultExt = '.bin',
  }) async {
    final saved = await saveAttachmentBytesWithThumbnail(
      bytes,
      sourceName: sourceName,
      defaultExt: defaultExt,
      withThumbnail: false,
    );
    return saved.path;
  }

  Future<StoredAttachmentData> saveAttachmentBytesWithThumbnail(
    Uint8List bytes, {
    String? sourceName,
    String defaultExt = '.bin',
    bool withThumbnail = true,
  }) async {
    final media = await _mediaDir();
    final ext = p.extension(sourceName ?? '').toLowerCase();
    final normalizedExt = ext.isEmpty ? defaultExt : ext;
    final fileName = '${const Uuid().v4()}$normalizedExt';
    final target = File(p.join(media.path, fileName));
    await target.writeAsBytes(bytes, flush: true);

    var thumbPath = '';
    final imageLike = const [
      '.jpg',
      '.jpeg',
      '.png',
      '.gif',
      '.webp',
      '.bmp',
      '.heic',
    ].contains(normalizedExt);
    if (withThumbnail && imageLike) {
      final processed = await compute(_processImageInIsolate, <String, Object>{
        'bytes': bytes,
        'sourceName': sourceName ?? '',
        'maxEdge': 2300,
        'thumbEdge': 560,
        'quality': 88,
        'thumbQuality': 84,
      });
      final thumbBytes = processed['thumb'];
      if (thumbBytes != null) {
        final thumbDir = await _thumbDir();
        final thumbName = '${const Uuid().v4()}.jpg';
        final thumbTarget = File(p.join(thumbDir.path, thumbName));
        await thumbTarget.writeAsBytes(thumbBytes, flush: true);
        thumbPath = thumbTarget.path;
      }
    }

    final hash = sha256.convert(bytes).toString();
    return StoredAttachmentData(
      path: target.path,
      hash: hash,
      thumbnailPath: thumbPath,
    );
  }

  Future<StoredAttachmentData> saveDoodleAttachment(Uint8List bytes) async {
    final media = await _mediaDir();
    final fileName = '${const Uuid().v4()}.png';
    final target = File(p.join(media.path, fileName));
    await target.writeAsBytes(bytes, flush: true);

    final processed = await compute(_processImageInIsolate, <String, Object>{
      'bytes': bytes,
      'sourceName': 'doodle.png',
      'maxEdge': 2300,
      'thumbEdge': 560,
      'quality': 88,
      'thumbQuality': 84,
    });
    var thumbPath = '';
    final thumbBytes = processed['thumb'];
    if (thumbBytes != null) {
      final thumbDir = await _thumbDir();
      final thumbName = '${const Uuid().v4()}.jpg';
      final thumbTarget = File(p.join(thumbDir.path, thumbName));
      await thumbTarget.writeAsBytes(thumbBytes, flush: true);
      thumbPath = thumbTarget.path;
    }

    final hash = sha256.convert(bytes).toString();
    return StoredAttachmentData(
      path: target.path,
      hash: hash,
      thumbnailPath: thumbPath,
    );
  }

  Future<String> saveDoodle(Uint8List bytes) async {
    final saved = await saveDoodleAttachment(bytes);
    return saved.path;
  }

  Future<int> cleanupOrphanedMedia(List<DiaryEntry> entries) async {
    final media = await _mediaDir();
    final referenced = entries
        .expand((entry) => entry.attachments)
        .expand((item) => [item.path, item.thumbnailPath])
        .where((item) => item.trim().isNotEmpty)
        .map((item) => p.normalize(item))
        .toSet();

    var removed = 0;
    await for (final entity in media.list()) {
      if (entity is! File) {
        continue;
      }
      final filePath = p.normalize(entity.path);
      if (referenced.contains(filePath)) {
        continue;
      }
      try {
        await entity.delete();
        removed++;
      } catch (_) {
        // ignore file lock or permission failures
      }
    }
    return removed;
  }

  Future<int> cleanupSyncedAttachmentCache(List<DiaryEntry> entries) async {
    var removed = 0;
    for (final entry in entries) {
      for (final attachment in entry.attachments) {
        if (attachment.remotePath.trim().isEmpty ||
            attachment.path.trim().isEmpty) {
          continue;
        }
        // Keep local image file when there is no usable thumbnail,
        // otherwise entry cards can lose preview after cache cleanup.
        if (attachment.isVisualImage &&
            !await _hasUsableThumbnail(attachment)) {
          continue;
        }
        final file = File(attachment.path);
        if (!await file.exists()) {
          continue;
        }
        try {
          await file.delete();
          removed++;
        } catch (_) {
          // ignore file lock or permission failures
        }
      }
    }
    return removed;
  }
}
