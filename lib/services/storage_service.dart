import 'dart:io';
import 'dart:typed_data';

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

  Future<String> saveImage(String sourcePath) async {
    final media = await _mediaDir();
    final ext = p.extension(sourcePath).toLowerCase();
    final fileName = '${const Uuid().v4()}${ext.isEmpty ? '.jpg' : ext}';
    final target = File(p.join(media.path, fileName));
    await File(sourcePath).copy(target.path);
    return target.path;
  }

  Future<String> saveDoodle(Uint8List bytes) async {
    final media = await _mediaDir();
    final fileName = '${const Uuid().v4()}.png';
    final target = File(p.join(media.path, fileName));
    await target.writeAsBytes(bytes, flush: true);
    return target.path;
  }
}
