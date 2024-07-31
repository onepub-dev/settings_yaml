import 'dart:io';

/// checks if the given [path] exists.
///
/// Throws [ArgumentError] if [path] is an empty string.
bool exists(String path, {bool followLinks = true}) {
  if (path.isEmpty) {
    throw ArgumentError('path must not be empty.');
  }

  final exists = FileSystemEntity.typeSync(path, followLinks: followLinks) !=
      FileSystemEntityType.notFound;

  return exists;
}

/// true if the given path is a directory.
bool isDirectory(String path) {
  final fromType = FileSystemEntity.typeSync(path);
  return fromType == FileSystemEntityType.directory;
}

bool isLink(String path) {
  final fromType = FileSystemEntity.typeSync(path, followLinks: false);
  return fromType == FileSystemEntityType.link;
}
