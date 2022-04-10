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
