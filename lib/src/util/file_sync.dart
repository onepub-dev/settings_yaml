import 'dart:io';

///
/// Provides a set of methods to read/write
/// a file synchronisly.
///
/// The class is mostly used internally.
///
/// Note: the api to this class is considered EXPERIMENTAL
/// and is subject to change.
class FileSync {
  late File _file;
  late RandomAccessFile _raf;

  ///
  FileSync(String path, {FileMode fileMode = FileMode.writeOnlyAppend}) {
    _file = File(path);
    _open(fileMode);
  }

  /// The path to this file.
  String get path => _file.path;

  void _open(FileMode fileMode) {
    _raf = _file.openSync(mode: fileMode);
  }

  ///
  /// Flushes the contents of the file to disk.
  void flush() {
    _raf.flushSync();
  }

  /// Returns the length of the file in bytes
  /// The file does NOT have to be open
  /// to determine its length.
  int get length {
    return _file.lengthSync();
  }

  /// Close and flushes a file to disk.
  void close() {
    _raf.closeSync();
  }

  /// Truncates the file to zero bytes and
  /// then writes the given text to the file.
  /// If [newline] is null then no line terminator will
  /// be added.
  void write(String line, {String newline = '\n'}) {
    line += newline ;
    _raf.truncateSync(0);

    _raf.setPositionSync(0);
    _raf.flushSync();

    _raf.writeStringSync(line);
  }

  /// Appends the [line] to the file
  /// If [newLine] is true then append a newline after the line.
  void append(String line, {String newline = '\n'}) {
    line += newline ;

    _raf.setPositionSync(_raf.lengthSync());
    _raf.writeStringSync(line);
  }

  /// Truncates the file to zero bytes in length.
  void truncate() {
    _raf.truncateSync(0);
  }
}

///
/// Creates a link at [linkPath] which points to an
/// existing file or directory at [existingPath]
///
void symlink(
  String existingPath,
  String linkPath,
) {
  var link = Link(linkPath);
  link.createSync(existingPath);
}

///
/// Deletes the symlink at [linkPath]
///
void deleteSymlink(String linkPath) {
  var link = Link(linkPath);
  link.deleteSync();
}

///
/// Returns a FileStat instance describing the
/// file or directory located by [path].
///
FileStat stat(String path) {
  return File(path).statSync();
}
