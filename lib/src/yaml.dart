import 'package:yaml/yaml.dart';
import 'yaml_map_extension.dart';

dynamic convertNode(dynamic value) {
  if (value is YamlList) return value.toList();

  if (value is YamlMap) return value.toMap();

  return value;
}
