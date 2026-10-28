import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import 'settings_yaml.dart';

/// Native Windows save. Requires a trusted parent and no concurrent mutation.
///
/// Access policy is preserved; auditing SACL entries are outside this contract.
/// CAP, process-trust and access-filter policies fail before replacement.
/// This adapter cannot reproduce their privilege semantics.
void secureSaveWindows(String absolutePath, String content) {
  final api = _Windows();
  using((arena) {
    final target = absolutePath.toNativeUtf16(allocator: arena);
    final attributes = api.attributes(target);
    final exists = attributes != 0xffffffff;
    if (!exists && api.lastError() != 2) {
      api.fail('Inspect destination', absolutePath);
    }
    if (exists && attributes & (0x400 | 0x10) != 0) {
      throw SettingsYamlException('Save destination must be a regular file.');
    }

    // OW is OWNER RIGHTS, not CREATOR OWNER. Neither this directory nor the
    // file ever inherits a permissive DACL, including during creation.
    final descriptor = arena<Pointer<Void>>();
    if (api.convert(
          'D:P(A;;FA;;;OW)'.toNativeUtf16(allocator: arena),
          1,
          descriptor,
          nullptr,
        ) ==
        0) {
      api.fail('Create private security descriptor', absolutePath);
    }
    arena.onReleaseAll(() => api.localFree(descriptor.value));
    final security = arena<_SecurityAttributes>();
    security.ref
      ..length = sizeOf<_SecurityAttributes>()
      ..descriptor = descriptor.value
      ..inheritHandle = 0;
    final directory =
        p.join(p.dirname(absolutePath), '.settings_yaml-${const Uuid().v4()}');
    final stage = p.join(directory, 'settings');
    final backup = p.join(directory, 'original');
    if (api.createDirectory(
            directory.toNativeUtf16(allocator: arena), security) ==
        0) {
      api.fail('Create private staging directory', directory);
    }
    var retainRecovery = false;
    try {
      final directoryHandle = api.createFile(
          directory.toNativeUtf16(allocator: arena),
          0x20000,
          7,
          nullptr,
          3,
          0x2200000,
          nullptr);
      if (api.invalid(directoryHandle)) {
        api.fail('Open private staging directory', directory);
      }
      try {
        api.verifyPrivate(directoryHandle, descriptor.value, arena, directory);
      } finally {
        api.close(directoryHandle);
      }
      final handle = api.createFile(
          stage.toNativeUtf16(allocator: arena),
          0xc00e0000,
          0,
          security,
          1,
          exists && attributes & 0x4000 != 0 ? 0x4000 : 0x80,
          nullptr);
      if (api.invalid(handle)) {
        api.fail('Create private staging file', stage);
      }
      var open = true;
      try {
        api.verifyPrivate(handle, descriptor.value, arena, stage);
        if (exists && attributes & 0x4000 != 0) {
          final stageAttributes =
              api.attributes(stage.toNativeUtf16(allocator: arena));
          if (stageAttributes == 0xffffffff || stageAttributes & 0x4000 == 0) {
            throw SettingsYamlException('Cannot create encrypted staging file; '
                'no content written: $stage');
          }
        }
        // The restrictive creation descriptor precedes all secret data.
        final bytes = utf8.encode(content);
        final buffer = arena<Uint8>(bytes.isEmpty ? 1 : bytes.length);
        buffer.asTypedList(bytes.length).setAll(0, bytes);
        final written = arena<Uint32>();
        var offset = 0;
        while (offset < bytes.length) {
          final remaining = bytes.length - offset;
          final length = remaining > 0x40000000 ? 0x40000000 : remaining;
          // Pointer arithmetic operators require Dart 3.3; support Dart 3.0.
          // ignore: deprecated_member_use
          final chunk = buffer.elementAt(offset);
          if (api.write(handle, chunk, length, written, nullptr) == 0 ||
              written.value == 0) {
            api.fail('Write staging file', stage);
          }
          offset += written.value;
        }
        if (api.flush(handle) == 0) {
          api.fail('Flush staging file', stage);
        }
        if (exists) {
          api.copyAccessPolicy(target, handle, arena, absolutePath);
        }
        // ReplaceFile opens the replacement without sharing; close first.
        if (api.close(handle) == 0) {
          api.fail('Close staging file', stage);
        }
        open = false;
      } finally {
        if (open) {
          api.close(handle);
        }
      }
      if (exists) {
        // No IGNORE_ACL_ERRORS or IGNORE_MERGE_ERRORS flags. The unique backup
        // also makes error 1177 recoverable: Windows may already have moved the
        // original away, despite reporting failure. Never claim rollback.
        if (api.replace(target, stage.toNativeUtf16(allocator: arena),
                backup.toNativeUtf16(allocator: arena), 0, nullptr, nullptr) ==
            0) {
          final error = api.lastError();
          retainRecovery = true;
          throw SettingsYamlException('ReplaceFileW failed (Windows $error). '
              'The destination may have moved. Recovery artifacts retained: '
              'original="$backup", replacement="$stage", '
              'destination="$absolutePath".');
        }
      } else if (api.move(
              target: target, source: stage.toNativeUtf16(allocator: arena)) ==
          0) {
        api.fail('Move new settings file', absolutePath);
      }
    } finally {
      if (!retainRecovery) {
        try {
          Directory(directory).deleteSync(recursive: true);
        } on FileSystemException {
          // Cleanup must neither mask the primary error nor report a failed
          // save after commit. Any leftovers remain inside the private folder.
        }
      }
    }
  });
}

final class _SecurityAttributes extends Struct {
  @Uint32()
  external int length;
  external Pointer<Void> descriptor;
  @Int32()
  external int inheritHandle;
}

final class _Windows {
  final kernel = DynamicLibrary.open('kernel32.dll');
  final security = DynamicLibrary.open('advapi32.dll');

  late final lastError =
      kernel.lookupFunction<Uint32 Function(), int Function()>('GetLastError');
  late final localFree = kernel.lookupFunction<
      Pointer<Void> Function(Pointer<Void>),
      Pointer<Void> Function(Pointer<Void>)>('LocalFree');
  late final attributes = kernel.lookupFunction<Uint32 Function(Pointer<Utf16>),
      int Function(Pointer<Utf16>)>('GetFileAttributesW');
  late final createDirectory = kernel.lookupFunction<
      Int32 Function(Pointer<Utf16>, Pointer<_SecurityAttributes>),
      int Function(
          Pointer<Utf16>, Pointer<_SecurityAttributes>)>('CreateDirectoryW');
  late final convert = security.lookupFunction<
          Int32 Function(
              Pointer<Utf16>, Uint32, Pointer<Pointer<Void>>, Pointer<Uint32>),
          int Function(
              Pointer<Utf16>, int, Pointer<Pointer<Void>>, Pointer<Uint32>)>(
      'ConvertStringSecurityDescriptorToSecurityDescriptorW');
  late final createFile = kernel.lookupFunction<
      Pointer<Void> Function(Pointer<Utf16>, Uint32, Uint32,
          Pointer<_SecurityAttributes>, Uint32, Uint32, Pointer<Void>),
      Pointer<Void> Function(
          Pointer<Utf16>,
          int,
          int,
          Pointer<_SecurityAttributes>,
          int,
          int,
          Pointer<Void>)>('CreateFileW');
  late final close = kernel.lookupFunction<Int32 Function(Pointer<Void>),
      int Function(Pointer<Void>)>('CloseHandle');
  late final flush = kernel.lookupFunction<Int32 Function(Pointer<Void>),
      int Function(Pointer<Void>)>('FlushFileBuffers');
  late final write = kernel.lookupFunction<
      Int32 Function(Pointer<Void>, Pointer<Uint8>, Uint32, Pointer<Uint32>,
          Pointer<Void>),
      int Function(Pointer<Void>, Pointer<Uint8>, int, Pointer<Uint32>,
          Pointer<Void>)>('WriteFile');
  late final replace = kernel.lookupFunction<
      Int32 Function(Pointer<Utf16>, Pointer<Utf16>, Pointer<Utf16>, Uint32,
          Pointer<Void>, Pointer<Void>),
      int Function(Pointer<Utf16>, Pointer<Utf16>, Pointer<Utf16>, int,
          Pointer<Void>, Pointer<Void>)>('ReplaceFileW');
  late final _move = kernel.lookupFunction<
      Int32 Function(Pointer<Utf16>, Pointer<Utf16>, Uint32),
      int Function(Pointer<Utf16>, Pointer<Utf16>, int)>('MoveFileExW');
  late final getSecurity = security.lookupFunction<
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
  late final setSecurity = security.lookupFunction<
      Uint32 Function(Pointer<Void>, Uint32, Uint32, Pointer<Void>,
          Pointer<Void>, Pointer<Void>, Pointer<Void>),
      int Function(Pointer<Void>, int, int, Pointer<Void>, Pointer<Void>,
          Pointer<Void>, Pointer<Void>)>('SetSecurityInfo');
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
  late final equalSid = security.lookupFunction<
      Int32 Function(Pointer<Void>, Pointer<Void>),
      int Function(Pointer<Void>, Pointer<Void>)>('EqualSid');
  late final getControl = security.lookupFunction<
      Int32 Function(Pointer<Void>, Pointer<Uint16>, Pointer<Uint32>),
      int Function(Pointer<Void>, Pointer<Uint16>,
          Pointer<Uint32>)>('GetSecurityDescriptorControl');
  late final getAce = security.lookupFunction<
      Int32 Function(Pointer<Void>, Uint32, Pointer<Pointer<Uint8>>),
      int Function(Pointer<Void>, int, Pointer<Pointer<Uint8>>)>('GetAce');

  int move({required Pointer<Utf16> target, required Pointer<Utf16> source}) =>
      _move(source, target,
          8); // WRITE_THROUGH, deliberately no REPLACE_EXISTING.

  bool invalid(Pointer<Void> handle) =>
      handle.address == -1 ||
      handle.address == 0xffffffffffffffff ||
      handle.address == 0xffffffff;

  Never fail(String operation, String path, [int? error]) =>
      throw SettingsYamlException(
          '$operation failed (Windows ${error ?? lastError()}): $path');

  bool sameAcl(Pointer<Void> left, Pointer<Void> right) {
    if (left == nullptr || right == nullptr) {
      return left == right;
    }
    final count = left.cast<Uint16>()[2];
    if (count != right.cast<Uint16>()[2]) {
      return false;
    }
    // ACL buffers can have different unused capacity. Compare ordered ACEs;
    // order and ACE flags affect access, allocator slack does not.
    return using((arena) {
      final leftAce = arena<Pointer<Uint8>>();
      final rightAce = arena<Pointer<Uint8>>();
      for (var index = 0; index < count; index++) {
        if (getAce(left, index, leftAce) == 0 ||
            getAce(right, index, rightAce) == 0) {
          return false;
        }
        final length = leftAce.value.cast<Uint16>()[1];
        if (length != rightAce.value.cast<Uint16>()[1]) {
          return false;
        }
        final a = leftAce.value.asTypedList(length);
        final b = rightAce.value.asTypedList(length);
        for (var i = 0; i < length; i++) {
          if (a[i] != b[i]) {
            return false;
          }
        }
      }
      return true;
    });
  }

  void verifyPrivate(
      Pointer<Void> handle, Pointer<Void> expected, Arena arena, String path) {
    final actualDacl = arena<Pointer<Void>>();
    final sd = arena<Pointer<Void>>();
    final result =
        getSecurity(handle, 1, 4, nullptr, nullptr, actualDacl, nullptr, sd);
    if (result != 0) {
      fail('Verify private staging ACL', path, result);
    }
    arena.onReleaseAll(() => localFree(sd.value));
    final expectedDacl = arena<Pointer<Void>>();
    final present = arena<Int32>();
    final defaulted = arena<Int32>();
    if (getDacl(expected, present, expectedDacl, defaulted) == 0) {
      fail('Read private staging ACL', path);
    }
    if (!sameAcl(expectedDacl.value, actualDacl.value)) {
      throw SettingsYamlException('Filesystem did not apply private staging '
          'ACL; no content written: $path');
    }
  }

  void copyAccessPolicy(Pointer<Utf16> path, Pointer<Void> stage, Arena arena,
      String displayPath) {
    final source = createFile(path, 0x20000, 7, nullptr, 3, 0x200000, nullptr);
    if (invalid(source)) {
      fail('Open destination security', displayPath);
    }
    try {
      final owner = arena<Pointer<Void>>();
      final group = arena<Pointer<Void>>();
      final dacl = arena<Pointer<Void>>();
      final sd = arena<Pointer<Void>>();
      // OWNER, GROUP, DACL, LABEL, ATTRIBUTE, SCOPE, PROCESS_TRUST_LABEL,
      // ACCESS_FILTER. Query failure (including unsupported OS) is fail-closed.
      final result =
          getSecurity(source, 1, 0x1f7, owner, group, dacl, nullptr, sd);
      if (result != 0) {
        fail('Read destination access policy', displayPath, result);
      }
      arena.onReleaseAll(() => localFree(sd.value));
      final sacl = arena<Pointer<Void>>();
      final present = arena<Int32>();
      final defaulted = arena<Int32>();
      if (getSacl(sd.value, present, sacl, defaulted) == 0) {
        fail('Inspect access policy', displayPath);
      }
      var accessSaclFlags = 0;
      if (present.value != 0 && sacl.value != nullptr) {
        final count = sacl.value.cast<Uint16>()[2];
        final ace = arena<Pointer<Uint8>>();
        for (var index = 0; index < count; index++) {
          if (getAce(sacl.value, index, ace) == 0) {
            fail('Inspect access policy entry', displayPath);
          }
          final type = ace.value.value;
          // Only mandatory labels and resource attributes can be restored
          // without changing privileged policy semantics. Unknown ACEs fail.
          if (type != 0x11 && type != 0x12) {
            throw SettingsYamlException('Cannot preserve Windows access policy '
                'ACE type $type; destination unchanged: $displayPath');
          }
          accessSaclFlags |= type == 0x11 ? 0x10 : 0x20;
        }
      }
      final control = arena<Uint16>();
      final revision = arena<Uint32>();
      if (getControl(sd.value, control, revision) == 0) {
        fail('Read security descriptor control', displayPath);
      }
      final protection = control.value & 0x1000 != 0 ? 0x80000000 : 0x20000000;
      final applied = setSecurity(stage, 1, 7 | accessSaclFlags | protection,
          owner.value, group.value, dacl.value, sacl.value);
      if (applied != 0) {
        fail('Preserve destination access policy', displayPath, applied);
      }
      final newOwner = arena<Pointer<Void>>();
      final newGroup = arena<Pointer<Void>>();
      final newDacl = arena<Pointer<Void>>();
      final newSd = arena<Pointer<Void>>();
      final checked = getSecurity(
          stage, 1, 0x1f7, newOwner, newGroup, newDacl, nullptr, newSd);
      if (checked != 0) {
        fail('Verify preserved access policy', displayPath, checked);
      }
      arena.onReleaseAll(() => localFree(newSd.value));
      final newSacl = arena<Pointer<Void>>();
      final newControl = arena<Uint16>();
      if (getSacl(newSd.value, present, newSacl, defaulted) == 0 ||
          getControl(newSd.value, newControl, revision) == 0) {
        fail('Verify security descriptor', displayPath);
      }
      if (equalSid(owner.value, newOwner.value) == 0 ||
          equalSid(group.value, newGroup.value) == 0 ||
          !sameAcl(dacl.value, newDacl.value) ||
          !sameAcl(sacl.value, newSacl.value) ||
          (control.value & 0x1000) != (newControl.value & 0x1000)) {
        throw SettingsYamlException('Windows did not reproduce the existing '
            'access policy exactly; destination unchanged: $displayPath');
      }
    } finally {
      close(source);
    }
  }
}
