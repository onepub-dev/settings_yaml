/* Copyright (C) S. Brett Sutton - All Rights Reserved
 * Unauthorized copying of this file, via any medium is strictly prohibited
 * Proprietary and confidential
 * Written by Brett Sutton <bsutton@onepub.dev>, Jan 2022
 */

import 'dart:io';

import 'package:path/path.dart';

import '../settings_yaml.dart';
import 'file.dart';
import 'is.dart';
import 'truepath.dart';

///
/// Copies the file [from] to the path [to].
///
/// ```dart
/// copy("/tmp/fred.text", "/tmp/fred2.text", overwrite=true);
/// ```
///
/// [to] may be a directory in which case the [from] filename is
/// used to construct the [to] files full path.
///
/// If [to] is a file then the  file must not exist unless [overwrite]
///  is set to true.
///
/// If [to] is a directory then the directory must exist.
///
/// If [from] is a symlink we copy the file it links to rather than
/// the symlink. This mimics the behaviour of gnu 'cp' command.
///
/// The default for [overwrite] is false.
///
/// If an error occurs a [CopyException] is thrown.

void copy(String from, String to, {bool overwrite = false}) {
  var finalto = to;
  if (isDirectory(finalto)) {
    finalto = join(finalto, basename(from));
  }

  if (!overwrite && exists(finalto, followLinks: false)) {
    throw CopyException(
      'The target file ${truepath(finalto)} already exists.',
    );
  }

  try {
    /// if we are copying a symlink then we copy the file rather than
    /// the symlink as this mimicks gnu 'cp'.
    if (isLink(from)) {
      final resolvedFrom = resolveSymLink(from);
      File(resolvedFrom).copySync(finalto);
    } else {
      File(from).copySync(finalto);
    }
  }
  // we don't care why
  // ignore: avoid_catches_without_on_clauses
  catch (e) {
    /// lets try and improve the message.
    /// We do these checks only on failure
    /// so in the most common case (everything is correct)
    /// we don't waste cycles on unnecessary work.
    if (isDirectory(from)) {
      throw CopyException(
          "The 'from' argument ${truepath(from)} is a directory. "
          'Use copyTree instead.');
    }
    if (!exists(from)) {
      throw CopyException("The 'from' file ${truepath(from)} does not exists.");
    }
    if (!exists(dirname(to))) {
      throw CopyException(
        "The 'to' directory ${truepath(dirname(to))} does not exists.",
      );
    }

    throw CopyException(
      'An error occured copying ${truepath(from)} to ${truepath(finalto)}. '
      'Error: $e',
    );
  }
}

/// Throw when the [copy] function encounters an error.
class CopyException extends SettingsYamlException {
  /// Throw when the [copy] function encounters an error.
  CopyException(super.message);
}
