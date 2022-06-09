/* Copyright (C) S. Brett Sutton - All Rights Reserved
 * Unauthorized copying of this file, via any medium is strictly prohibited
 * Proprietary and confidential
 * Written by Brett Sutton <bsutton@onepub.dev>, Jan 2022
 */

import 'package:yaml/yaml.dart';
import 'yaml_map_extension.dart';

dynamic convertNode(dynamic value) {
  if (value is YamlList) {
    return value.toList();
  }

  if (value is YamlMap) {
    return value.toMap();
  }

  return value;
}
