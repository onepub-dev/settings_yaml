import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;

import 'settings_yaml.dart';

/// Requires trusted parent directories and serialized writers.
void secureSavePosix(String path, String content) {
  final native = _Posix();
  final destination = File(path);
  final metadata = destination.existsSync() ? _Metadata.read(path) : null;
  var source = -1;
  var target = -1;
  var directoryFd = -1;
  Pointer<Void> originalAcl = nullptr;
  Directory? staging;
  try {
    if (metadata != null) {
      source = native.openPath(path, native.noFollow);
      originalAcl = native.getAcl(source);
    }
    staging = destination.parent.createTempSync('.settings_yaml-');
    directoryFd = native.openPath(staging.path, native.noFollow);
    native.check(native.fchmod(directoryFd, 0x1c0), 'private directory mode');
    if (Platform.isMacOS) {
      native.clearAcl(directoryFd);
    }
    if ((staging.statSync().mode & 0x1ff) != 0x1c0 ||
        staging.listSync().isNotEmpty) {
      native.fail('verify private staging directory');
    }
    final stagedPath = p.join(staging.path, 'settings');
    target = native.openPath(stagedPath,
        native.noFollow | native.create | native.exclusive | 1, 0x180);
    if (Platform.isMacOS) {
      native.clearAcl(target);
    }
    native.check(native.fchmod(target, 0x180), 'private file mode');
    if ((File(stagedPath).statSync().mode & 0x1ff) != 0x180) {
      native.fail('verify private file mode');
    }
    native.writeContent(target, content);
    if (metadata != null) {
      native.check(native.fchown(target, metadata.uid, metadata.gid),
          'preserve owner and group');
      native.check(native.fchmod(target, metadata.mode), 'preserve mode');
      native
        ..setAcl(target, originalAcl)
        ..verifyAcl(target, originalAcl);
      if (_Metadata.read(stagedPath) != metadata) {
        native.fail('verify destination metadata');
      }
    }
    native.check(native.fsync(target), 'flush settings metadata');
    // Same-filesystem POSIX rename leaves the original intact on failure.
    // An unrelated legacy .bak is never used or removed.
    File(stagedPath).renameSync(path);
  } finally {
    if (originalAcl != nullptr) {
      native.aclFree(originalAcl);
    }
    if (source >= 0) {
      native.close(source);
    }
    if (target >= 0) {
      native.close(target);
    }
    if (directoryFd >= 0) {
      native.close(directoryFd);
    }
    // Cleanup cannot mask primary errors or report failure after commit.
    try {
      staging?.deleteSync(recursive: true);
    } on FileSystemException {
      // Best effort: a leftover staging directory remains private.
    }
  }
}

@immutable
class _Metadata {
  const _Metadata(this.uid, this.gid, this.mode);

  factory _Metadata.read(String path) {
    // stat struct ABI varies across POSIX CPUs. Read numeric metadata through
    // the system utility, without a shell or PATH lookup.
    final result = Process.runSync(
        '/usr/bin/stat',
        Platform.isMacOS
            ? ['-f', '%u:%g:%Lp', path]
            : ['-c', '%u:%g:%a', '--', path]);
    if (result.exitCode != 0) {
      throw SettingsYamlException('Unable to read file ownership and mode.');
    }
    final fields = (result.stdout as String).trim().split(':');
    return _Metadata(int.parse(fields[0]), int.parse(fields[1]),
        int.parse(fields[2], radix: 8));
  }

  final int uid;
  final int gid;
  final int mode;

  @override
  bool operator ==(Object other) =>
      other is _Metadata &&
      uid == other.uid &&
      gid == other.gid &&
      mode == other.mode;

  @override
  int get hashCode => Object.hash(uid, gid, mode);
}

class _Posix {
  final libc = DynamicLibrary.process();
  late final DynamicLibrary acl =
      Platform.isMacOS ? libc : DynamicLibrary.open('libacl.so.1');

  int get noFollow => Platform.isMacOS ? 0x100 : 0x20000;
  int get create => Platform.isMacOS ? 0x200 : 0x40;
  int get exclusive => Platform.isMacOS ? 0x800 : 0x80;

  late final open = libc.lookupFunction<
      Int32 Function(Pointer<Utf8>, Int32, VarArgs<(Int32,)>),
      int Function(Pointer<Utf8>, int, int)>('open');
  late final close =
      libc.lookupFunction<Int32 Function(Int32), int Function(int)>('close');
  late final fsync =
      libc.lookupFunction<Int32 Function(Int32), int Function(int)>('fsync');
  late final write = libc.lookupFunction<
      IntPtr Function(Int32, Pointer<Uint8>, UintPtr),
      int Function(int, Pointer<Uint8>, int)>('write');
  late final _fchmodLinux = libc.lookupFunction<Int32 Function(Int32, Uint32),
      int Function(int, int)>('fchmod');
  late final _fchmodMac = libc.lookupFunction<Int32 Function(Int32, Uint16),
      int Function(int, int)>('fchmod');
  int fchmod(int fd, int mode) =>
      Platform.isMacOS ? _fchmodMac(fd, mode) : _fchmodLinux(fd, mode);
  late final fchown = libc.lookupFunction<Int32 Function(Int32, Uint32, Uint32),
      int Function(int, int, int)>('fchown');
  late final aclGetFd = acl.lookupFunction<Pointer<Void> Function(Int32),
      Pointer<Void> Function(int)>('acl_get_fd');
  late final darwinError =
      libc.lookupFunction<Pointer<Int32> Function(), Pointer<Int32> Function()>(
          '__error');
  late final aclSetFd = acl.lookupFunction<Int32 Function(Int32, Pointer<Void>),
      int Function(int, Pointer<Void>)>('acl_set_fd');
  late final aclInit = acl.lookupFunction<Pointer<Void> Function(Int32),
      Pointer<Void> Function(int)>('acl_init');
  late final aclFree = acl.lookupFunction<Int32 Function(Pointer<Void>),
      int Function(Pointer<Void>)>('acl_free');
  late final aclToText = acl.lookupFunction<
      Pointer<Utf8> Function(Pointer<Void>, Pointer<IntPtr>),
      Pointer<Utf8> Function(Pointer<Void>, Pointer<IntPtr>)>('acl_to_text');

  int openPath(String path, int flags, [int mode = 0]) {
    final encoded = path.toNativeUtf8();
    try {
      final fd = open(encoded, flags, mode);
      check(fd, 'open file without following links');
      return fd;
    } finally {
      malloc.free(encoded);
    }
  }

  void writeContent(int fd, String content) {
    final bytes = utf8.encode(content);
    final buffer = malloc<Uint8>(bytes.length);
    try {
      buffer.asTypedList(bytes.length).setAll(0, bytes);
      var offset = 0;
      while (offset < bytes.length) {
        // elementAt retains compatibility with the Dart 3.0 minimum SDK.
        // ignore: deprecated_member_use
        final remaining = buffer.elementAt(offset);
        final count = write(fd, remaining, bytes.length - offset);
        if (count <= 0) {
          fail('write settings');
        }
        offset += count;
      }
    } finally {
      malloc.free(buffer);
    }
  }

  Pointer<Void> getAcl(int fd) {
    // Resolve lazy FFI bindings and obtain the thread-local errno address
    // before the ACL call, so nothing native intervenes before reading its errno.
    final get = aclGetFd;
    final error = Platform.isMacOS ? darwinError() : nullptr.cast<Int32>();
    final value = get(fd);
    final errorCode = Platform.isMacOS ? error.value : 0;
    if (value == nullptr) {
      // Darwin returns ENOENT (2) when there is no extended ACL. Other failures
      // must still abort before replacing the destination.
      if (Platform.isMacOS && errorCode == 2) {
        return nullptr;
      }
      fail('read ACL');
    }
    return value;
  }

  void setAcl(int fd, Pointer<Void> value) {
    if (Platform.isMacOS && value == nullptr) {
      clearAcl(fd);
    } else {
      check(aclSetFd(fd, value), 'preserve ACL');
    }
  }

  void clearAcl(int fd) {
    // macOS extended ACLs are independent of POSIX mode bits. Remove inherited
    // ACEs, and verify their removal, before writing any secrets.
    // https://developer.apple.com/library/archive/documentation/System/Conceptual/ManPages_iPhoneOS/man3/acl_set_fd.3.html
    final empty = aclInit(0);
    if (empty == nullptr) {
      fail('allocate empty ACL');
    }
    try {
      setAcl(fd, empty);
      verifyAcl(fd, empty);
    } finally {
      aclFree(empty);
    }
  }

  String aclText(Pointer<Void> value) {
    if (Platform.isMacOS && value == nullptr) {
      // Compare absence only with an explicitly empty ACL, including its flags.
      // Never treat a present ACL with entries or flags as absent.
      final empty = aclInit(0);
      if (empty == nullptr) {
        fail('allocate empty ACL');
      }
      try {
        return aclText(empty);
      } finally {
        aclFree(empty);
      }
    }
    final text = aclToText(value, nullptr);
    if (text == nullptr) {
      fail('inspect ACL');
    }
    try {
      return text.toDartString();
    } finally {
      aclFree(text.cast());
    }
  }

  void verifyAcl(int fd, Pointer<Void> expected) {
    final actual = getAcl(fd);
    try {
      if (aclText(actual) != aclText(expected)) {
        fail('verify preserved ACL');
      }
    } finally {
      if (actual != nullptr) {
        aclFree(actual);
      }
    }
  }

  void check(int result, String operation) {
    if (result < 0) {
      fail(operation);
    }
  }

  Never fail(String operation) => throw SettingsYamlException(
      'Unable to $operation; destination not replaced.');
}
