/* Copyright (C) S. Brett Sutton - All Rights Reserved
 * Unauthorized copying of this file, via any medium is strictly prohibited
 * Proprietary and confidential
 * Written by Brett Sutton <bsutton@onepub.dev>, Jan 2022
 */

import 'dart:collection';
import 'dart:convert';

import 'package:yaml/yaml.dart';

import 'settings_yaml.dart';

/// Copies supported values with budgets on expanded output, including aliases.
dynamic convertNode(dynamic value) =>
    _Conversion(preserveMutable: true).convert(value, 0);

/// One shared key budget for every map visited by a selector.
class SelectorKeys {
  final _conversion = _Conversion(preserveMutable: true);

  String key(dynamic value) => _conversion.key(value, 0);

  dynamic convertValue(dynamic value, {bool normalizeMaps = false}) =>
      _conversion.convert(value, 0, normalizeMaps: normalizeMaps);

  dynamic resolve(Map<dynamic, dynamic> map, String key) {
    final keys = <String>{};
    dynamic result;
    for (final entry in map.entries) {
      final normalized = _conversion.key(entry.key, 0);
      if (!keys.add(normalized)) {
        throw SettingsYamlException(
            'Settings keys collide after normalization.');
      }
      if (normalized == key) {
        result = entry.value;
      }
    }
    return result;
  }
}

/// Normalizes only keys, sharing one budget across the whole map.
Map<String, dynamic> normalizeMapKeys(Map<dynamic, dynamic> map) {
  final conversion = _Conversion();
  final result = <String, dynamic>{};
  for (final entry in map.entries) {
    final normalized = conversion.key(entry.key, 1);
    if (result.containsKey(normalized)) {
      throw SettingsYamlException('Settings keys collide after normalization.');
    }
    result[normalized] = entry.value;
  }
  return result;
}

String serializeSettings(Map<String, dynamic> values) {
  final normalized = _Conversion().convert(values, 0);
  // JSON flow syntax is YAML syntax. Escape YAML-specific line separators too.
  final buffer = StringBuffer();
  for (final unit in jsonEncode(normalized).codeUnits) {
    if ((unit >= 0x7f && unit <= 0x9f) ||
        unit == 0x2028 ||
        unit == 0x2029 ||
        unit == 0xfffe ||
        unit == 0xffff) {
      buffer.write('\\u${unit.toRadixString(16).padLeft(4, '0')}');
    } else {
      buffer.writeCharCode(unit);
    }
  }
  final encoded = buffer.toString();
  if (encoded.length > 8 * 1024 * 1024) {
    throw SettingsYamlException('Settings serialized output exceeds 8 MiB.');
  }
  return '# SettingsYaml settings file\n$encoded\n';
}

class _Conversion {
  _Conversion({this.preserveMutable = false});

  final bool preserveMutable;
  final Set<Object> _active = HashSet<Object>.identity();
  var _nodes = 0;
  var _text = 0;

  String key(dynamic value, int depth) {
    final dynamic scalar = value is YamlScalar ? value.value : value;
    if (scalar != null &&
        scalar is! String &&
        scalar is! bool &&
        scalar is! int &&
        !(scalar is double && scalar.isFinite)) {
      throw SettingsYamlException('Unsupported settings key type.');
    }
    return convert(scalar.toString(), depth) as String;
  }

  dynamic convert(dynamic value, int depth, {bool normalizeMaps = false}) {
    if (++_nodes > 10000 || depth > 64) {
      throw SettingsYamlException('Settings exceed the traversal budget.');
    }
    if (value is String) {
      _text += value.length;
      if (_text > 1024 * 1024) {
        throw SettingsYamlException('Settings exceed the string budget.');
      }
      for (var i = 0; i < value.length; i++) {
        final unit = value.codeUnitAt(i);
        if (unit >= 0xd800 && unit <= 0xdbff) {
          if (++i >= value.length ||
              value.codeUnitAt(i) < 0xdc00 ||
              value.codeUnitAt(i) > 0xdfff) {
            throw SettingsYamlException('Unpaired UTF-16 surrogate.');
          }
        } else if (unit >= 0xdc00 && unit <= 0xdfff) {
          throw SettingsYamlException('Unpaired UTF-16 surrogate.');
        }
      }
      return value;
    }
    if (value == null || value is bool || value is int) {
      return value;
    }
    if (value is double && value.isFinite) {
      return value;
    }
    if (value is! Map && value is! List) {
      throw SettingsYamlException('Unsupported settings value type.');
    }
    if (!_active.add(value as Object)) {
      throw SettingsYamlException('Cyclic settings values are unsupported.');
    }
    try {
      if (value is List) {
        final result = <dynamic>[
          for (final dynamic item in value)
            convert(item, depth + 1, normalizeMaps: normalizeMaps)
        ];
        return preserveMutable && !normalizeMaps && value is! YamlList
            ? value
            : result;
      }
      final result = <String, dynamic>{};
      for (final entry in (value as Map).entries) {
        final normalized = key(entry.key, depth + 1);
        if (result.containsKey(normalized)) {
          throw SettingsYamlException(
              'Settings keys collide after normalization.');
        }
        result[normalized] =
            convert(entry.value, depth + 1, normalizeMaps: normalizeMaps);
      }
      return preserveMutable && !normalizeMaps && value is! YamlMap
          ? value
          : result;
    } finally {
      _active.remove(value);
    }
  }
}
