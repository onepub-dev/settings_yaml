import 'dart:io';

import 'package:dshell/dshell.dart';
import 'package:meta/meta.dart';
import 'package:yaml/yaml.dart';

class SettingsYaml {
  YamlDocument _document;
  String filePath;
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
  SettingsYaml.fromString({@required String content, @required this.filePath}) {
    /// don't try to load an empty settings file. It will end in tears.
    if (content == null || content.trim().isEmpty) return;

    _document = loadYamlDocument(content);

    var topMap = _document.contents as YamlMap;

    for (var pair in topMap.value.entries) {
      valueMap[pair.key as String] = pair.value;
    }
  }

  /// Loads a settings file from the give [filePath].
  /// The [filePath] must point to a file (not a directory).
  /// The directory component of [filePath] maybe absolute or relative but
  /// the entire directory path must exist.
  ///
  /// If the directory tree of [filePath] doesn't exist then a SettingsYamlException will be thrown.
  ///
  /// If you pass [create] = true then if the settings file doesn't already
  /// exist it will be created.
  /// [create] defaults to false.
  ///
  static SettingsYaml load({@required String filePath}) {
    if (!exists(filePath)) {
      if (!exists(dirname(filePath))) {
        throw SettingsYamlException(
            'The directory tree above ${truepath(filePath)} does not exist. Create the directory tree and try again.');
      }
      touch(filePath, create: true);
    }

    var contents = File(filePath).readAsStringSync();

    return SettingsYaml.fromString(content: contents, filePath: filePath);
  }

  // void put(String key, String value) {
  //   valueMap[key] = value;
  // }

  /// Returns the value for the given key
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

  // String operator [](String path) {
  //   var parts = path.split('.');
  //   var len = parts.length;

  //   YamlNode parent;
  //   for (var i = 0; i < len; i++) {
  //     // is this the last part
  //     if (i == len - 1) {
  //       // last part we are after the value.

  //       return parent.value;
  //     }
  //   }

  /// Saves the settings back to the settings file.
  /// To avoid a corrupted file we first copy the existing
  /// settings file to a .bak file.
  /// If the save fails you may need to manually rename the .bak file.
  void save() {
    var tmp = FileSync.tempFile();
    tmp.write('# SettingsYaml settings file');

    for (var pair in valueMap.entries) {
      tmp.append('${pair.key}: ${pair.value}');
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

  /// reads the value of a top level [key].
  ///
  // ignore: unused_element
  String _getValue(String key) {
    if (_document.contents.value == null) {
      return null;
    } else {
      return _document.contents.value[key] as String;
    }
  }

  /// returns a list of elements attached to [key].
  // ignore: unused_element
  YamlList _getList(String key) {
    if (_document.contents.value == null) {
      return null;
    } else {
      return _document.contents.value[key] as YamlList;
    }
  }

  /// returns the map of elements attached to [key].
  // ignore: unused_element
  YamlMap _getMap(String key) {
    if (_document.contents.value == null) {
      return null;
    } else {
      return _document.contents.value[key] as YamlMap;
    }
  }
}

class SettingsYamlException implements Exception {
  String message;
  SettingsYamlException(this.message);

  @override
  String toString() => message;
}
