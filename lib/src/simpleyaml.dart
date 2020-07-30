import 'dart:io';

import 'package:dshell/dshell.dart';
import 'package:meta/meta.dart';
import 'package:yaml/yaml.dart';

class SimpleYaml {
  YamlDocument _document;
  String filePath;
  var valueMap = <String, dynamic>{};

  SimpleYaml(this.filePath);

  SimpleYaml.fromString({@required String contents, @required this.filePath}) {
    _document = loadYamlDocument(contents);

    var topMap = _document.contents as YamlMap;

    for (var pair in topMap.value.entries) {
      valueMap[pair.key as String] = pair.value;
    }
  }

  static SimpleYaml load({String filePath, bool create = false}) {
    if (!create && !exists(filePath)) {
      throw SimpleYamlException('The yaml file $filePath does not exist');
    }

    var contents = File(filePath).readAsStringSync();

    return SimpleYaml.fromString(contents: contents, filePath: filePath);
  }

  void put(String key, String value) {
    valueMap[key] = value;
  }

  /// Returns the value for the given key
  dynamic operator [](String path) => valueMap[path];

  /// adds a key value piar
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

  void save() {
    var tmp = FileSync.tempFile();
    tmp.write('# SimpleYaml settings file');

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

class SimpleYamlException implements Exception {
  String message;
  SimpleYamlException(this.message);

  @override
  String toString() => message;
}
