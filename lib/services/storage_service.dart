import 'dart:io';
import 'dart:typed_data';

import 'package:diary/data/models/diary_entry.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

class StorageService {
  const StorageService();

  Future<Directory> _mediaDir() async {
    final dir = await getApplicationDocumentsDirectory();
    final media = Directory(p.join(dir.path, 'media'));
    if (!await media.exists()) {
      await media.create(recursive: true);
    }
    return media;
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

  Future<String> saveImage(String sourcePath) {
    return _copyToMedia(sourcePath, defaultExt: '.jpg');
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
    final media = await _mediaDir();
    final ext = p.extension(sourceName ?? '').toLowerCase();
    final normalizedExt = ext.isEmpty ? defaultExt : ext;
    final fileName = '${const Uuid().v4()}$normalizedExt';
    final target = File(p.join(media.path, fileName));
    await target.writeAsBytes(bytes, flush: true);
    return target.path;
  }

  Future<String> saveDoodle(Uint8List bytes) async {
    final media = await _mediaDir();
    final fileName = '${const Uuid().v4()}.png';
    final target = File(p.join(media.path, fileName));
    await target.writeAsBytes(bytes, flush: true);
    return target.path;
  }

  Future<int> cleanupOrphanedMedia(List<DiaryEntry> entries) async {
    final media = await _mediaDir();
    final referenced = entries
        .expand((entry) => entry.attachments)
        .map((item) => p.normalize(item.path))
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
}
