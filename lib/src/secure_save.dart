import 'dart:io';

import 'package:path/path.dart' as p;

import 'secure_save_posix.dart';
import 'secure_save_windows.dart';
import 'settings_yaml.dart';

/// Requires a trusted parent directory and no concurrent path manipulation.
void secureSave(String path, String content) {
  final destination = File(p.absolute(path));
  final type = FileSystemEntity.typeSync(destination.path, followLinks: false);
  if (type != FileSystemEntityType.notFound &&
      type != FileSystemEntityType.file) {
    throw SettingsYamlException('Save destination must be a regular file.');
  }
  if (Platform.isWindows) {
    secureSaveWindows(destination.path, content);
  } else if (Platform.isLinux || Platform.isMacOS) {
    secureSavePosix(destination.path, content);
  } else {
    throw SettingsYamlException('Unsupported operating system.');
  }
}
