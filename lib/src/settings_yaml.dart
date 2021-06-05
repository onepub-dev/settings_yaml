import 'dart:io';

import 'package:path/path.dart';
import 'package:settings_yaml/src/util/file_util.dart';
import 'package:yaml/yaml.dart';

class SettingsYaml {
  YamlDocument? _document;
  String filePath;

  /// The complete map of key/value pairs
  var valueMap = <String, dynamic>{};

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
    if (content.trim().isEmpty) return;

    _document = loadYamlDocument(content);

    if (_document!.contents is YamlMap) {
      var topMap = _document!.contents as YamlMap;

      for (var pair in topMap.value.entries) {
        valueMap[pair.key as String] = pair.value;
      }
    }

    /// else the settings file was empty.
  }

  /// Loads a settings file from the give [pathToSettings].
  ///
  /// If the settings file doesn't exist then it will be created when you call [save].
  ///
  /// The [pathToSettings] must point to a file (not a directory).
  ///
  /// The directory component of [pathToSettings] maybe absolute or relative but
  /// the entire directory path must exist.
  ///
  /// If the parent of [pathToSettings] doesn't exist then a SettingsYamlException will be thrown.
  ///
  static SettingsYaml load({required String pathToSettings}) {
    if (!exists(dirname(pathToSettings))) {
      throw SettingsYamlException(
          'The directory tree above ${truepath(pathToSettings)} does not exist. Create the directory tree and try again.');
    }

    String? contents;
    if (exists(pathToSettings)) {
      contents = File(pathToSettings).readAsStringSync();
    }
    contents ??= '';

    return SettingsYaml.fromString(content: contents, filePath: pathToSettings);
  }

  /// Saves the settings back to the settings file.
  /// To avoid a corrupted file in the event of a crash we first copy the existing
  /// settings file to a .bak file.
  /// If the save fails you may need to manually rename the .bak file.
  void save() {
    var tmp = tempFile();
    write(tmp, '# SettingsYaml settings file');

    for (var pair in valueMap.entries) {
      if (pair.value is String) {
        /// quote the string to ensure it doesn't get interpreted
        /// as a num/bool etc and import.
        append(tmp, '${pair.key}: "${pair.value}"');
      } else {
        append(tmp, '${pair.key}: ${pair.value}');
      }
    }

    /// Do a safe save.
    var back = '$filePath.bak';
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

  /// Returns the value for the given key.
  ///
  /// If the key doesn't exists then null is returned.
  /// ```
  /// var settings = SettingsYaml.load('mysettings.yaml');
  /// var password = settings['password'];
  /// ```
  dynamic operator [](String path) => valueMap[path];

  /// Adds or Updates the given key/value pair.
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

  /// Returns true if the key has a value which is a
  /// String which is non-null and not empty
  bool validString(String key) {
    final value = _document?.contents.value[key];
    return (value != null && value is String && value.isNotEmpty);
  }

  bool validInt(String key) {
    final value = _document?.contents.value[key];
    return (value != null && value is int);
  }

  bool validDouble(String key) {
    final value = _document?.contents.value[key];
    return (value != null && value is double);
  }

  bool validBool(String key) {
    final value = _document?.contents.value[key];
    return (value != null && value is bool);
  }
}

class SettingsYamlException implements Exception {
  String message;
  SettingsYamlException(this.message);

  @override
  String toString() => message;
}
