import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:path/path.dart' as p;
import 'package:settings_yaml/settings_yaml.dart';
import 'package:settings_yaml/src/secure_save_windows.dart';
import 'package:settings_yaml/src/windows_access_policy.dart';
import 'package:test/test.dart';

void main() {
  group('Windows native save security', () {
    late Directory temporary;
    late String path;
    late _SecurityFixture native;

    setUp(() {
      temporary = Directory.systemTemp.createTempSync('settings-yaml-win-');
      path = p.join(temporary.path, 'settings.yaml');
      native = _SecurityFixture();
    });
    tearDown(() => temporary.deleteSync(recursive: true));

    test(
        'first native save creates missing file and preserves unrelated backup',
        () {
      // Before fixture calls: lazy GetLastError resolution once erased the
      // first GetFileAttributesW ERROR_FILE_NOT_FOUND result.
      File('$path.bak').writeAsStringSync('unrelated');
      secureSaveWindows(path, 'secret');
      expect(File(path).readAsStringSync(), 'secret');
      expect(native.sddl(path), contains('D:P(A;;FA;;;OW)'));
      expect(File('$path.bak').readAsStringSync(), 'unrelated');
      expect(temporary.listSync().map((entry) => p.basename(entry.path)),
          unorderedEquals(['settings.yaml', 'settings.yaml.bak']));
    });

    test('missing parent reports the native path error', () {
      final missing = p.join(temporary.path, 'missing', 'settings.yaml');
      expect(
          () => secureSaveWindows(missing, 'secret'),
          throwsA(isA<SettingsYamlException>().having(
              (error) => error.toString(),
              'native error',
              contains('Inspect destination failed (Windows 3)'))));
      expect(temporary.listSync(), isEmpty);
    });

    for (final kind in ['inherited', 'explicit unprotected', 'protected']) {
      test('$kind DACL survives first and repeated saves in both query views',
          () {
        native.configure(temporary.path, path, kind);
        File('$path.bak').writeAsStringSync('unrelated');
        final before = native.queryMatrix(path);
        expect(before.control & 0x1000, kind == 'protected' ? 0x1000 : 0);
        expect(_hasInherited(before), kind == 'inherited');
        for (final content in ['new', 'updated']) {
          secureSaveWindows(path, content);
          _expectPreserved(before, native.queryMatrix(path));
          expect(File(path).readAsStringSync(), content);
          expect(File('$path.bak').readAsStringSync(), 'unrelated');
        }
      });

      test('$kind saved and unsaved files follow parent grant and removal', () {
        native.configure(temporary.path, path, kind);
        final unsaved = p.join(temporary.path, 'unsaved');
        File(unsaved).writeAsStringSync('old');
        if (kind != 'inherited') {
          native.setDacl(
              unsaved, 'D:${kind == 'protected' ? 'P' : ''}(A;;FA;;;OW)',
              protected: kind == 'protected');
        }
        _expectPreserved(native.queryMatrix(path), native.queryMatrix(unsaved));
        secureSaveWindows(path, 'new');
        secureSaveWindows(path, 'updated');
        final parentBase =
            kind == 'inherited' ? '(A;OICI;FA;;;OW)' : '(A;;FA;;;OW)';
        // SetNamedSecurityInfo uses modern automatic propagation. No token
        // privileges are enabled; the test owns this temporary directory.
        native.setDacl(temporary.path, 'D:P$parentBase(A;OICI;FR;;;WD)');
        final granted = native.queryMatrix(path);
        _expectPreserved(granted, native.queryMatrix(unsaved));
        expect(native.sddl(path).contains(';;;WD)'), kind != 'protected');
        expect(granted.control & 0x1000, kind == 'protected' ? 0x1000 : 0);
        if (kind != 'protected') {
          expect(_hasInherited(granted), isTrue);
        }
        native.setDacl(temporary.path, 'D:P$parentBase');
        final revoked = native.queryMatrix(path);
        _expectPreserved(revoked, native.queryMatrix(unsaved));
        expect(native.sddl(path), isNot(contains(';;;WD)')));
        expect(revoked.control & 0x1000, kind == 'protected' ? 0x1000 : 0);
        expect(File(path).readAsStringSync(), 'updated');
        expect(File(unsaved).readAsStringSync(), 'old');
      });
    }

    for (final protected in [false, true]) {
      test('legacy protected=$protected permits only forward AI normalization',
          () {
        native.setDacl(temporary.path, 'D:P(A;;FA;;;OW)');
        final unsaved = p.join(temporary.path, 'unsaved');
        for (final fixture in [path, unsaved]) {
          File(fixture).writeAsStringSync('old');
          native.setLegacyDacl(fixture, 'D:${protected ? 'P' : ''}(A;;FA;;;OW)',
              protected: protected);
          expect(native.read(fixture).control & 0x400, 0,
              reason: 'fixture must exercise the legacy AI=false state');
          expect(_hasInherited(native.read(fixture)), isFalse);
        }
        // Keep independent baselines for each query API/mask. Unlike the
        // modern matrix, this does not assume legacy query views agree.
        final before = native.queryViews(path);
        expect(native.read(path).control & 0x400, 0,
            reason: 'named queries must not change the legacy raw descriptor');
        for (final content in ['new', 'updated']) {
          secureSaveWindows(path, content);
          final after = native.queryViews(path);
          for (var i = 0; i < before.length; i++) {
            _expectPreserved(before[i], after[i], reason: 'legacy view $i');
          }
          expect(after.first.control & 0x400, 0x400,
              reason: 'exercise the observed ReplaceFileW normalization');
          expect(File(path).readAsStringSync(), content);
        }
        expect(native.read(unsaved).control & 0x400, 0);
        for (final grant in [true, false]) {
          native.setDacl(temporary.path,
              'D:P(A;;FA;;;OW)${grant ? '(A;OICI;FR;;;WD)' : ''}');
          final savedViews = native.queryViews(path);
          final unsavedViews = native.queryViews(unsaved);
          for (var i = 0; i < savedViews.length; i++) {
            // Protection can leave the unsaved legacy file at AI=false.
            // Still compare every ACE, flag and other control exactly.
            _expectPreserved(unsavedViews[i], savedViews[i],
                reason: 'parent grant=$grant, legacy view $i');
          }
          expect(native.sddl(path).contains(';;;WD)'), grant && !protected);
          expect(savedViews.first.control & 0x1000, protected ? 0x1000 : 0);
        }
        expect(File(unsaved).readAsStringSync(), 'old');
      });
    }

    test('protected DACL retains an explicit reader ACE on repeated saves', () {
      File(path).writeAsStringSync('old');
      native.setDacl(path, 'D:P(A;;FA;;;OW)(A;;FR;;;WD)');
      final before = native.queryMatrix(path);
      expect(native.sddl(path), contains(';;;WD)'));
      for (final content in ['new', 'updated']) {
        secureSaveWindows(path, content);
        _expectPreserved(before, native.queryMatrix(path));
        expect(File(path).readAsStringSync(), content);
      }
    });

    test('new files exclude permissive inherited parent ACEs', () {
      native.setDacl(temporary.path, 'D:P(A;OICI;FA;;;OW)(A;OICI;FR;;;WD)');
      final inherited = File(p.join(temporary.path, 'inherited'))
        ..writeAsStringSync('fixture');
      expect(native.sddl(inherited.path), contains(';;;WD)'));
      secureSaveWindows(path, 'secret');
      final created = native.queryMatrix(path);
      expect(native.sddl(path), contains('D:P(A;;FA;;;OW)'));
      expect(native.sddl(path), isNot(contains(';;;WD)')));
      secureSaveWindows(path, 'updated');
      _expectPreserved(created, native.queryMatrix(path));
      expect(File(path).readAsStringSync(), 'updated');
    });

    test(
        'mandatory label rejects before replacement '
        'without artifacts or details', () {
      File(path).writeAsStringSync('old');
      File('$path.bak').writeAsStringSync('unrelated');
      // An owner may lower the integrity level without enabling privileges.
      // Do not skip: a native runner must exercise a real nonempty access SACL.
      native.setLabel(path, 'S:(ML;;NW;;;LW)');
      final before = native.read(path);
      expect(before.sacl, isNotEmpty);
      expect(before.sacl!.any((ace) => ace[0] == 0x11), isTrue);
      expect(
          () => secureSaveWindows(path, 'secret-not-for-errors'),
          throwsA(isA<SettingsYamlException>().having(
              (error) => error.toString(),
              'precommit error',
              allOf(
                  contains('access-SACL policy; destination unchanged'),
                  isNot(contains('Replacement committed')),
                  isNot(contains('secret-not-for-errors')),
                  isNot(contains('ML;')),
                  isNot(contains('S-1-'))))));
      _expectPreserved(before, native.read(path));
      expect(File(path).readAsStringSync(), 'old');
      expect(File('$path.bak').readAsStringSync(), 'unrelated');
      expect(temporary.listSync().map((entry) => p.basename(entry.path)),
          unorderedEquals(['settings.yaml', 'settings.yaml.bak']));
    });

    test('read-only destination fails without changing it or unrelated backup',
        () {
      File(path).writeAsStringSync('old');
      File('$path.bak').writeAsStringSync('unrelated');
      final before = native.read(path);
      native.setAttributes(path, 0x81);
      try {
        expect(() => secureSaveWindows(path, 'new'),
            throwsA(isA<SettingsYamlException>()));
        expect(File(path).readAsStringSync(), 'old');
        _expectPreserved(before, native.read(path));
        expect(File('$path.bak').readAsStringSync(), 'unrelated');
      } finally {
        native.setAttributes(path, 0x80);
      }
    });

    test('exclusive open fails without changing original or unrelated backup',
        () {
      File(path).writeAsStringSync('old');
      File('$path.bak').writeAsStringSync('unrelated');
      final before = native.read(path);
      final handle = native.lock(path);
      try {
        expect(() => secureSaveWindows(path, 'new'),
            throwsA(isA<SettingsYamlException>()));
      } finally {
        expect(native.close(handle), isNot(0));
      }
      expect(File(path).readAsStringSync(), 'old');
      _expectPreserved(before, native.read(path));
      expect(File('$path.bak').readAsStringSync(), 'unrelated');
    });

    test('rejects a reparse-point destination without touching its target', () {
      final target = File(p.join(temporary.path, 'target'))
        ..writeAsStringSync('target');
      try {
        Link(path).createSync(target.path);
      } on FileSystemException catch (error) {
        if (error.osError?.errorCode == 1314 || error.osError?.errorCode == 5) {
          markTestSkipped('Windows symlink creation requires Developer Mode '
              'or a privilege this test deliberately does not enable.');
          return;
        }
        rethrow;
      }
      expect(() => secureSaveWindows(path, 'new'),
          throwsA(isA<SettingsYamlException>()));
      expect(target.readAsStringSync(), 'target');
      expect(FileSystemEntity.typeSync(path, followLinks: false),
          FileSystemEntityType.link);
    });
  }, skip: !Platform.isWindows ? 'Requires native Windows ACL APIs.' : false);
}

bool _hasInherited(WindowsAccessPolicy policy) =>
    policy.dacl!.any((ace) => ace[1] & 0x10 != 0);

// An independent assertion oracle, not a call back into preservedBy().
void _expectPreserved(WindowsAccessPolicy before, WindowsAccessPolicy after,
    {bool allowAi = true, String? reason}) {
  expect(after.owner, before.owner, reason: reason);
  expect(after.group, before.group, reason: reason);
  expect(after.dacl, before.dacl, reason: reason);
  expect(after.sacl, before.sacl, reason: reason);
  expect(after.control & 0x3b3c, before.control & 0x3b3c, reason: reason);
  if (!allowAi || before.control & 0x400 != 0) {
    expect(after.control & 0x400, before.control & 0x400, reason: reason);
  }
}

/// Native fixtures avoid localized tools, shell quoting and enabled privileges.
final class _SecurityFixture {
  final kernel = DynamicLibrary.open('kernel32.dll');
  final security = DynamicLibrary.open('advapi32.dll');
  late final free = kernel.lookupFunction<Pointer<Void> Function(Pointer<Void>),
      Pointer<Void> Function(Pointer<Void>)>('LocalFree');
  late final get = security.lookupFunction<
      Uint32 Function(
          Pointer<Utf16>,
          Uint32,
          Uint32,
          Pointer<Pointer<Void>>,
          Pointer<Pointer<Void>>,
          Pointer<Pointer<Void>>,
          Pointer<Pointer<Void>>,
          Pointer<Pointer<Void>>),
      int Function(
          Pointer<Utf16>,
          int,
          int,
          Pointer<Pointer<Void>>,
          Pointer<Pointer<Void>>,
          Pointer<Pointer<Void>>,
          Pointer<Pointer<Void>>,
          Pointer<Pointer<Void>>)>('GetNamedSecurityInfoW');
  late final getHandle = security.lookupFunction<
      Uint32 Function(
          Pointer<Void>,
          Uint32,
          Uint32,
          Pointer<Pointer<Void>>,
          Pointer<Pointer<Void>>,
          Pointer<Pointer<Void>>,
          Pointer<Pointer<Void>>,
          Pointer<Pointer<Void>>),
      int Function(
          Pointer<Void>,
          int,
          int,
          Pointer<Pointer<Void>>,
          Pointer<Pointer<Void>>,
          Pointer<Pointer<Void>>,
          Pointer<Pointer<Void>>,
          Pointer<Pointer<Void>>)>('GetSecurityInfo');
  late final setNamed = security.lookupFunction<
      Uint32 Function(Pointer<Utf16>, Uint32, Uint32, Pointer<Void>,
          Pointer<Void>, Pointer<Void>, Pointer<Void>),
      int Function(Pointer<Utf16>, int, int, Pointer<Void>, Pointer<Void>,
          Pointer<Void>, Pointer<Void>)>('SetNamedSecurityInfoW');
  late final setFile = security.lookupFunction<
      Int32 Function(Pointer<Utf16>, Uint32, Pointer<Void>),
      int Function(Pointer<Utf16>, int, Pointer<Void>)>('SetFileSecurityW');
  late final stringify = security.lookupFunction<
          Int32 Function(Pointer<Void>, Uint32, Uint32, Pointer<Pointer<Utf16>>,
              Pointer<Uint32>),
          int Function(Pointer<Void>, int, int, Pointer<Pointer<Utf16>>,
              Pointer<Uint32>)>(
      'ConvertSecurityDescriptorToStringSecurityDescriptorW');
  late final parse = security.lookupFunction<
          Int32 Function(
              Pointer<Utf16>, Uint32, Pointer<Pointer<Void>>, Pointer<Uint32>),
          int Function(
              Pointer<Utf16>, int, Pointer<Pointer<Void>>, Pointer<Uint32>)>(
      'ConvertStringSecurityDescriptorToSecurityDescriptorW');
  late final attributes = kernel.lookupFunction<
      Int32 Function(Pointer<Utf16>, Uint32),
      int Function(Pointer<Utf16>, int)>('SetFileAttributesW');
  late final open = kernel.lookupFunction<
      Pointer<Void> Function(Pointer<Utf16>, Uint32, Uint32, Pointer<Void>,
          Uint32, Uint32, Pointer<Void>),
      Pointer<Void> Function(Pointer<Utf16>, int, int, Pointer<Void>, int, int,
          Pointer<Void>)>('CreateFileW');
  late final close = kernel.lookupFunction<Int32 Function(Pointer<Void>),
      int Function(Pointer<Void>)>('CloseHandle');
  late final control = security.lookupFunction<
      Int32 Function(Pointer<Void>, Pointer<Uint16>, Pointer<Uint32>),
      int Function(Pointer<Void>, Pointer<Uint16>,
          Pointer<Uint32>)>('GetSecurityDescriptorControl');
  late final getSacl = security.lookupFunction<
      Int32 Function(Pointer<Void>, Pointer<Int32>, Pointer<Pointer<Void>>,
          Pointer<Int32>),
      int Function(Pointer<Void>, Pointer<Int32>, Pointer<Pointer<Void>>,
          Pointer<Int32>)>('GetSecurityDescriptorSacl');
  late final getDacl = security.lookupFunction<
      Int32 Function(Pointer<Void>, Pointer<Int32>, Pointer<Pointer<Void>>,
          Pointer<Int32>),
      int Function(Pointer<Void>, Pointer<Int32>, Pointer<Pointer<Void>>,
          Pointer<Int32>)>('GetSecurityDescriptorDacl');
  late final getAce = security.lookupFunction<
      Int32 Function(Pointer<Void>, Uint32, Pointer<Pointer<Uint8>>),
      int Function(Pointer<Void>, int, Pointer<Pointer<Uint8>>)>('GetAce');
  late final sidLength = security.lookupFunction<Uint32 Function(Pointer<Void>),
      int Function(Pointer<Void>)>('GetLengthSid');

  void configure(String directory, String path, String kind) {
    // Force modern propagation instead of depending on the runner's temp ACL.
    void nativeParent({required bool inherited}) {
      setDacl(directory, inherited ? 'D:P(A;OICI;FA;;;OW)' : 'D:P(A;;FA;;;OW)');
    }

    nativeParent(inherited: kind == 'inherited');
    File(path).writeAsStringSync('old');
    if (kind == 'inherited') {
      // Reapply the parent after creation to exercise automatic propagation.
      nativeParent(inherited: true);
    } else {
      setDacl(path, 'D:${kind == 'protected' ? 'P' : ''}(A;;FA;;;OW)',
          protected: kind == 'protected');
    }
  }

  List<WindowsAccessPolicy> queryViews(String path) => [
        read(path),
        read(path, named: true),
        read(path, information: 7),
        read(path, named: true, information: 7),
      ];

  WindowsAccessPolicy queryMatrix(String path) {
    // The old diagnostic compared handle/0x1f7 with named/7 and reported ID
    // differences. Check both variables on the same controlled fixture; never
    // normalize ACE flags or assume that the two APIs have equivalent views.
    final handle = read(path);
    _expectPreserved(handle, read(path, named: true),
        allowAi: false,
        reason: 'GetSecurityInfo vs GetNamedSecurityInfoW, mask 0x1f7');
    final basic = read(path, information: 7);
    _expectPreserved(basic, read(path, named: true, information: 7),
        allowAi: false,
        reason: 'GetSecurityInfo vs GetNamedSecurityInfoW, mask 7');
    expect(basic.owner, handle.owner);
    expect(basic.group, handle.group);
    expect(basic.dacl, handle.dacl);
    expect(basic.control & 0x150c, handle.control & 0x150c,
        reason: 'handle query masks 7 and 0x1f7 must preserve DACL controls');
    _expectPreserved(handle, read(path),
        allowAi: false,
        reason: 'querying the named view must not mutate the raw policy');
    return handle;
  }

  WindowsAccessPolicy read(String path,
          {bool named = false, int information = 0x1f7}) =>
      using((arena) {
        final owner = arena<Pointer<Void>>();
        final group = arena<Pointer<Void>>();
        final dacl = arena<Pointer<Void>>();
        final descriptor = arena<Pointer<Void>>();
        final name = path.toNativeUtf16(allocator: arena);
        if (named) {
          expect(
              get(name, 1, information, owner, group, dacl, nullptr,
                  descriptor),
              0);
        } else {
          final handle = open(name, 0x20000, 7, nullptr, 3, 0x200000, nullptr);
          expect(
              handle.address, isNot(anyOf(-1, 0xffffffff, 0xffffffffffffffff)));
          try {
            expect(
                getHandle(handle, 1, information, owner, group, dacl, nullptr,
                    descriptor),
                0);
          } finally {
            expect(close(handle), isNot(0));
          }
        }
        arena.onReleaseAll(() => free(descriptor.value));
        final sacl = arena<Pointer<Void>>();
        final present = arena<Int32>();
        final defaulted = arena<Int32>();
        final value = arena<Uint16>();
        final revision = arena<Uint32>();
        expect(getSacl(descriptor.value, present, sacl, defaulted), isNot(0));
        expect(control(descriptor.value, value, revision), isNot(0));
        List<int> sid(Pointer<Void> pointer) =>
            List<int>.of(pointer.cast<Uint8>().asTypedList(sidLength(pointer)));
        List<List<int>>? aces(Pointer<Void> acl) {
          if (acl == nullptr) {
            return null;
          }
          final entries = <List<int>>[];
          final ace = arena<Pointer<Uint8>>();
          for (var index = 0; index < acl.cast<Uint16>()[2]; index++) {
            expect(getAce(acl, index, ace), isNot(0));
            entries.add(List<int>.of(
                ace.value.asTypedList(ace.value.cast<Uint16>()[1])));
          }
          return entries;
        }

        return WindowsAccessPolicy(
            owner: sid(owner.value),
            group: sid(group.value),
            dacl: aces(dacl.value),
            sacl: aces(sacl.value),
            control: value.value);
      });

  String sddl(String path) => using((arena) {
        final descriptor = arena<Pointer<Void>>();
        expect(
            get(path.toNativeUtf16(allocator: arena), 1, 7, nullptr, nullptr,
                nullptr, nullptr, descriptor),
            0);
        arena.onReleaseAll(() => free(descriptor.value));
        final text = arena<Pointer<Utf16>>();
        expect(stringify(descriptor.value, 1, 7, text, nullptr), isNot(0));
        arena.onReleaseAll(() => free(text.value.cast()));
        return text.value.toDartString();
      });

  void setDacl(String path, String sddl, {bool protected = true}) =>
      using((arena) {
        final descriptor = arena<Pointer<Void>>();
        expect(
            parse(sddl.toNativeUtf16(allocator: arena), 1, descriptor, nullptr),
            isNot(0));
        arena.onReleaseAll(() => free(descriptor.value));
        final acl = arena<Pointer<Void>>();
        final present = arena<Int32>();
        final defaulted = arena<Int32>();
        expect(getDacl(descriptor.value, present, acl, defaulted), isNot(0));
        expect(
            setNamed(
                path.toNativeUtf16(allocator: arena),
                1,
                4 | (protected ? 0x80000000 : 0x20000000),
                nullptr,
                nullptr,
                acl.value,
                nullptr),
            0);
      });

  void setLegacyDacl(String path, String sddl, {required bool protected}) =>
      using((arena) {
        final descriptor = arena<Pointer<Void>>();
        expect(
            parse(sddl.toNativeUtf16(allocator: arena), 1, descriptor, nullptr),
            isNot(0));
        arena.onReleaseAll(() => free(descriptor.value));
        expect(
            setFile(path.toNativeUtf16(allocator: arena),
                4 | (protected ? 0x80000000 : 0x20000000), descriptor.value),
            isNot(0));
      });

  void setLabel(String path, String sddl) => using((arena) {
        final descriptor = arena<Pointer<Void>>();
        expect(
            parse(sddl.toNativeUtf16(allocator: arena), 1, descriptor, nullptr),
            isNot(0));
        arena.onReleaseAll(() => free(descriptor.value));
        final acl = arena<Pointer<Void>>();
        final present = arena<Int32>();
        final defaulted = arena<Int32>();
        expect(getSacl(descriptor.value, present, acl, defaulted), isNot(0));
        expect(
            setNamed(path.toNativeUtf16(allocator: arena), 1, 0x10, nullptr,
                nullptr, nullptr, acl.value),
            0);
      });

  void setAttributes(String path, int value) => using((arena) {
        expect(
            attributes(path.toNativeUtf16(allocator: arena), value), isNot(0));
      });

  Pointer<Void> lock(String path) => using((arena) {
        final handle = open(path.toNativeUtf16(allocator: arena), 0x80000000, 0,
            nullptr, 3, 0x80, nullptr);
        expect(
            handle.address, isNot(anyOf(-1, 0xffffffff, 0xffffffffffffffff)));
        return handle;
      });
}
