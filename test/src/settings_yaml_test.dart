import 'package:collection/collection.dart';
// import 'package:dcli/dcli.dart' hide equals;
import 'package:dcli_core/dcli_core.dart' as core;
import 'package:settings_yaml/settings_yaml.dart';
import 'package:test/test.dart';

void main() {
  test('SettingsYaml fromString', () async {
    const content = '''
name: brett
hostname: slayer
port: 10
''';
    const path = '/tmp/settings.yaml';
    final yaml = SettingsYaml.fromString(content: content, filePath: path);
    expect(yaml['name'], equals('brett'));
    expect(yaml['hostname'], equals('slayer'));
    expect(yaml['port'], equals(10));
  });

  test('casting', () async {
    const content = '''
name: brett
string: slayer
int: 10
double: 10.1
bool: true
''';
    const path = '/tmp/settings.yaml';
    final yaml = SettingsYaml.fromString(content: content, filePath: path);
    expect(yaml.asString('string'), equals('slayer'));
    expect(yaml.asInt('int'), equals(10));
    expect(yaml.asDouble('double'), equals(10.1));
    expect(yaml.asBool('bool'), isTrue);
  });

  test('SettingsYaml String list', () async {
    core.Settings().setVerbose(enabled: true);
    const content = '''
name: brett
hostnames: [one, two, three]
''';
    const path = '/tmp/settings.yaml';
    final yaml = SettingsYaml.fromString(content: content, filePath: path);
    expect(yaml['hostnames'], equals(['one', 'two', 'three']));

    await core.withTempFile((pathTo) async {
      var yaml = SettingsYaml.load(pathToSettings: pathTo);
      yaml['list'] = <String>['one', 'two', 'three'];
      await yaml.save();

      yaml = SettingsYaml.load(pathToSettings: pathTo);

      expect(yaml['list'], equals(['one', 'two', 'three']));

      final numbers = (yaml['list'] as List<dynamic>).cast<String>();
      expect(numbers, equals(['one', 'two', 'three']));

      final atsAsString = yaml.asStringList('list');
      expect(atsAsString, equals(['one', 'two', 'three']));
    });
  });

  test('SettingsYaml String map', () async {
    const content = '''
name: brett
hostnames: 
  host1: one
  host2: two
  host3: three
''';
    const path = '/tmp/settings.yaml';
    final yaml = SettingsYaml.fromString(content: content, filePath: path);
    expect(
        const MapEquality<String, String>().equals(
            Map.from(yaml['hostnames'] as Map<String, dynamic>),
            {'host1': 'one', 'host2': 'two', 'host3': 'three'}),
        isTrue);

    await core.withTempFile((pathTo) async {
      var yaml = SettingsYaml.load(pathToSettings: pathTo);
      yaml['map'] = <String, String>{
        'host1': 'one',
        'host2': 'two',
        'host3': 'three'
      };
      await yaml.save();

      yaml = SettingsYaml.load(pathToSettings: pathTo);

      expect(
          const MapEquality<String, String>().equals(
              Map.from(yaml['map'] as Map<String, dynamic>),
              {'host1': 'one', 'host2': 'two', 'host3': 'three'}),
          isTrue);
    });
  });

  test('SettingsYaml fromString - empty content', () async {
    const content = '';
    const path = '/tmp/settings.yaml';
    final yaml = SettingsYaml.fromString(content: content, filePath: path);
    expect(yaml['name'], isNull);
    expect(yaml.validString('username'), false);
  });
  test('SettingsYaml fromFile', () async {
    const path = '/tmp/settings.yaml';
    const content = '''
name: brett
hostname: slayer
port: 10
coefficient: 8.25
''';
    if (core.exists(path)) {
      await core.delete(path);
    }
    await core.withOpenLineFile(path, (file) async {
      await file.write(content);
    });

    final yaml = SettingsYaml.load(pathToSettings: path);
    expect(yaml['name'], equals('brett'));
    expect(yaml['hostname'], equals('slayer'));
    expect(yaml['port'], equals(10));
    expect(yaml['coefficient'], equals(8.25));
  });

  test('SettingsYaml save', () async {
    const path = '/tmp/settings.yaml';
    const content = '''
name: brett
hostname: slayer
port: 10
''';
    if (core.exists(path)) {
      await core.delete(path);
    }

    await core.withOpenLineFile(path, (file) async {
      await file.write(content);
    });

    var yaml = SettingsYaml.fromString(content: content, filePath: path);
    await core.delete(path);
    await yaml.save();

    yaml = SettingsYaml.load(pathToSettings: path);
    expect(yaml['name'], equals('brett'));
    expect(yaml['hostname'], equals('slayer'));
    expect(yaml['port'], equals(10));
  });

  test('SettingsYaml load create with no file.', () async {
    const path = '/tmp/settings.yaml';

    if (core.exists(path)) {
      await core.delete(path);
    }

    final yaml = SettingsYaml.load(pathToSettings: path);
    await yaml.save();
  });

  test('SettingsYaml load create with no file and save settings.', () async {
    const path = '/tmp/settings.yaml';

    if (core.exists(path)) {
      await core.delete(path);
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
    await yaml.save();

    // reload saved data and make certain that its intact.
    yaml = SettingsYaml.load(pathToSettings: path);

    expect(yaml['name'], equals('brett'));
    expect(yaml['hostname'], equals('slayer'));
    expect(yaml['port'], equals(10));
  });

  test('SettingsYaml validXXX', () async {
    const path = '/tmp/settings.yaml';
    const content = '''
name: brett
hostname: slayer
port: 10
active: true
volume: 10.0
''';

    final yaml = SettingsYaml.fromString(content: content, filePath: path);

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
    const path = '/tmp/settings.yaml';

    const goodContent = '''
name: brett
hostname: slayer
port: 10
active: true
volume: 10.1
imageid: "65385002e970"
list: [one, two, three]
''';

    final yaml = SettingsYaml.fromString(content: goodContent, filePath: path);

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
    expect(yaml.asString('imageid'), equals('65385002e970'));
    expect(yaml.asStringList('list'), equals(['one', 'two', 'three']));
  });

  test('default Values - bad content', () async {
    const path = '/tmp/settings.yaml';

    const badContent = '''
name: brett
hostname: 
port: "abc"
active: fred
volume: "its heavey"
imageid: "65385002e970"
list: 
''';

    final yaml = SettingsYaml.fromString(content: badContent, filePath: path);
    expect(yaml.validString('hostname'), isFalse);
    expect(yaml.validInt('port'), isFalse);
    expect(yaml.validBool('active'), isFalse);
    expect(yaml.validBool('volume'), isFalse);
    expect(yaml.validDouble('imageid'), isFalse);
    expect(yaml.validStringList('list'), isFalse);

    expect(yaml.asString('hostname', defaultValue: 'good'), equals('good'));
    expect(yaml.asInt('port', defaultValue: 11), equals(11));
    expect(yaml.asBool('active'), isTrue);
    expect(yaml.asDouble('volume', defaultValue: 10.2), equals(10.2));
    expect(
        yaml.asString('imageid', defaultValue: 'hi'), equals('65385002e970'));
    expect(yaml.asStringList('list', defaultValue: ['a', 'b', 'c']),
        equals(['a', 'b', 'c']));
  });

  test('force String', () async {
    const path = '/tmp/settings.yaml';

    const content = '''
name: brett
hostname: slayer
port: 10
active: true
volume: 10.0
imageid: "65385002e970"
''';

    var yaml = SettingsYaml.fromString(content: content, filePath: path);

    await yaml.save();

    yaml = SettingsYaml.load(pathToSettings: path);
    expect(yaml.validString('imageid'), equals(true));
  });

  test('selectors -- good', () {
    const path = '/tmp/settings.yaml';

    const content = '''
name: brett
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

    final settings = SettingsYaml.fromString(content: content, filePath: path);
    expect(settings.selectAsString('hostname'), equals('slayer'));
    expect(settings.selectAsString('imageid'), equals('65385002e970'));
    expect(settings.selectAsDouble('volume'), equals(10.0));
    expect(settings.selectAsBool('active'), isTrue);
    expect(settings.selectAsString('people.person[0].name'), equals('brett'));
    expect(settings.selectAsString('people.person[1].name'), equals('john'));

    final t1 = settings.selectAsList('people');
    expect(t1!.length, equals(2));
    // ignore: avoid_dynamic_calls
    expect(t1[0]['name'], equals('brett'));
    // ignore: avoid_dynamic_calls
    expect(t1[1]['name'], equals('john'));
    // expect(
    //     t1,
    //     orderedEquals([
    //       {'person': null, 'name': 'brett'},
    //       {'person': null, 'name': 'john'}
    //     ]));
    final t2 = settings.selectAsMap('people.person[1]');

    expect(t2!.length, equals(2));
    expect(t2['name'], equals('john'));
  });

  test('selectors -- bad', () {
    const path = '/tmp/settings.yaml';

    const content = '''
name: brett
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

    final settings = SettingsYaml.fromString(content: content, filePath: path);

    expect(() => settings.selectAsString('bad.path'),
        throwsA(isA<SettingsYamlException>()));
    expect(
        () => settings.selectAsString('bad.path'),
        throwsA((dynamic e) =>
            e is SettingsYamlException && e.message == 'Invalid path: bad'));

    expect(
        () => settings.selectAsString('people.bad'),
        throwsA((dynamic e) =>
            e is SettingsYamlException &&
            e.message ==
                'As people is a list expected people.bad to be a list index. '
                    'e.g people.bad[i]'));

    expect(
        () => settings.selectAsString('people.bad[0]'),
        throwsA((dynamic e) =>
            e is SettingsYamlException &&
            e.message ==
                'Expected a index selector of people.person[0]. '
                    'Found people.bad[0]'));
  });
}
