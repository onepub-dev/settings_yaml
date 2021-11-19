import 'package:collection/collection.dart';
import 'package:dcli/dcli.dart' hide equals;
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

  test('casting', () async {
    var content = '''name: brett
string: slayer
int: 10
double: 10.1
bool: true
''';
    var path = '/tmp/settings.yaml';
    var yaml = SettingsYaml.fromString(content: content, filePath: path);
    expect(yaml.asString('string'), equals('slayer'));
    expect(yaml.asInt('int'), equals(10));
    expect(yaml.asDouble('double'), equals(10.1));
    expect(yaml.asBool('bool'), isTrue);
  });

  test('SettingsYaml String list', () async {
    var content = '''name: brett
hostnames: [one, two, three]
''';
    var path = '/tmp/settings.yaml';
    var yaml = SettingsYaml.fromString(content: content, filePath: path);
    expect(yaml['hostnames'], equals(['one', 'two', 'three']));

    withTempFile((pathTo) {
      var yaml = SettingsYaml.load(pathToSettings: pathTo);
      yaml['list'] = <String>['one', 'two', 'three'];
      yaml.save();

      yaml = SettingsYaml.load(pathToSettings: pathTo);

      expect(yaml['list'], equals(['one', 'two', 'three']));

      List<String> numbers = (yaml['list'] as List<dynamic>).cast<String>();
      expect(numbers, equals(['one', 'two', 'three']));

      List<String> atsAsString = yaml.asStringList('list');
      expect(atsAsString, equals(['one', 'two', 'three']));
    });
  });

  test('SettingsYaml String map', () async {
    var content = '''name: brett
hostnames: 
  host1: one
  host2: two
  host3: three
''';
    var path = '/tmp/settings.yaml';
    var yaml = SettingsYaml.fromString(content: content, filePath: path);
    expect(
        MapEquality().equals(yaml['hostnames'],
            {'host1': 'one', 'host2': 'two', 'host3': 'three'}),
        isTrue);

    withTempFile((pathTo) {
      var yaml = SettingsYaml.load(pathToSettings: pathTo);
      yaml['map'] = <String, String>{
        'host1': 'one',
        'host2': 'two',
        'host3': 'three'
      };
      yaml.save();

      yaml = SettingsYaml.load(pathToSettings: pathTo);

      expect(
          MapEquality().equals(
              yaml['map'], {'host1': 'one', 'host2': 'two', 'host3': 'three'}),
          isTrue);
    });
  });

  test('SettingsYaml fromString - empty content', () async {
    var content = '';
    var path = '/tmp/settings.yaml';
    var yaml = SettingsYaml.fromString(content: content, filePath: path);
    expect(yaml['name'], isNull);
    expect(yaml.validString('username'), false);
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

    var yaml = SettingsYaml.load(pathToSettings: path);
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

    yaml = SettingsYaml.load(pathToSettings: path);
    expect(yaml['name'], equals('brett'));
    expect(yaml['hostname'], equals('slayer'));
    expect(yaml['port'], equals(10));
  });

  test('SettingsYaml load create with no file.', () async {
    var path = '/tmp/settings.yaml';

    if (exists(path)) {
      delete(path);
    }

    var yaml = SettingsYaml.load(pathToSettings: path);
    yaml.save();
  });

  test('SettingsYaml load create with no file and save settings.', () async {
    var path = '/tmp/settings.yaml';

    if (exists(path)) {
      delete(path);
    }

    var yaml = SettingsYaml.load(pathToSettings: path);

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
    yaml = SettingsYaml.load(pathToSettings: path);

    expect(yaml['name'], equals('brett'));
    expect(yaml['hostname'], equals('slayer'));
    expect(yaml['port'], equals(10));
  });

  test('SettingsYaml validXXX', () async {
    var path = '/tmp/settings.yaml';
    var content = '''name: brett
hostname: slayer
port: 10
active: true
volume: 10.0
''';

    var yaml = SettingsYaml.fromString(content: content, filePath: path);

    expect(yaml.validString('name'), equals(true));

    expect(yaml.validString('hostname'), equals(true));
    expect(yaml.validInt('hostname'), equals(false));
    expect(yaml.validDouble('hostname'), equals(false));
    expect(yaml.validBool('hostname'), equals(false));

    /// Int
    expect(yaml.validInt('port'), equals(true));

    expect(yaml.validString('port'), equals(false));
    expect(yaml.validDouble('port'), equals(false));
    expect(yaml.validBool('port'), equals(false));

    /// double
    expect(yaml.validDouble('volume'), equals(true));

    expect(yaml.validString('volume'), equals(false));
    expect(yaml.validInt('volume'), equals(false));
    expect(yaml.validBool('volume'), equals(false));

    /// Bool
    expect(yaml.validBool('active'), equals(true));

    expect(yaml.validString('active'), equals(false));
    expect(yaml.validInt('active'), equals(false));
    expect(yaml.validDouble('active'), equals(false));

    /// non- existant key
    expect(yaml.validString('badkey'), equals(false));
  });

  test('default Values - good content', () async {
    var path = '/tmp/settings.yaml';

    var goodContent = '''name: brett
hostname: slayer
port: 10
active: true
volume: 10.1
imageid: "65385002e970"
list: [one, two, three]
''';

    var yaml = SettingsYaml.fromString(content: goodContent, filePath: path);

    expect(yaml.validString('hostname'), equals(true));
    expect(yaml.validInt('port'), equals(true));
    expect(yaml.validBool('active'), equals(true));
    expect(yaml.validDouble('volume'), equals(true));
    expect(yaml.validString('imageid'), equals(true));
    expect(yaml.validStringList('list'), equals(true));

    expect(yaml.asString('hostname'), equals('slayer'));
    expect(yaml.asInt('port'), equals(10));
    expect(yaml.asBool('active'), isTrue);
    expect(yaml.asDouble('volume'), equals(10.1));
    expect(yaml.asString('imageid'), equals("65385002e970"));
    expect(yaml.asStringList('list'), equals(['one', 'two', 'three']));
  });

  test('default Values - bad content', () async {
    var path = '/tmp/settings.yaml';

    var badContent = '''name: brett
hostname: 
port: "abc"
active: fred
volume: "its heavey"
imageid: "65385002e970"
list: 
''';

    var yaml = SettingsYaml.fromString(content: badContent, filePath: path);
    expect(yaml.validString('hostname'), isFalse);
    expect(yaml.validInt('port'), isFalse);
    expect(yaml.validBool('active'), isFalse);
    expect(yaml.validBool('volume'), isFalse);
    expect(yaml.validDouble('imageid'), isFalse);
    expect(yaml.validStringList('list'), isFalse);

    expect(yaml.asString('hostname', defaultValue: 'good'), equals('good'));
    expect(yaml.asInt('port', defaultValue: 11), equals(11));
    expect(yaml.asBool('active', defaultValue: true), isTrue);
    expect(yaml.asDouble('volume', defaultValue: 10.2), equals(10.2));
    expect(
        yaml.asString('imageid', defaultValue: 'hi'), equals("65385002e970"));
    expect(yaml.asStringList('list', defaultValue: ['a', 'b', 'c']),
        equals(['a', 'b', 'c']));
  });

  test('force String', () async {
    var path = '/tmp/settings.yaml';

    var content = '''name: brett
hostname: slayer
port: 10
active: true
volume: 10.0
imageid: "65385002e970"
''';

    var yaml = SettingsYaml.fromString(content: content, filePath: path);

    yaml.save();

    yaml = SettingsYaml.load(pathToSettings: path);
    expect(yaml.validString('imageid'), equals(true));
  });

  test('selectors -- good', () {
    var path = '/tmp/settings.yaml';

    var content = '''name: brett
hostname: slayer
port: 10
active: true
volume: 10.0
imageid: "65385002e970"
people:
  - person:
    name: brett
  - person:
    name: john
''';

    var settings = SettingsYaml.fromString(content: content, filePath: path);
    expect(settings.selectAsString('hostname'), equals('slayer'));
    expect(settings.selectAsString('imageid'), equals('65385002e970'));
    expect(settings.selectAsDouble('volume'), equals(10.0));
    expect(settings.selectAsBool('active'), isTrue);
    expect(settings.selectAsString('people.person[0].name'), equals('brett'));
    expect(settings.selectAsString('people.person[1].name'), equals('john'));

    final t1 = settings.selectAsList('people');
    expect(t1.length, equals(2));
    expect(t1[0]['name'], equals('brett'));
    expect(t1[1]['name'], equals('john'));
    // expect(
    //     t1,
    //     orderedEquals([
    //       {'person': null, 'name': 'brett'},
    //       {'person': null, 'name': 'john'}
    //     ]));
    final t2 = settings.selectAsMap('people.person[1]');

    expect(t2.length, equals(2));
    expect(t2['name'], equals('john'));
  });

  test('selectors -- bad', () {
    var path = '/tmp/settings.yaml';

    var content = '''name: brett
hostname: slayer
port: 10
active: true
volume: 10.0
imageid: "65385002e970"
people:
  - person:
    name: brett
  - person:
    name: john
''';

    var settings = SettingsYaml.fromString(content: content, filePath: path);

    expect(() => settings.selectAsString('bad.path'),
        throwsA(isA<SettingsYamlException>()));
    expect(
        () => settings.selectAsString('bad.path'),
        throwsA((e) =>
            e is SettingsYamlException && e.message == 'Invalid path: bad'));

    expect(
        () => settings.selectAsString('people.bad'),
        throwsA((e) =>
            e is SettingsYamlException &&
            e.message ==
                'As people is a list expected people.bad to be a list index. e.g people.bad[i]'));

    expect(
        () => settings.selectAsString('people.bad[0]'),
        throwsA((e) =>
            e is SettingsYamlException &&
            e.message ==
                'Expected a index selector of people.person[0]. Found people.bad[0]'));

  });
}
