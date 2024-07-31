import 'dart:io';

import 'package:path/path.dart';
import 'package:uuid/uuid.dart';

import 'delete.dart';
import 'is.dart';
import 'touch.dart';



/// Creates a temp file and then calls [action].
///
/// Once [action] completes the temporary file will be deleted.
///
/// The [action]s return value [R] is returned from the [withTempFileAsync]
/// function.
///
/// If [create] is true (default true) then the temp file will be
/// created. If [create] is false then just the name will be
/// generated.
///
/// if [pathToTempDir] is passed then the file will be created in that
/// directory otherwise the file will be created in the system
/// temp directory.
///
/// The temp file name will be <uuid>.tmp
/// unless you provide a [suffix] in which
/// case the file name will be <uuid>.<suffix>
Future<R> withTempFileAsync<R>(
  Future<R> Function(String tempFile) action, {
  String? suffix,
  String? pathToTempDir,
  bool create = true,
  bool keep = false,
}) async {
  final tmp = createTempFilename(suffix: suffix, pathToTempDir: pathToTempDir);
  if (create) {
    touch(tmp, create: true);
  }

  R result;
  try {
    result = await action(tmp);
  } finally {
    if (exists(tmp) && !keep) {
      delete(tmp);
    }
  }
  return result;
}



/// Generates a temporary filename in [pathToTempDir]
/// or if inTempDir os not passed then in
/// the system temp directory.
/// The generated filename is is guaranteed to be globally unique.
///
/// This method does NOT create the file.
///
/// The temp file name will be <uuid>.tmp
/// unless you provide a [suffix] in which
/// case the file name will be <uuid>.<suffix>
String createTempFilename({String? suffix, String? pathToTempDir}) {
  var finalsuffix = suffix ?? 'tmp';

  if (!finalsuffix.startsWith('.')) {
    finalsuffix = '.$finalsuffix';
  }
  pathToTempDir ??= Directory.systemTemp.path;
  const uuid = Uuid();
  return '${join(pathToTempDir, uuid.v4())}$finalsuffix';
}

///
/// Resolves the a symbolic link [pathToLink]
/// to the ultimate target path.
///
/// The return path will be canonicalized.
///
/// e.g.
/// ```dart
/// resolveSymLink('/usr/bin/dart) == '/usr/lib/bin/dart'
/// ```
///
/// throws a FileSystemException if the target path does not exist.
String resolveSymLink(String pathToLink) {
  final normalised = canonicalize(pathToLink);

  String resolved;
  if (isDirectory(normalised)) {
    resolved = Directory(normalised).resolveSymbolicLinksSync();
  } else {
    resolved = canonicalize(File(normalised).resolveSymbolicLinksSync());
  }

  return resolved;
}
