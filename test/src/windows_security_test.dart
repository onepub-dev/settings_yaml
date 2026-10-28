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
        native.saveWithDiagnostics(path, content);
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
        native.saveWithDiagnostics(path, content);
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
      native.saveWithDiagnostics(path, 'updated');
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
  var _reportedPolicyFailure = false;

  // Only synthetic fixtures use this wrapper. Never add ACLs or SIDs to the
  // production exception: a real settings file can contain private policy.
  void saveWithDiagnostics(String path, String content) {
    _PolicyDiagnostic? before;
    String? beforeError;
    try {
      before = policyDiagnostic(path);
    } on Object catch (error) {
      // Diagnostic collection must not prevent exercising the real save.
      beforeError = _diagnosticError(error);
    }
    try {
      secureSaveWindows(path, content);
    } on SettingsYamlException catch (error) {
      if (!_reportedPolicyFailure &&
          error.toString().contains(
              'Replacement committed, but access policy verification failed')) {
        _reportedPolicyFailure = true;
        try {
          if (before == null) {
            print('Synthetic Windows policy: before snapshot unavailable: '
                '$beforeError');
          } else {
            before.reportDifference(policyDiagnostic(path));
          }
        } on Object catch (error) {
          print('Synthetic Windows policy: diagnostic collection failed: '
              '${_diagnosticError(error)}');
        }
      }
      rethrow;
    }
  }

  final kernel = DynamicLibrary.open('kernel32.dll');
  final security = DynamicLibrary.open('advapi32.dll');
  late final lastError =
      kernel.lookupFunction<Uint32 Function(), int Function()>('GetLastError');
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
  late final getHandleSecurity = security.lookupFunction<
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
  late final getSacl = security.lookupFunction<
      Int32 Function(Pointer<Void>, Pointer<Int32>, Pointer<Pointer<Void>>,
          Pointer<Int32>),
      int Function(Pointer<Void>, Pointer<Int32>, Pointer<Pointer<Void>>,
          Pointer<Int32>)>('GetSecurityDescriptorSacl');
  late final getAce = security.lookupFunction<
      Int32 Function(Pointer<Void>, Uint32, Pointer<Pointer<Uint8>>),
      int Function(Pointer<Void>, int, Pointer<Pointer<Uint8>>)>('GetAce');
  late final sidLength = security.lookupFunction<Uint32 Function(Pointer<Void>),
      int Function(Pointer<Void>)>('GetLengthSid');

  _PolicyDiagnostic policyDiagnostic(String path) => using((arena) {
        // Resolve before any fallible call: lazy symbol lookup can overwrite
        // the native last-error value this diagnostic is trying to report.
        lastError();
        // Match the production query, including access-relevant SACL ACEs;
        // auditing SACLs are outside the save contract and this diagnostic.
        final handle = open(path.toNativeUtf16(allocator: arena), 0x20000, 7,
            nullptr, 3, 0x200000, nullptr);
        if ([-1, 0xffffffff, 0xffffffffffffffff].contains(handle.address)) {
          throw StateError('CreateFileW failed (Windows ${lastError()})');
        }
        try {
          final owner = arena<Pointer<Void>>();
          final group = arena<Pointer<Void>>();
          final dacl = arena<Pointer<Void>>();
          final descriptor = arena<Pointer<Void>>();
          final result = getHandleSecurity(
              handle, 1, 0x1f7, owner, group, dacl, nullptr, descriptor);
          if (result != 0) {
            throw StateError('GetSecurityInfo failed (Windows $result)');
          }
          arena.onReleaseAll(() => free(descriptor.value));
          final sacl = arena<Pointer<Void>>();
          final present = arena<Int32>();
          final defaulted = arena<Int32>();
          final value = arena<Uint16>();
          final revision = arena<Uint32>();
          if (getSacl(descriptor.value, present, sacl, defaulted) == 0) {
            throw StateError('GetSecurityDescriptorSacl failed '
                '(Windows ${lastError()})');
          }
          if (control(descriptor.value, value, revision) == 0) {
            throw StateError('GetSecurityDescriptorControl failed '
                '(Windows ${lastError()})');
          }
          final text = arena<Pointer<Utf16>>();
          // SDDL is supplemental: a formatter failure must not discard the
          // byte-for-byte policy comparison or the descriptor control bits.
          final String sddl;
          if (stringify(descriptor.value, 1, 0x1f7, text, nullptr) == 0) {
            sddl = '(unavailable: '
                'ConvertSecurityDescriptorToStringSecurityDescriptorW failed '
                'with Windows ${lastError()})';
          } else {
            arena.onReleaseAll(() => free(text.value.cast()));
            sddl = text.value.toDartString();
          }
          String sid(Pointer<Void> pointer) => pointer == nullptr
              ? 'null'
              : _hex(pointer.cast<Uint8>().asTypedList(sidLength(pointer)));
          List<String>? aces(Pointer<Void> acl) {
            if (acl == nullptr) {
              return null;
            }
            final entries = <String>[];
            final ace = arena<Pointer<Uint8>>();
            for (var index = 0; index < acl.cast<Uint16>()[2]; index++) {
              if (getAce(acl, index, ace) == 0) {
                throw StateError('GetAce($index) failed '
                    '(Windows ${lastError()})');
              }
              final bytes = ace.value.asTypedList(ace.value.cast<Uint16>()[1]);
              entries.add('type=${bytes[0]} flags=0x${_hex([bytes[1]])} '
                  'bytes=${_hex(bytes)}');
            }
            return entries;
          }

          return _PolicyDiagnostic(sid(owner.value), sid(group.value),
              aces(dacl.value), aces(sacl.value), value.value, sddl);
        } finally {
          close(handle);
        }
      });

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

String _hex(List<int> bytes) =>
    bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();

String _diagnosticError(Object error) {
  final text = error.toString();
  return text.length <= 512 ? text : '${text.substring(0, 512)} [truncated]';
}

final class _PolicyDiagnostic {
  _PolicyDiagnostic(
      this.owner, this.group, this.dacl, this.sacl, this.control, this.sddl);

  final String owner;
  final String group;
  final List<String>? dacl;
  final List<String>? sacl;
  final int control;
  final String sddl;

  void reportDifference(_PolicyDiagnostic after) {
    String bounded(String text, int limit) => text.length <= limit
        ? text
        : '${text.substring(0, limit)} [truncated; ${text.length} chars]';
    String aclText(List<String>? entries) => entries == null
        ? 'null'
        : entries
            .asMap()
            .entries
            .map((entry) => '[${entry.key}] ${entry.value}')
            .join('\n');
    bool sameAcl(List<String>? left, List<String>? right) =>
        (left == null) == (right == null) && aclText(left) == aclText(right);

    // Compare full values before limiting output. At most one bounded report
    // per fixture; preserve the save exception and recovery files unchanged.
    print('Synthetic Windows policy differences: '
        'owner=${owner != after.owner}, group=${group != after.group}, '
        'DACL ACEs=${!sameAcl(dacl, after.dacl)}, '
        'access SACL ACEs=${!sameAcl(sacl, after.sacl)}, '
        'DACL control=${(control & 0x150c) != (after.control & 0x150c)}');
    for (final bit in <int, String>{
      0x0004: 'PRESENT',
      0x0008: 'DEFAULTED',
      0x0100: 'AUTO_INHERIT_REQ',
      0x0400: 'AUTO_INHERITED',
      0x1000: 'PROTECTED',
    }.entries) {
      print('DACL ${bit.value}: '
          '${control & bit.key != 0} -> ${after.control & bit.key != 0}');
    }
    print('Owner SID bytes: ${bounded(owner, 256)} -> '
        '${bounded(after.owner, 256)}');
    print('Group SID bytes: ${bounded(group, 256)} -> '
        '${bounded(after.group, 256)}');
    print('DACL ACEs before:\n${bounded(aclText(dacl), 4096)}');
    print('DACL ACEs after:\n${bounded(aclText(after.dacl), 4096)}');
    print('Access SACL ACEs before:\n${bounded(aclText(sacl), 4096)}');
    print('Access SACL ACEs after:\n${bounded(aclText(after.sacl), 4096)}');
    print('SDDL before: ${bounded(sddl, 2048)}');
    print('SDDL after: ${bounded(after.sddl, 2048)}');
  }
}
