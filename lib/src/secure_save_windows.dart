import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import 'settings_yaml.dart';
import 'windows_access_policy.dart';

/// Native Windows save. Requires a trusted parent and no concurrent mutation.
///
/// Access policy is preserved; auditing SACL entries are outside this contract.
/// Non-null access SACLs fail before replacement. This adapter
/// cannot safely reproduce their inheritance and privilege semantics.
void secureSaveWindows(String absolutePath, String content) {
  final bytes = utf8.encode(content);
  final api = _Windows();
  using((arena) {
    final target = absolutePath.toNativeUtf16(allocator: arena);
    final attributes = api.attributes(target);
    final attributeError = api.lastError();
    final exists = attributes != 0xffffffff;
    if (!exists && attributeError != 2) {
      api.fail('Inspect destination', absolutePath, attributeError);
    }
    if (exists && attributes & (0x400 | 0x10) != 0) {
      throw SettingsYamlException('Save destination must be a regular file.');
    }
    final original =
        exists ? api.readAccessPolicy(target, arena, absolutePath) : null;
    if (original != null && !original.supportedForReplacement) {
      throw SettingsYamlException('Cannot safely preserve Windows access-SACL '
          'policy; destination unchanged: $absolutePath');
    }

    // OW is OWNER RIGHTS, not CREATOR OWNER. Create the empty sibling with a
    // protected private DACL before preparing the destination's policy.
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
    final prefix =
        p.join(p.dirname(absolutePath), '.settings_yaml-${const Uuid().v4()}');
    final stage = '$prefix.stage';
    final backup = '$prefix.original';
    var stageCreated = false;
    var backupCreated = false;
    var retainRecovery = false;
    var contentStarted = false;
    Object? primaryError;
    try {
      // ReplaceFileW can overwrite its backup name. Under the trusted-parent,
      // no-concurrent-mutation contract, reject collisions before using it.
      if (api.attributes(backup.toNativeUtf16(allocator: arena)) !=
              0xffffffff ||
          api.lastError() != 2) {
        throw SettingsYamlException('Recovery path is not available: $backup');
      }
      var handle = api.createFile(
          stage.toNativeUtf16(allocator: arena),
          0xc0150000,
          0,
          security,
          1,
          exists && attributes & 0x4000 != 0 ? 0x4000 : 0x80,
          nullptr);
      if (api.invalid(handle)) {
        api.fail('Create private staging file', stage);
      }
      stageCreated = true;
      var open = true;
      try {
        final identity = api.inspectFile(handle, arena, stage, empty: true);
        api.verifyPrivate(handle, descriptor.value, arena, stage);
        final privatePolicy = api.readHandlePolicy(handle, arena, stage);
        if (!privatePolicy.supportedForReplacement) {
          throw SettingsYamlException('Cannot safely preserve staging '
              'access-SACL policy; no content written: $stage');
        }
        if (exists && attributes & 0x4000 != 0) {
          final stageAttributes =
              api.attributes(stage.toNativeUtf16(allocator: arena));
          if (stageAttributes == 0xffffffff || stageAttributes & 0x4000 == 0) {
            throw SettingsYamlException('Cannot create encrypted staging file; '
                'no content written: $stage');
          }
        }
        if (original != null) {
          api.prepareAccessPolicy(original, handle, arena, stage);
        }
        final expected = original ?? privatePolicy;
        api.verifyAccessPolicy(
            expected, api.readHandlePolicy(handle, arena, stage), stage);
        // Test all rights required by replacement before writing secrets.
        if (api.close(handle) == 0) {
          api.fail('Close empty staging file', stage);
        }
        open = false;
        handle = api.createFile(stage.toNativeUtf16(allocator: arena),
            0xc0150000, 0, nullptr, 3, 0x200000, nullptr);
        if (api.invalid(handle)) {
          api.fail('Reopen empty staging file', stage);
        }
        open = true;
        api.verifyIdentity(identity,
            api.inspectFile(handle, arena, stage, empty: true), stage);
        api.verifyAccessPolicy(
            expected, api.readHandlePolicy(handle, arena, stage), stage);
        if (exists && attributes & 0x4000 != 0) {
          api.verifyEncrypted(handle, arena, stage);
        }
        // From this point staging confidentiality equals the verified target
        // policy. The exclusive handle prevents other opens during writing.
        final buffer = arena<Uint8>(bytes.isEmpty ? 1 : bytes.length);
        buffer.asTypedList(bytes.length).setAll(0, bytes);
        final written = arena<Uint32>();
        var offset = 0;
        while (offset < bytes.length) {
          contentStarted = true;
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
        // ReplaceFile opens the replacement without sharing; close first.
        if (api.close(handle) == 0) {
          api.fail('Close staging file', stage);
        }
        open = false;
      } catch (_) {
        if (open) {
          // The creation handle keeps DELETE even after the DACL changes.
          // Deletion takes effect when it closes; never mark a published file.
          api.discardOnClose(handle, arena);
        }
        rethrow;
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
          final recovery = api.checkRecovery(original!, backup, arena);
          throw SettingsYamlException('ReplaceFileW failed (Windows $error). '
              'The destination may have moved. Recovery artifacts retained: '
              'original="$backup", replacement="$stage", '
              'destination="$absolutePath". $recovery');
        }
        backupCreated = true;
        // Replacement is already committed. Never remove the recovery copy
        // or claim rollback if the filesystem did not preserve the policy.
        Object? destinationError;
        try {
          final actual = api.readAccessPolicy(target, arena, absolutePath);
          api.verifyAccessPolicy(original!, actual, absolutePath);
        } on Object catch (error) {
          destinationError = error;
        }
        // Observe recovery independently even when the fresh destination open
        // fails, so its usability is never inferred from replacement success.
        final recovery = api.checkRecovery(original!, backup, arena);
        if (destinationError != null ||
            recovery != 'Recovery policy verified.') {
          retainRecovery = true;
          throw SettingsYamlException('Replacement committed, but access '
              'policy verification failed: ${destinationError ?? recovery}. '
              'Recovery artifacts retained: original="$backup", '
              'destination="$absolutePath". $recovery');
        }
      } else if (api.move(
              target: target, source: stage.toNativeUtf16(allocator: arena)) ==
          0) {
        api.fail('Move new settings file', absolutePath);
      }
    } catch (error) {
      primaryError = error;
      rethrow;
    } finally {
      if (!retainRecovery) {
        for (final ownedPath in [
          if (stageCreated) stage,
          if (backupCreated) backup,
        ]) {
          try {
            File(ownedPath).deleteSync();
          } on FileSystemException catch (error) {
            if (primaryError != null &&
                !contentStarted &&
                error.osError?.errorCode != 2 &&
                error.osError?.errorCode != 3) {
              throw SettingsYamlException('$primaryError. Empty staging '
                  'artifact could not be removed: "$ownedPath". No content '
                  'written; destination unchanged. Cleanup failed: $error');
            }
            // Do not mask a primary failure or report failure after commit.
            // Only paths created by this operation are eligible for cleanup.
          }
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
  _Windows() {
    // Resolve this symbol before any fallible call. A lazy GetProcAddress
    // lookup after a failure can overwrite the thread's native last error.
    lastError();
  }

  final kernel = DynamicLibrary.open('kernel32.dll');
  final security = DynamicLibrary.open('advapi32.dll');

  late final lastError =
      kernel.lookupFunction<Uint32 Function(), int Function()>('GetLastError');
  late final localFree = kernel.lookupFunction<
      Pointer<Void> Function(Pointer<Void>),
      Pointer<Void> Function(Pointer<Void>)>('LocalFree');
  late final attributes = kernel.lookupFunction<Uint32 Function(Pointer<Utf16>),
      int Function(Pointer<Utf16>)>('GetFileAttributesW');
  late final fileType = kernel.lookupFunction<Uint32 Function(Pointer<Void>),
      int Function(Pointer<Void>)>('GetFileType');
  late final fileInformation = kernel.lookupFunction<
      Int32 Function(Pointer<Void>, Pointer<Uint32>),
      int Function(
          Pointer<Void>, Pointer<Uint32>)>('GetFileInformationByHandle');
  late final setFileInformation = kernel.lookupFunction<
      Int32 Function(Pointer<Void>, Uint32, Pointer<Void>, Uint32),
      int Function(Pointer<Void>, int, Pointer<Void>,
          int)>('SetFileInformationByHandle');
  late final initializeAcl = security.lookupFunction<
      Int32 Function(Pointer<Void>, Uint32, Uint32),
      int Function(Pointer<Void>, int, int)>('InitializeAcl');
  late final addAce = security.lookupFunction<
      Int32 Function(Pointer<Void>, Uint32, Uint32, Pointer<Void>, Uint32),
      int Function(Pointer<Void>, int, int, Pointer<Void>, int)>('AddAce');
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
  late final sidLength = security.lookupFunction<Uint32 Function(Pointer<Void>),
      int Function(Pointer<Void>)>('GetLengthSid');
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

  List<int> inspectFile(Pointer<Void> handle, Arena arena, String path,
      {bool empty = false}) {
    // BY_HANDLE_FILE_INFORMATION contains thirteen DWORDs, including FILETIMEs.
    final info = arena<Uint32>(13);
    if (fileType(handle) != 1 || fileInformation(handle, info) == 0) {
      fail('Inspect regular staging file', path);
    }
    if (info[0] & (0x400 | 0x10) != 0 ||
        (empty && (info[8] != 0 || info[9] != 0))) {
      throw SettingsYamlException('Expected a regular '
          '${empty ? 'empty ' : ''}file: $path');
    }
    return [info[7], info[11], info[12]];
  }

  void verifyIdentity(List<int> expected, List<int> actual, String path) {
    for (var index = 0; index < expected.length; index++) {
      if (expected[index] != actual[index]) {
        throw SettingsYamlException('Staging file identity changed: $path');
      }
    }
  }

  void verifyEncrypted(Pointer<Void> handle, Arena arena, String path) {
    final info = arena<Uint32>(13);
    if (fileInformation(handle, info) == 0 || info[0] & 0x4000 == 0) {
      throw SettingsYamlException('Cannot verify encrypted staging file; '
          'no content written: $path');
    }
  }

  void discardOnClose(Pointer<Void> handle, Arena arena) {
    final disposition = arena<Uint8>()..value = 1;
    // FileDispositionInfo / FILE_DISPOSITION_INFO uses a BOOLEAN. Failure
    // falls back to path cleanup, whose prewrite failures are reported.
    setFileInformation(handle, 4, disposition.cast<Void>(), 1);
  }

  String checkRecovery(WindowsAccessPolicy original, String path, Arena arena) {
    try {
      verifyAccessPolicy(
          original,
          readAccessPolicy(path.toNativeUtf16(allocator: arena), arena, path),
          path);
      return 'Recovery policy verified.';
    } on Object catch (error) {
      return 'Recovery policy could not be verified: $error';
    }
  }

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
      Pointer<Void> handle, Pointer<Void> expected, Arena arena, String path,
      {bool protected = true}) {
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
    final control = arena<Uint16>();
    final revision = arena<Uint32>();
    if (getControl(sd.value, control, revision) == 0) {
      fail('Read private staging security control', path);
    }
    if (present.value == 0 ||
        expectedDacl.value == nullptr ||
        !sameAcl(expectedDacl.value, actualDacl.value) ||
        (control.value & 0x1000 != 0) != protected) {
      throw SettingsYamlException('Filesystem did not apply private staging '
          'ACL: $path');
    }
  }

  WindowsAccessPolicy readAccessPolicy(
      Pointer<Utf16> path, Arena arena, String displayPath) {
    final source = createFile(path, 0x20000, 7, nullptr, 3, 0x200000, nullptr);
    if (invalid(source)) {
      fail('Open destination security', displayPath);
    }
    try {
      inspectFile(source, arena, displayPath);
      return readHandlePolicy(source, arena, displayPath);
    } finally {
      close(source);
    }
  }

  WindowsAccessPolicy readHandlePolicy(
      Pointer<Void> source, Arena arena, String displayPath) {
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
    final control = arena<Uint16>();
    final revision = arena<Uint32>();
    if (getControl(sd.value, control, revision) == 0) {
      fail('Read security descriptor control', displayPath);
    }
    List<int> sid(Pointer<Void> value) {
      if (value == nullptr) {
        throw SettingsYamlException('Missing Windows security identity: '
            '$displayPath');
      }
      return List<int>.of(value.cast<Uint8>().asTypedList(sidLength(value)));
    }

    List<List<int>>? acl(Pointer<Void> value) {
      if (value == nullptr) {
        return null;
      }
      final entries = <List<int>>[];
      final ace = arena<Pointer<Uint8>>();
      for (var index = 0; index < value.cast<Uint16>()[2]; index++) {
        if (getAce(value, index, ace) == 0) {
          fail('Inspect access policy entry', displayPath);
        }
        entries.add(
            List<int>.of(ace.value.asTypedList(ace.value.cast<Uint16>()[1])));
      }
      return entries;
    }

    return WindowsAccessPolicy(
        owner: sid(owner.value),
        group: sid(group.value),
        dacl: acl(dacl.value),
        sacl: acl(sacl.value),
        control: control.value);
  }

  void prepareAccessPolicy(WindowsAccessPolicy original, Pointer<Void> stage,
      Arena arena, String path) {
    // The stage is still empty and shares the destination's parent, so native
    // inheritance is evaluated in the correct context. Do not change owner or
    // group or acquire privileges to force an otherwise unsupported policy.
    final prepared = readHandlePolicy(stage, arena, path);
    if (!original.sameIdentities(prepared)) {
      throw SettingsYamlException('Cannot safely reproduce the existing '
          'owner or group; destination unchanged: $path');
    }
    if (!original.sameAccessSacl(prepared)) {
      throw SettingsYamlException('Cannot safely reproduce the existing '
          'access-SACL policy; destination unchanged: $path');
    }
    Pointer<Void> dacl = nullptr;
    final entries = original.dacl;
    if (entries != null) {
      final length = 8 + entries.fold<int>(0, (sum, ace) => sum + ace.length);
      dacl = arena<Uint8>(length).cast<Void>();
      // ACL_REVISION_DS also supports ordinary ACEs. Preserve the ordered raw
      // ACE bytes, including every inherited flag, using native ACL routines.
      if (initializeAcl(dacl, length, 4) == 0) {
        fail('Initialize destination DACL', path);
      }
      for (final entry in entries) {
        final ace = arena<Uint8>(entry.length);
        ace.asTypedList(entry.length).setAll(0, entry);
        if (addAce(dacl, 4, 0xffffffff, ace.cast<Void>(), entry.length) == 0) {
          fail('Reproduce destination DACL entry', path);
        }
      }
    }
    final protection = original.control & 0x1000 != 0 ? 0x80000000 : 0x20000000;
    final applied =
        setSecurity(stage, 1, 4 | protection, nullptr, nullptr, dacl, nullptr);
    if (applied != 0) {
      fail('Prepare staging access policy', path, applied);
    }
    // Any unexpected native transformation rejects this empty stage; never
    // repair it and continue with secret content.
    verifyAccessPolicy(original, readHandlePolicy(stage, arena, path), path);
  }

  void verifyAccessPolicy(
      WindowsAccessPolicy original, WindowsAccessPolicy actual, String path) {
    if (!original.preservedBy(actual)) {
      throw SettingsYamlException('Windows did not preserve the existing '
          'access policy: $path');
    }
  }
}
