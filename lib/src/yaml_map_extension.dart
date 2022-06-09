/* Copyright (C) S. Brett Sutton - All Rights Reserved
 * Unauthorized copying of this file, via any medium is strictly prohibited
 * Proprietary and confidential
 * Written by Brett Sutton <bsutton@onepub.dev>, Jan 2022
 */

import 'package:yaml/yaml.dart';

import 'yaml.dart';

extension YamlMapEx on YamlMap {
  Map<String, dynamic> toMap() {
    final map = <String, dynamic>{};
    forEach((dynamic k, dynamic v) {
      if (k is YamlScalar) {
        map[k.value.toString()] = convertNode(v);
      } else {
        map[k.toString()] = convertNode(v);
      }
    });
    return map;
  }
}
