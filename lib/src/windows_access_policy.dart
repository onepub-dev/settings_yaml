/// An owned byte snapshot of the access-relevant Windows descriptor fields.
/// Internal to the Windows save adapter; auditing ACEs are not queried.
final class WindowsAccessPolicy {
  WindowsAccessPolicy({
    required this.owner,
    required this.group,
    required this.dacl,
    required this.sacl,
    required this.control,
  });

  final List<int> owner;
  final List<int> group;
  final List<List<int>>? dacl;
  final List<List<int>>? sacl;
  final int control;

  // SACL PRESENT, DEFAULTED, AUTO_INHERIT_REQ, AUTO_INHERITED, PROTECTED.
  static const saclControl = 0x2a30;
  // DACL PRESENT, DEFAULTED, AUTO_INHERIT_REQ, PROTECTED.
  static const daclControl = 0x110c;

  /// ReplaceFileW does not promise to preserve all access-SACL semantics.
  /// Reject even an empty, present ACL until its controls can be reproduced
  /// without privileges. In particular, do not try to rewrite mandatory labels.
  bool get supportedForReplacement =>
      sacl == null && control & saclControl == 0;

  bool sameIdentities(WindowsAccessPolicy other) =>
      _sameBytes(owner, other.owner) && _sameBytes(group, other.group);

  bool sameAccessSacl(WindowsAccessPolicy other) =>
      _sameAcl(sacl, other.sacl) &&
      control & saclControl == other.control & saclControl;

  /// Accept only equal DACL AI or its observed false-to-true normalization.
  /// AI is not protection: unprotected files remain subject to parent changes.
  bool preservedBy(WindowsAccessPolicy other) =>
      sameIdentities(other) &&
      _sameAcl(dacl, other.dacl) &&
      sameAccessSacl(other) &&
      control & daclControl == other.control & daclControl &&
      (control & 0x400 == 0 || other.control & 0x400 != 0);
}

bool _sameAcl(List<List<int>>? left, List<List<int>>? right) {
  if (left == null || right == null) {
    return left == right;
  }
  if (left.length != right.length) {
    return false;
  }
  for (var i = 0; i < left.length; i++) {
    if (!_sameBytes(left[i], right[i])) {
      return false;
    }
  }
  return true;
}

bool _sameBytes(List<int> left, List<int> right) {
  if (left.length != right.length) {
    return false;
  }
  for (var i = 0; i < left.length; i++) {
    if (left[i] != right[i]) {
      return false;
    }
  }
  return true;
}
