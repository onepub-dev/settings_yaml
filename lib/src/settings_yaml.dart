/* Copyright (C) S. Brett Sutton - All Rights Reserved
 * Unauthorized copying of this file, via any medium is strictly prohibited
 * Proprietary and confidential
 * Written by Brett Sutton <bsutton@onepub.dev>, Jan 2022
 */

// ignore_for_file: avoid_dynamic_calls

import 'dart:io';

import 'package:path/path.dart';
import 'package:yaml/yaml.dart';

import 'util/delete.dart';
import 'util/file.dart';
import 'util/is.dart';
import 'util/line_file.dart';
import 'util/move.dart';
import 'util/truepath.dart';
import 'yaml.dart';
import 'yaml_map_extension.dart';

/// Provides the ability to read/write simply settings stored in a yaml file
/// without having to worry about parsing the yaml file or programatically
/// traversing the yaml tree.
///
/// ```yaml
/// password: xxxx
/// user: xxxx
/// '''
///
/// To obtain the value of password use:
/// ```dart
/// final settings = SettingsYaml.load(pathToSettings: 'path to yaml.yaml');
/// final password = settings.asString['password'];
/// ```
///
/// You can also update an entry:
///
/// ```dart
/// settings['password'] = 'abc123';
/// settings.save();
/// ```
///
/// You can also read attributes stored in a classic yaml hierachy using
/// selectors similar to html xpath selectors.
///
/// A selector path is made of words seperated by periods.
/// e.g.
/// environment.sdk
///
/// You can also craft a selector to access a specific element in
/// a yaml list using the '[]' operators.
///
/// To access a list use 'word[n]' where 'n' is the nth instance of the word
/// in a yaml array.
///
/// e.g.
/// ```
/// one:
///   - two
///   - two
///     three:
///       four: value
/// ```
/// To return the value of four
/// ```dart
/// traverse('one.two[1].three.four') == 'value'
/// ```
class SettingsYaml {
  /// Loads settings from a string.
  /// The [content] must be formatted like a standard yaml file would be:
  ///
  /// ```
  /// var settings = SettingsYaml(content: '''
  /// password: xxxx
  /// user: xxxx
  /// ''', filePath: 'mysettings.yaml');
  /// ```
  ///
  /// The [filePath] is the path/file name that will be used when
  /// save is called.
  SettingsYaml.fromString({required String content, required this.filePath}) {
    /// don't try to load an empty settings file. It will end in tears.
    if (content.trim().isEmpty) {
      return;
    }

    _document = loadYamlDocument(content);

    if (_document!.contents is YamlMap) {
      final topMap = _document!.contents as YamlMap;

      for (final pair in topMap.value.entries) {
        valueMap[pair.key as String] = pair.value;
      }
    }

    /// else the settings file was empty.
  }

  /// Loads a settings file from the give [pathToSettings].
  ///
  /// If the settings file doesn't exist then it will be created
  /// when you call [save].
  ///
  /// The [pathToSettings] must point to a file (not a directory).
  ///
  /// The directory component of [pathToSettings] maybe absolute or relative but
  /// the entire directory path must exist.
  ///
  /// If the parent of [pathToSettings] doesn't exist then a
  /// SettingsYamlException will be thrown.
  ///
  factory SettingsYaml.load({required String pathToSettings}) {
    if (!exists(dirname(pathToSettings))) {
      throw SettingsYamlException(
          'The directory tree above ${truepath(pathToSettings)} does not exist.'
          ' Create the directory tree and try again.');
    }

    String? contents;
    if (exists(pathToSettings)) {
      contents = File(pathToSettings).readAsStringSync();
    }
    contents ??= '';

    return SettingsYaml.fromString(content: contents, filePath: pathToSettings);
  }

  YamlDocument? _document;
  String filePath;

  /// The complete map of key/value pairs
  Map<String, dynamic> valueMap = <String, dynamic>{};

  /// Returns a String list for the top level [key].
  ///
  /// If the key isn't a valid List<String>  then [defaultValue] is returned
  /// Use [validStringList] to determine if the key exists and is
  /// a valid List<String>.
  ///
  /// use selectAsList if you need a list that is not at the top
  /// of the yaml tree.
  List<String> asStringList(String key,
      {List<String> defaultValue = const <String>[]}) {
    if (validStringList(key)) {
      return (valueMap[key] as List<dynamic>).cast<String>();
    } else {
      return defaultValue;
    }
  }

  /// returns the value at the top level [key] as an String.
  /// If the value isn't an String then an exception will be thrown.
  /// If the key isn't a valid String then [defaultValue] is returned
  /// Use [validString] to determine if the key exists and is
  /// a valid String.
  ///
  /// use selectAsString if you need a String that is not at the top
  /// of the yaml tree.
  String asString(String key, {String defaultValue = ''}) =>
      validString(key) ? valueMap[key] as String : defaultValue;

  /// returns the value at at the top level [key] as an bool.
  /// If the value isn't an bool then an exception will be thrown.
  /// If the key isn't a valid bool then [defaultValue] is returned
  /// Use [validBool] to determine if the key exists and is
  /// a valid bool.
  ///
  /// use selectAsBool if you need a bool that is not at the top
  /// of the yaml tree.

  bool asBool(String key, {bool defaultValue = true}) =>
      validBool(key) ? valueMap[key] as bool : defaultValue;

  /// returns the value at at the top level [key] as an int.
  /// If the value isn't an int then an exception will be thrown.
  /// If the key isn't a valid int then [defaultValue] is returned
  /// Use [validInt] to determine if the key exists and is
  /// a valid int.
  int asInt(String key, {int defaultValue = 0}) =>
      validInt(key) ? valueMap[key] as int : defaultValue;

  /// returns the value at at the top level [key] as an double.
  /// If the value isn't an double then an exception will be thrown.
  /// If the key isn't a valid int then [defaultValue] is returned.
  /// Use [validDouble] to determine if the key exists and is
  /// a valid double.
  double asDouble(String key, {double defaultValue = 0.0}) =>
      validDouble(key) ? valueMap[key] as double : defaultValue;

  /// Saves the settings back to the settings file.
  /// To avoid a corrupted file in the event of a crash we first
  /// copy the existing
  /// settings file to a .bak file.
  /// If the save fails you may need to manually rename the .bak file.
  Future<void> save() async {
    final tmp = createTempFilename();

    await withOpenLineFile(tmp, (file) async {
      file.write('# SettingsYaml settings file');

      for (final pair in valueMap.entries) {
        if (pair.value is String) {
          /// quote the string to ensure it doesn't get interpreted
          /// as a num/bool etc and import.
          file.append('${pair.key}: "${pair.value}"');
        } else {
          file.append('${pair.key}: ${pair.value}');
        }
      }
    });

    /// Do a safe save.
    final back = '$filePath.bak';
    if (exists(back)) {
      delete(back);
    }
    if (exists(filePath)) {
      move(filePath, back);
    }
    move(tmp, filePath);
    if (exists(back)) {
      delete(back);
    }
  }

  /// Returns the value for the given top level key.
  ///
  /// If the key doesn't exists then null is returned.
  /// ```
  /// var settings = SettingsYaml.load('mysettings.yaml');
  /// var password = settings['password'];
  /// ```
  dynamic operator [](String key) => _normalizedValue(key);

  /// Adds or Updates the given top level key/value pair.
  ///
  /// The value may be a String or a number (int, double);
  ///
  /// ```
  /// var settings = SettingsYaml.load('mysettings.yaml');
  ///  settings['password'] = 'a new password';
  /// settings.save();
  /// ```
  ///
  void operator []=(String path, dynamic value) => valueMap[path] = value;

  /// reads the value of a top level [key].
  ///
  // ignore: unused_element
  String? _getValue(String key) {
    if (_document?.contents.value == null) {
      return null;
    } else {
      return _document!.contents.value[key] as String?;
    }
  }

  /// returns a list of elements attached to [key].
  // ignore: unused_element
  YamlList? _getList(String key) {
    if (_document?.contents.value == null) {
      return null;
    } else {
      return _document!.contents.value[key] as YamlList?;
    }
  }

  /// returns the map of elements attached to [key].
  // ignore: unused_element
  YamlMap? _getMap(String key) {
    if (_document?.contents.value == null) {
      return null;
    } else {
      return _document!.contents.value[key] as YamlMap?;
    }
  }

  /// Returns true if the top level key has a value which is a
  /// String which is non-null and not empty
  bool validString(String key) {
    final dynamic value = valueMap[key];
    return value != null && value is String && value.isNotEmpty;
  }

  /// Returns true if the top level key has a value which is a
  /// String List which is not empty.
  bool validStringList(String key) {
    final dynamic value = valueMap[key];
    return value != null && value is List<dynamic> && value.isNotEmpty;
  }

  /// Returns true if the top level key has a value which is an
  /// int. Empty or null value returns false.
  bool validInt(String key) {
    final dynamic value = valueMap[key];
    return value != null && value is int;
  }

  /// Returns true if the top level key has a value which is a
  /// double. Empty or null value returns false.
  bool validDouble(String key) {
    final dynamic value = valueMap[key];
    return value != null && value is double;
  }

  /// Returns true if the top level key has a value which is a
  /// bool. Empty or null value returns false.
  bool validBool(String key) {
    final dynamic value = valueMap[key];
    return value != null && value is bool;
  }

  dynamic _normalizedValue(String path) {
    final dynamic value = valueMap[path];

    return convertNode(value);
  }

  /// Returns the String attribute at [path]
  /// See [traverse] for details on the syntax of [path]
  /// Throws a [SettingsYamlException] if
  /// an error occurs reading the selector
  /// Throws a [PathNotFoundException] exception
  /// If the selector doesn't lead to a valid
  /// location.
  String? selectAsString(String path) {
    final dynamic value = traverse(path);
    if (value is! String) {
      throw SettingsYamlException('Expected a String at $path. Found $value');
    }

    return value;
  }

  /// Returns the int attribute at [path]
  /// See [traverse] for details on the syntax of [path]
  /// Throws a [SettingsYamlException] if
  /// an error occurs reading the selector
  /// Throws a [PathNotFoundException] exception
  /// If the selector doesn't lead to a valid
  /// location.
  int? selectAsInt(String path) {
    final dynamic value = traverse(path);
    if (value is! int) {
      throw SettingsYamlException('Expected a int at $path. Found $value');
    }

    return value;
  }

  /// Returns the double attribute at [path]
  /// See [traverse] for details on the syntax of [path]
  /// Throws a [SettingsYamlException] if
  /// an error occurs reading the selector
  /// Throws a [PathNotFoundException] exception
  /// If the selector doesn't lead to a valid
  /// location.
  double? selectAsDouble(String path) {
    final dynamic value = traverse(path);
    if (value is! double) {
      throw SettingsYamlException('Expected a double at $path. Found $value');
    }

    return value;
  }

  /// Returns the boolean attribute at [path]
  /// See [traverse] for details on the syntax of [path]
  /// Throws a [SettingsYamlException] if
  /// an error occurs reading the selector
  /// Throws a [PathNotFoundException] exception
  /// If the selector doesn't lead to a valid
  /// location.
  bool? selectAsBool(String path) {
    final dynamic value = traverse(path);
    if (value is! bool) {
      throw SettingsYamlException('Expected a bool at $path. Found $value');
    }

    return value;
  }

  /// Returns the list  at [path]
  /// See [traverse] for details on the syntax of [path]
  /// Throws a [SettingsYamlException] if
  /// an error occurs reading the selector
  /// Throws a [PathNotFoundException] exception
  /// If the selector doesn't lead to a valid
  /// location.
  List<dynamic>? selectAsList(String path) {
    final dynamic list = traverse(path);
    if (list is! YamlList) {
      throw SettingsYamlException('Expected a list at $path. Found $list');
    }
    return list.toList();
  }

  /// Returns the map at [path]
  /// See [traverse] for details on the syntax of [path]
  /// Throws a [SettingsYamlException] if
  /// an error occurs reading the selector
  /// Throws a [PathNotFoundException] exception
  /// If the selector doesn't lead to a valid
  /// location.
  Map<String, dynamic>? selectAsMap(String path) {
    final dynamic map = traverse(path);
    if (map is! YamlMap) {
      throw SettingsYamlException('Expected a map at $path. Found $map');
    }
    return map.toMap();
  }

  /// Returns true if the given [path] exists in the
  /// settings file.
  bool selectorExists(String path) {
    var valid = true;
    try {
      traverse(path);
    } on PathNotFoundException catch (_, __) {
      valid = false;
    }
    return valid;
  }

  /// Regex to extract the index from an array selector of the form
  // ignore: comment_references
  /// 'word[n]'
  static final _indexRegx = RegExp(r'^(\w*)\[([0-9]*)\]$');
  dynamic traverse(String selector) {
    final parts = selector.split('.');
    var remaining = parts.length;

    dynamic current = _document?.contents.value;

    if (current == null) {
      return PathNotFoundException('$filePath is empty or missing');
    }
    var traversed = '';
    var previousTraversed = '';
    for (final part in parts) {
      previousTraversed = traversed;
      if (traversed.isNotEmpty) {
        traversed += '.$part';
      } else {
        traversed += part;
      }

      if (remaining > 0) {
        if (part.contains('[')) {
          /// we have a list selector of the form 'attribute[n]'
          if (current is! YamlList) {
            throw SettingsYamlException('Expected a map at $traversed');
          }

          final matches = _indexRegx.allMatches(part);
          if (matches.length != 1) {
            throw SettingsYamlException(
                'Expected a index selector e.g. people[1] '
                'in $part at $traversed');
          }

          final key = matches.first.group(1);
          final index = int.parse(matches.first.group(2)!);
          current = current[index];

          if (current.keys.first != key) {
            throw SettingsYamlException('Expected a index selector of '
                '$previousTraversed.${current.keys.first}[$index]. '
                'Found $previousTraversed.$key[$index]');
          }
        } else {
          if (current is! YamlMap) {
            throw SettingsYamlException(
                'As $previousTraversed is a list expected $traversed to be a '
                'list index. e.g $traversed[i]');
          }
          current = current[part];
          if (current == null) {
            throw PathNotFoundException('Invalid path: $traversed');
          }
        }

        remaining--;
      }
    }
    return current;
  }
}

class SettingsYamlException implements Exception {
  SettingsYamlException(this.message);

  String message;

  @override
  String toString() => message;
}

class PathNotFoundException implements SettingsYamlException {
  PathNotFoundException(this.message);

  @override
  String message;

  @override
  String toString() => message;
}
