import 'package:dshell/dshell.dart' hide equals;
import 'package:test/test.dart';

import 'package:settings_yaml/settings_yaml.dart';

void main() {
  test('SettingsYaml fromString', () async {
    var content = '''name: brett
hostname: slayer
port: 10
''';
    var path = '/tmp/settings.yaml';
    var yaml = SettingsYaml.fromString(content: content, filePath: path);
    expect(yaml['name'], equals('brett'));
    expect(yaml['hostname'], equals('slayer'));
    expect(yaml['port'], equals(10));
  });

  test('SettingsYaml fromFile', () async {
    var path = '/tmp/settings.yaml';
    var content = '''name: brett
hostname: slayer
port: 10
coefficient: 8.25
''';
    if (exists(path)) {
      delete(path);
    }
    path.write(content);

    var yaml = SettingsYaml.load(filePath: path);
    expect(yaml['name'], equals('brett'));
    expect(yaml['hostname'], equals('slayer'));
    expect(yaml['port'], equals(10));
    expect(yaml['coefficient'], equals(8.25));
  });

  test('SettingsYaml save', () async {
    var path = '/tmp/settings.yaml';
    var content = '''name: brett
hostname: slayer
port: 10
''';
    if (exists(path)) {
      delete(path);
    }
    path.write(content);

    var yaml = SettingsYaml.fromString(content: content, filePath: path);
    delete(path);
    yaml.save();

    yaml = SettingsYaml.load(filePath: path);
    expect(yaml['name'], equals('brett'));
    expect(yaml['hostname'], equals('slayer'));
    expect(yaml['port'], equals(10));
  });

  test('SettingsYaml load create with no file.', () async {
    var path = '/tmp/settings.yaml';

    if (exists(path)) {
      delete(path);
    }

    var yaml = SettingsYaml.load(filePath: path);
    yaml.save();
  });

  test('SettingsYaml load create with no file and save settings.', () async {
    var path = '/tmp/settings.yaml';

    if (exists(path)) {
      delete(path);
    }

    var yaml = SettingsYaml.load(filePath: path);

    yaml['name'] = 'brett';
    yaml['hostname'] = 'slayer';
    yaml['port'] = 10;
    yaml['coefficient'] = 8.25;

    expect(yaml['name'], equals('brett'));
    expect(yaml['hostname'], equals('slayer'));
    expect(yaml['port'], equals(10));
    expect(yaml['coefficient'], equals(8.25));
    yaml.save();

    // reload saved data and make certain that its intact.
    yaml = SettingsYaml.load(filePath: path);

    expect(yaml['name'], equals('brett'));
    expect(yaml['hostname'], equals('slayer'));
    expect(yaml['port'], equals(10));
  });
}
