import 'package:yaml/yaml.dart';

import 'yaml.dart';

extension YamlListEx on YamlList {
  List<dynamic> toList(YamlList yamlList) {
    var list = <dynamic>[];
    for (var e in yamlList) {
      list.add(convertNode(e));
    }
    return list;
  }
}
