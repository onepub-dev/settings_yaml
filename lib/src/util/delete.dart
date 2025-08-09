/* Copyright (C) S. Brett Sutton - All Rights Reserved
 * Unauthorized copying of this file, via any medium is strictly prohibited
 * Proprietary and confidential
 * Written by Brett Sutton <bsutton@onepub.dev>, Jan 2022
 */

import 'dart:io';

import '../../settings_yaml.dart';
import 'is.dart';
import 'truepath.dart';

///
/// Deletes the file at [path].
///
/// If the file does not exists a DeleteException is thrown.
///
/// ```dart
/// delete("/tmp/test.fred", ask: true);
/// ```
///
/// If the [path] is a directory a DeleteException is thrown.
  void delete(String path) {

    if (!exists(path)) {
      throw DeleteException('The path ${truepath(path)} does not exists.');
    }

    if (isDirectory(path)) {
      throw DeleteException('The path ${truepath(path)} is a directory.');
    }

    try {
      File(path).deleteSync();
    }
    // we dont' care why
    // ignore: avoid_catches_without_on_clauses
    catch (e) {
      throw DeleteException(
        'An error occured deleting ${truepath(path)}. Error: $e',
      );
    }
  }

  /// Thrown when the [delete] function encounters an error
class DeleteException extends SettingsYamlException {
  /// Thrown when the [delete] function encounters an error
  DeleteException(super.message);
}
