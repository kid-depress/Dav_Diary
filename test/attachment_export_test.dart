import 'dart:io';
import 'dart:typed_data';

import 'package:diary/services/storage_service.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

class _SaveDialog extends FilePicker {
  String? target;
  String? suggestedName;

  @override
  Future<String?> saveFile({
    String? dialogTitle,
    String? fileName,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Uint8List? bytes,
    bool lockParentWindow = false,
  }) async {
    suggestedName = fileName;
    return target;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late File source;
  late _SaveDialog picker;
  late FilePicker originalPicker;
  const storage = StorageService();
  final content = List<int>.generate(4096, (index) => index % 256);

  setUpAll(() => FilePicker.platform = _SaveDialog());

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('diary-export-');
    source = File(p.join(directory.path, '附件.bin'));
    await source.writeAsBytes(content);
    originalPicker = FilePicker.platform;
    picker = _SaveDialog();
    FilePicker.platform = picker;
  });

  tearDown(() async {
    FilePicker.platform = originalPicker;
    await directory.delete(recursive: true);
  });

  test('exports the exact bytes and keeps the source', () async {
    picker.target = p.join(directory.path, 'saved.bin');
    expect(await storage.exportAttachment(source.path), picker.target);
    expect(picker.suggestedName, '附件.bin');
    expect(await File(picker.target!).readAsBytes(), content);
    expect(await source.readAsBytes(), content);
  });

  test('cancel does not create or change files', () async {
    expect(await storage.exportAttachment(source.path), isNull);
    expect(await directory.list().length, 1);
    expect(await source.readAsBytes(), content);
  });

  test('saving over the source keeps its contents', () async {
    picker.target = source.path;
    expect(await storage.exportAttachment(source.path), source.path);
    expect(await source.readAsBytes(), content);
  });
}
