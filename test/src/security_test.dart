import 'dart:io';

import 'package:settings_yaml/settings_yaml.dart';
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

void main() {
  late Directory directory;
  late String path;
  late SettingsYaml settings;
  setUp(() {
    directory = Directory.systemTemp.createTempSync('settings-security-');
    path = '${directory.path}/settings.yaml';
    settings = SettingsYaml.fromString(content: '', filePath: path);
  });
  tearDown(() => directory.deleteSync(recursive: true));

  test('bounded legacy interpolation proof creates an injected setting', () {
    const value = '"\ninjected: true\n#';
    final dynamic parsed = loadYaml('value: "$value"');
    // The legacy proof intentionally reads the parser's dynamic map result.
    // ignore: avoid_dynamic_calls
    expect(parsed['injected'], true);
  });

  test('keys, strings, nested containers and scalars round trip as data',
      () async {
    const attack = '"\ninjected: true\n#';
    final strings = <String>[
      attack,
      'x: 0\ninjected',
      'true',
      'null',
      '1',
      '',
      r'\',
      '\u0000\t\r\n',
      '\u007f\u0084\u0085\u009f\u2028\u2029\ufffe\uffff',
      '中文 😀',
      '---\n...',
    ];
    settings.valueMap = {
      for (final s in strings) s: s,
      'nested': [
        {'value': strings},
        [null, true, false, 1, -1, 1.5, 1.0]
      ],
    };
    await settings.save();
    final restored = SettingsYaml.load(pathToSettings: path);
    expect(restored['nested'], settings['nested']);
    for (final s in strings) {
      expect(restored[s], s);
    }
    expect(restored['injected'], isNull);
  });

  test('invalid data leaves destination and backup unchanged', () async {
    File(path).writeAsStringSync('original: true');
    File('$path.bak').writeAsStringSync('backup');
    final cycle = <dynamic>[];
    cycle.add(cycle);
    final invalid = <dynamic>[
      Object(),
      double.nan,
      double.infinity,
      {1: 'a', '1': 'b'},
      {Object(): 1},
      cycle,
      String.fromCharCode(0xd800),
      'x' * (1024 * 1024 + 1),
    ];
    dynamic deep = 1;
    for (var i = 0; i < 66; i++) {
      deep = [deep];
    }
    invalid.add(deep);
    for (final value in invalid) {
      settings['bad'] = value;
      await expectLater(settings.save(), throwsA(isA<SettingsYamlException>()));
      expect(File(path).readAsStringSync(), 'original: true');
      expect(File('$path.bak').readAsStringSync(), 'backup');
      expect(directory.listSync().length, 2);
    }
  });

  test('alias expansion is bounded across getters selectors and save',
      () async {
    final source = StringBuffer('a0: &a0 {value: end}\n');
    for (var i = 1; i <= 16; i++) {
      source.writeln('a$i: &a$i {left: *a${i - 1}, right: *a${i - 1}}');
    }
    settings =
        SettingsYaml.fromString(content: source.toString(), filePath: path);
    expect(() => settings['a16'], throwsA(isA<SettingsYamlException>()));
    expect(() => settings.selectAsMap('a16'),
        throwsA(isA<SettingsYamlException>()));
    expect(() => settings.selectAsString('a16'),
        throwsA(isA<SettingsYamlException>()));
    expect(
        () => settings.traverse('a16'), throwsA(isA<SettingsYamlException>()));
    await expectLater(settings.save(), throwsA(isA<SettingsYamlException>()));
    expect(directory.listSync(), isEmpty);
    expect(settings.selectAsMap('a0'), {'value': 'end'});
    var leaves = 0;
    void countLeaves(Map<String, dynamic> map) {
      if (map.containsKey('value')) {
        leaves++;
      } else {
        countLeaves(map['left'] as Map<String, dynamic>);
        countLeaves(map['right'] as Map<String, dynamic>);
      }
    }

    countLeaves(settings.selectAsMap('a8')!);
    expect(leaves, 256);
  });

  test('list aliases and in-memory map cycles are bounded', () {
    dynamic value = <dynamic>[1];
    for (var i = 0; i < 16; i++) {
      value = [value, value];
    }
    settings['list'] = value;
    expect(() => settings['list'], throwsA(isA<SettingsYamlException>()));
    expect(() => settings.asStringList('list'),
        throwsA(isA<SettingsYamlException>()));
    final cycle = <String, dynamic>{};
    cycle['self'] = cycle;
    settings['map'] = cycle;
    expect(() => settings['map'], throwsA(isA<SettingsYamlException>()));
  });

  test('parsed cycles reject in parser or bounded conversion', () {
    try {
      settings =
          SettingsYaml.fromString(content: 'x: &x {self: *x}', filePath: path);
    } on Exception {
      return; // yaml 3.1.4 rejects recursive aliases while parsing.
    }
    expect(() => settings['x'], throwsA(isA<SettingsYamlException>()));
  });

  test('new mode is 0600 and existing permissions are preserved', () async {
    File('$path.bak').writeAsStringSync('unrelated backup');
    settings['value'] = 'synthetic secret';
    await settings.save();
    expect(File(path).statSync().mode & 0x1ff, 0x180);
    for (final mode in ['600', '400', '640']) {
      expect(Process.runSync('/bin/chmod', [mode, path]).exitCode, 0);
      await settings.save();
      expect(File(path).statSync().mode & 0x1ff, int.parse(mode, radix: 8));
    }
    expect(directory.listSync().length, 2);
    expect(File('$path.bak').readAsStringSync(), 'unrelated backup');
  }, skip: !(Platform.isLinux || Platform.isMacOS));

  test('symlink and missing-parent failures leave no artifacts', () async {
    final target = File('${directory.path}/target')
      ..writeAsStringSync('original');
    Link(path).createSync(target.path);
    settings['value'] = 'synthetic';
    await expectLater(settings.save(), throwsA(isA<SettingsYamlException>()));
    expect(target.readAsStringSync(), 'original');
    expect(Link(path).existsSync(), isTrue);
    settings.filePath = '${directory.path}/missing/settings.yaml';
    await expectLater(settings.save(), throwsA(isA<FileSystemException>()));
    expect(directory.listSync().length, 2);
  }, skip: !(Platform.isLinux || Platform.isMacOS));

  test('Linux preserves ownership and named ACLs under inherited default ACLs',
      () async {
    // Use a mapped UID, including in sandboxes with a one-user namespace.
    final uid = (Process.runSync('/usr/bin/stat', ['-c', '%u', directory.path])
            .stdout as String)
        .trim();
    expect(
        Process.runSync('/usr/bin/setfacl',
            ['-m', 'd:u:$uid:r-x,d:m:r-x', directory.path]).exitCode,
        0);
    settings['value'] = 'synthetic';
    await settings.save();
    expect(File(path).statSync().mode & 0x1ff, 0x180);
    expect(
        Process.runSync('/usr/bin/setfacl', ['-m', 'u:$uid:r--,m:r--', path])
            .exitCode,
        0);
    final before = Process.runSync('/usr/bin/getfacl', ['-cpn', path]);
    expect(before.exitCode, 0);
    final owner = Process.runSync('/usr/bin/stat', ['-c', '%u:%g:%a', path]);
    await settings.save();
    expect(Process.runSync('/usr/bin/getfacl', ['-cpn', path]).stdout,
        before.stdout);
    expect(Process.runSync('/usr/bin/stat', ['-c', '%u:%g:%a', path]).stdout,
        owner.stdout);
  },
      skip: !Platform.isLinux ||
          !File('/usr/bin/setfacl').existsSync() ||
          !File('/usr/bin/getfacl').existsSync());

  test('macOS clears inherited ACLs for new files and preserves existing ACLs',
      () async {
    const inheritedAce =
        // chmod permission tokens are comma-delimited, without spaces.
        // ignore: missing_whitespace_between_adjacent_strings
        'everyone allow read,readattr,readextattr,readsecurity,'
        'file_inherit,directory_inherit';
    expect(
        Process.runSync('/bin/chmod', ['+a', inheritedAce, directory.path])
            .exitCode,
        0);
    settings['value'] = 'synthetic';
    await settings.save();
    expect(File(path).statSync().mode & 0x1ff, 0x180);
    String aclLines() =>
        (Process.runSync('/bin/ls', ['-le', path]).stdout as String)
            .split('\n')
            .skip(1)
            .join('\n');
    expect(aclLines().trim(), isEmpty);
    expect(
        Process.runSync('/bin/chmod', ['+a', 'everyone allow read', path])
            .exitCode,
        0);
    final acl = aclLines();
    final owner = Process.runSync('/usr/bin/stat', ['-f', '%u:%g:%Lp', path]);
    await settings.save();
    expect(aclLines(), acl);
    expect(Process.runSync('/usr/bin/stat', ['-f', '%u:%g:%Lp', path]).stdout,
        owner.stdout);
  }, skip: !Platform.isMacOS);

  test('macOS saves an existing file with its extended ACL removed', () async {
    File(path).writeAsStringSync('value: original\n');
    expect(Process.runSync('/bin/chmod', ['-N', path]).exitCode, 0);
    expect(Process.runSync('/bin/chmod', ['640', path]).exitCode, 0);
    final owner = Process.runSync('/usr/bin/stat', ['-f', '%u:%g:%Lp', path]);
    for (var i = 0; i < 2; i++) {
      settings['value'] = 'replacement $i';
      await settings.save();
      expect(
          SettingsYaml.load(pathToSettings: path)['value'], 'replacement $i');
      expect(Process.runSync('/usr/bin/stat', ['-f', '%u:%g:%Lp', path]).stdout,
          owner.stdout);
      final listing = Process.runSync('/bin/ls', ['-le', path]);
      expect(listing.exitCode, 0);
      expect((listing.stdout as String).split('\n').skip(1).join('\n').trim(),
          isEmpty);
    }
    expect(directory.listSync().map((entry) => entry.path), [path]);
  }, skip: !Platform.isMacOS);

  test('rename failure cleans populated private staging', () async {
    File(path).writeAsStringSync('original');
    settings.filePath = '${directory.path}/${'x' * 300}';
    settings['value'] = 'synthetic secret';
    await expectLater(settings.save(), throwsA(isA<FileSystemException>()));
    expect(directory.listSync().map((entry) => entry.path), [path]);
    expect(File(path).readAsStringSync(), 'original');
  }, skip: !(Platform.isLinux || Platform.isMacOS));

  test('ordinary collection getters retain mutation identity through save',
      () async {
    final map = <String, dynamic>{'value': 1};
    final list = <dynamic>[1];
    settings['map'] = map;
    settings['list'] = list;
    expect(identical(settings['map'], map), isTrue);
    expect(identical(settings['list'], list), isTrue);
    (settings['map'] as Map<String, dynamic>)['value'] = 2;
    (settings['list'] as List<dynamic>).add(2);
    expect(settings.selectAsInt('map.value'), 2);
    await settings.save();
    final restored = SettingsYaml.load(pathToSettings: path);
    expect(restored['map'], {'value': 2});
    expect(restored['list'], [1, 2]);
    final previousContent = File(path).readAsStringSync();
    map['cycle'] = map;
    await expectLater(settings.save(), throwsA(isA<SettingsYamlException>()));
    expect(File(path).readAsStringSync(), previousContent);
  });

  test('YamlScalar keys normalize and detect collisions', () async {
    settings['map'] = YamlMap.wrap({YamlScalar.wrap('key'): 'value'});
    expect(settings['map'], {'key': 'value'});
    await settings.save();
    expect(SettingsYaml.load(pathToSettings: path)['map'], {'key': 'value'});
    settings['map'] = YamlMap.wrap({YamlScalar.wrap(1): 'a', '1': 'b'});
    expect(() => settings['map'], throwsA(isA<SettingsYamlException>()));
  });

  test('numeric selectors are coherent before and after save', () async {
    settings = SettingsYaml.fromString(
        content: '1: root\nm: {1: nested}\nitems: [{1: value}]',
        filePath: path);
    for (var i = 0; i < 2; i++) {
      expect(settings.selectAsString('1'), 'root');
      expect(settings.selectAsString('m.1'), 'nested');
      expect(settings.selectAsMap('items.1[0]'), {'1': 'value'});
      await settings.save();
      settings = SettingsYaml.load(pathToSettings: path);
    }
  });

  test('assigned numeric map selectors normalize without changing identity',
      () async {
    final map = <int, dynamic>{
      1: 'nested',
      2: <int, dynamic>{3: 'deeper'},
    };
    settings['m'] = map;
    expect(identical(settings['m'], map), isTrue);
    for (var i = 0; i < 2; i++) {
      expect(settings.selectAsString('m.1'), 'nested');
      expect(settings.selectAsMap('m'), {
        '1': 'nested',
        '2': {'3': 'deeper'},
      });
      if (i == 0) {
        expect(identical(settings['m'], map), isTrue);
      }
      await settings.save();
      settings = SettingsYaml.load(pathToSettings: path);
    }
  });

  test('typed map selection shares budgets and rejects normalized collisions',
      () {
    settings['m'] = <dynamic, dynamic>{1: 'a', '1': 'b'};
    expect(
        () => settings.selectAsMap('m'), throwsA(isA<SettingsYamlException>()));
    settings.valueMap = {
      for (var i = 0; i < 6000; i++) '$i': 0,
      'selected': <int, dynamic>{
        for (var i = 0; i < 2500; i++) i: 'value',
      },
    };
    expect(() => settings.selectAsMap('selected'),
        throwsA(isA<SettingsYamlException>()));
  });

  test('selector keys and selected value share the traversal budget', () {
    settings.valueMap = {
      for (var i = 0; i < 6000; i++) '$i': 0,
      'selected': List<int>.filled(5000, 1),
    };
    expect(() => settings.traverse('selected'),
        throwsA(isA<SettingsYamlException>()));
  });

  test('empty traverse throws and selector does not exist', () {
    expect(() => settings.traverse('missing'),
        throwsA(isA<PathNotFoundException>()));
    expect(settings.selectorExists('missing'), isFalse);
  });
}
