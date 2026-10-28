import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:path/path.dart' as p;
import 'package:settings_yaml/settings_yaml.dart';
import 'package:settings_yaml/src/secure_save_windows.dart';
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
      // Keep this before fixture calls: lazy GetLastError resolution used to
      // erase ERROR_FILE_NOT_FOUND on the first GetFileAttributesW failure.
      File('$path.bak').writeAsStringSync('unrelated');
      secureSaveWindows(path, 'secret');
      expect(File(path).readAsStringSync(), 'secret');
      expect(native.snapshot(path), contains('D:P(A;;FA;;;OW)'));
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

    test('preserves owner, group and ordinary inherited DACL', () {
      File(path).writeAsStringSync('old');
      final before = native.snapshot(path);
      final control = native.daclControl(path);
      expect(before, contains(';ID;'));
      expect(control & 0x1000, 0);
      for (final content in ['new', 'updated']) {
        secureSaveWindows(path, content);
        expect(File(path).readAsStringSync(), content);
        expect(native.snapshot(path), before);
        expect(native.daclControl(path), control);
      }
    });

    test('preserves protected DACL with a reader ACE and unrelated backup', () {
      File(path).writeAsStringSync('old');
      File('$path.bak').writeAsStringSync('unrelated');
      native.setDacl(path, 'D:P(A;;FA;;;OW)(A;;FR;;;WD)');
      final before = native.snapshot(path);
      final control = native.daclControl(path);
      expect(before, contains('D:P'));
      expect(before, contains(';;;WD)'));
      expect(control & 0x1000, 0x1000);
      for (final content in ['new', 'updated']) {
        secureSaveWindows(path, content);
        expect(File(path).readAsStringSync(), content);
        expect(native.snapshot(path), before);
        expect(native.daclControl(path), control);
        expect(File('$path.bak').readAsStringSync(), 'unrelated');
      }
    });

    test('new files exclude permissive inherited parent ACEs', () {
      native.setDacl(temporary.path, 'D:P(A;OICI;FA;;;OW)(A;OICI;FR;;;WD)');
      final inherited = File(p.join(temporary.path, 'inherited'))
        ..writeAsStringSync('fixture');
      expect(native.snapshot(inherited.path), contains(';;;WD)'));
      secureSaveWindows(path, 'secret');
      final created = native.snapshot(path);
      expect(created, contains('D:P(A;;FA;;;OW)'));
      expect(created, isNot(contains(';;;WD)')));
      // A second save must also work with the generated OWNER RIGHTS policy.
      secureSaveWindows(path, 'updated');
      expect(native.snapshot(path), created);
      expect(File(path).readAsStringSync(), 'updated');
    });

    test('read-only destination fails without changing it or unrelated backup',
        () {
      File(path).writeAsStringSync('old');
      File('$path.bak').writeAsStringSync('unrelated');
      final before = native.snapshot(path);
      native.setAttributes(path, 0x81);
      try {
        expect(() => secureSaveWindows(path, 'new'),
            throwsA(isA<SettingsYamlException>()));
        expect(File(path).readAsStringSync(), 'old');
        expect(native.snapshot(path), before);
        expect(File('$path.bak').readAsStringSync(), 'unrelated');
      } finally {
        native.setAttributes(path, 0x80);
      }
    });

    test('exclusive open fails without changing original or unrelated backup',
        () {
      File(path).writeAsStringSync('old');
      File('$path.bak').writeAsStringSync('unrelated');
      final before = native.snapshot(path);
      final handle = native.lock(path);
      try {
        expect(() => secureSaveWindows(path, 'new'),
            throwsA(isA<SettingsYamlException>()));
      } finally {
        expect(native.close(handle), isNot(0));
      }
      expect(File(path).readAsStringSync(), 'old');
      expect(native.snapshot(path), before);
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

/// Native fixture operations avoid localized icacls output and shell quoting.
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
  late final set = security.lookupFunction<
      Int32 Function(Pointer<Utf16>, Uint32, Pointer<Void>),
      int Function(Pointer<Utf16>, int, Pointer<Void>)>('SetFileSecurityW');
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

  int daclControl(String path) => using((arena) {
        final descriptor = arena<Pointer<Void>>();
        expect(
            get(path.toNativeUtf16(allocator: arena), 1, 4, nullptr, nullptr,
                nullptr, nullptr, descriptor),
            0);
        arena.onReleaseAll(() => free(descriptor.value));
        final value = arena<Uint16>();
        final revision = arena<Uint32>();
        expect(control(descriptor.value, value, revision), isNot(0));
        // Include present/defaulted, auto-inherit request, auto-inherited and
        // protected bits, not just the subset represented by SDDL formatting.
        return value.value & 0x150c;
      });

  String snapshot(String path) => using((arena) {
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

  void setDacl(String path, String sddl) => using((arena) {
        final descriptor = arena<Pointer<Void>>();
        expect(
            parse(sddl.toNativeUtf16(allocator: arena), 1, descriptor, nullptr),
            isNot(0));
        arena.onReleaseAll(() => free(descriptor.value));
        expect(
            set(path.toNativeUtf16(allocator: arena), 0x80000004,
                descriptor.value),
            isNot(0));
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
