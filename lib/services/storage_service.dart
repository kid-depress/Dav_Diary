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
