import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Desktop data belongs in the application's own directory, rather than in
/// shared Documents. Keep the existing mobile location for installed users.
Future<Directory> getDiaryDataDirectory() async {
  final directory = Platform.isWindows
      ? await getApplicationSupportDirectory()
      : await getApplicationDocumentsDirectory();
  await directory.create(recursive: true);
  return directory;
}
