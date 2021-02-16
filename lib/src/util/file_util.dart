import 'dart:io';

import 'package:path/path.dart';
// ignore: import_of_legacy_library_into_null_safe
import 'package:uuid/uuid.dart';

import 'file_sync.dart';

/// checks if the given [path] exists.
///
/// Throws [ArgumentError] if [path] is null or an empty string.
bool exists(String path, {bool followLinks = false}) {
  if (path.isEmpty) {
    throw ArgumentError('path must not be empty');
  }
  //return FileSystemEntity.existsSync(path);
  return FileSystemEntity.typeSync(path, followLinks: followLinks) !=
      FileSystemEntityType.notFound;
}

/// [truepath] creates an absolute and canonicalize path.
///
/// True path provides a safe and consistent manner for
/// manipulating, accessing and displaying paths.
///
/// Works like [join] in that it concatenates a set of directories
/// into a path.
/// [truepath] then goes on to create an absolute path which
/// is then canonicalize to remove any segments (.. or .).
///
String truepath(String part1,
        [String? part2,
        String? part3,
        String? part4,
        String? part5,
        String? part6,
        String? part7]) =>
    canonicalize(absolute(part1, part2, part3, part4, part5, part6, part7));

void delete(String path) {
  File(path).deleteSync();
}

/// Generates a temporary filename in the system temp directory
/// that is guaranteed to be unique.
///
/// This method does not create the file.
///
/// The temp file name will be <uuid>.tmp
/// unless you provide a [suffix] in which
/// case the file name will be <uuid>.<suffix>
String tempFile({String suffix = 'tmp'}) {
  if (!suffix.startsWith('.')) {
    suffix = '.$suffix';
  }
  var uuid = Uuid();
  return '${join(Directory.systemTemp.path, uuid.v4())}$suffix';
}

void move(String from, String to, {bool overwrite = false}) {
  var dest = to;

  if (isDirectory(to)) {
    dest = join(to, basename(from));
  }

  if (exists(dest) && !overwrite) {
    throw MoveException(
        'The [to] path ${truepath(dest)} already exists. Use overwrite:true ');
  }
  try {
    File(from).renameSync(dest);
  } on FileSystemException catch (e) {
    if (e.osError != null && e.osError!.errorCode == 18) {
      /// Invalid cross-device link
      /// We can't move files across a partition so
      /// do a copy/delete.
      copy(from, to, overwrite: overwrite);
      delete(from);
    } else {
      throw MoveException(
          'The Move of ${truepath(from??'null')} to ${truepath(dest??'null')} failed. Error $e');
    }
  }
  // ignore: avoid_catches_without_on_clauses
  catch (e) {
    throw MoveException(
        'The Move of ${truepath(from??'null')} to ${truepath(dest??'null')} failed. Error $e');
  }
}

void copy(String from, String to, {bool overwrite = false}) {
  if (isDirectory(to)) {
    to = join(to, basename(from));
  }

  if (overwrite == false && exists(to)) {
    throw CopyException('The target file ${absolute(to)} already exists');
  }

  try {
    File(from).copySync(to);
  }
  // ignore: avoid_catches_without_on_clauses
  catch (e) {
    throw CopyException(
        'An error occured copying ${absolute(from)} to ${absolute(to)}. Error: $e');
  }
}

/// true if the given path is a directory.
bool isDirectory(String path) {
  var fromType = FileSystemEntity.typeSync(path);
  return (fromType == FileSystemEntityType.directory);
}

/// Truncates and Writes [line] to the file terminated by [newline].
/// [newline] defaults to '\n'.
///
/// e.g.
/// ```dart
/// '/tmp/log'.write('Start of Log')
/// ```
///
/// See [append] appends a line to an existing file.
void write(String path, String line, {String newline = '\n'}) {
  var sink = FileSync(path);
  sink.write(line, newline: newline);
  sink.close();
}

/// Treat [this] String  as the name of a file
/// and append [line] to the file.
/// If [newline] is true add a newline after the line.
///
/// e.g.
/// ```dart
/// '.bashrc'.append('export FRED=ONE');
/// ```
///
void append(String path, String line, {String newline = '\n'}) {
  var sink = FileSync(path);
  sink.append(line, newline: newline);
  sink.close();
}

/// Thrown when the [move] function encouters an error.
class MoveException implements Exception {
  late String message;

  /// Thrown when the [move] function encouters an error.
  MoveException(String message);

  @override
  String toString() => message;
}

/// Thrown when the [move] function encouters an error.
class CopyException implements Exception {
  late String message;

  /// Thrown when the [move] function encouters an error.
  CopyException(String message);

  @override
  String toString() => message;
}
