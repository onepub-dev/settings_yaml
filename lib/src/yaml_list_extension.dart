/* Copyright (C) S. Brett Sutton - All Rights Reserved
 * Unauthorized copying of this file, via any medium is strictly prohibited
 * Proprietary and confidential
 * Written by Brett Sutton <bsutton@onepub.dev>, Jan 2022
 */

import 'package:yaml/yaml.dart';

import 'yaml.dart';

extension YamlListEx on YamlList {
  List<dynamic> toList(YamlList yamlList) {
    final list = <dynamic>[];
    for (final e in yamlList) {
      list.add(convertNode(e));
    }
    return list;
  }
}
