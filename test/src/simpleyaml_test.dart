import 'package:dshell/dshell.dart' hide equals;
import 'package:test/test.dart';

import 'package:simpleyaml/simpleyaml.dart';

void main() {
  test('SimpleYaml fromString', () async {
    var content = '''name: brett
hostname: slayer
port: 10
''';
    var path = '/tmp/settings.yaml';
    var yaml = SimpleYaml.fromString(contents: content, filePath: path);
    expect(yaml['name'], equals('brett'));
    expect(yaml['hostname'], equals('slayer'));
    expect(yaml['port'], equals(10));
  });

  test('SimpleYaml fromFile', () async {
    var path = '/tmp/settings.yaml';
    var content = '''name: brett
hostname: slayer
port: 10
''';
    if (exists(path)) {
      delete(path);
    }
    path.write(content);

    var yaml = SimpleYaml.load(filePath: path);
    expect(yaml['name'], equals('brett'));
    expect(yaml['hostname'], equals('slayer'));
    expect(yaml['port'], equals(10));
  });

  test('SimpleYaml save', () async {
    var path = '/tmp/settings.yaml';
    var content = '''name: brett
hostname: slayer
port: 10
''';
    if (exists(path)) {
      delete(path);
    }
    path.write(content);

    var yaml = SimpleYaml.fromString(contents: content, filePath: path);
    delete(path);
    yaml.save();

    yaml = SimpleYaml.load(filePath: path);
    expect(yaml['name'], equals('brett'));
    expect(yaml['hostname'], equals('slayer'));
    expect(yaml['port'], equals(10));
  });
}
