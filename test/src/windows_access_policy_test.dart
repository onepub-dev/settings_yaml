import 'package:settings_yaml/src/windows_access_policy.dart';
import 'package:test/test.dart';

void main() {
  WindowsAccessPolicy policy({
    List<int> owner = const [1, 2],
    List<int> group = const [3, 4],
    List<List<int>>? dacl = const [
      [0, 0, 4, 0],
      [0, 16, 4, 0]
    ],
    List<List<int>>? sacl,
    int control = 4,
  }) =>
      WindowsAccessPolicy(
          owner: owner, group: group, dacl: dacl, sacl: sacl, control: control);

  test('DACL AI accepts equality and false to true only', () {
    expect(policy().preservedBy(policy()), isTrue);
    expect(policy().preservedBy(policy(control: 0x404)), isTrue);
    expect(policy(control: 0x404).preservedBy(policy(control: 0x404)), isTrue);
    expect(policy(control: 0x404).preservedBy(policy()), isFalse);
  });

  test('all other DACL controls remain strict in both directions', () {
    for (final bit in [4, 8, 0x100, 0x1000]) {
      final changed = policy(control: 4 ^ bit);
      expect(policy().preservedBy(changed), isFalse, reason: 'bit $bit');
      expect(changed.preservedBy(policy()), isFalse, reason: 'bit $bit');
    }
  });

  test('owner, group, ACE bytes, order, flags and nullness remain strict', () {
    for (final changed in [
      policy(owner: [1, 3]),
      policy(group: [3, 5]),
      policy(dacl: [
        [0, 0, 4, 1],
        [0, 16, 4, 0]
      ]),
      policy(dacl: [
        [0, 16, 4, 0],
        [0, 0, 4, 0]
      ]),
      policy(dacl: [
        [0, 0, 4, 0],
        [0, 0, 4, 0]
      ]),
      policy(dacl: [
        [0, 0, 4, 0]
      ]),
      policy(dacl: null),
      policy(dacl: []),
      policy(sacl: []),
      policy(sacl: [
        [0x11, 0, 4, 0]
      ]),
    ]) {
      expect(policy().preservedBy(changed), isFalse);
      expect(changed.preservedBy(policy()), isFalse);
    }
    expect(policy(dacl: null).preservedBy(policy(dacl: [])), isFalse);
    final labeled = policy(sacl: [
      [0x11, 0, 4, 0],
      [0x12, 0, 4, 0]
    ]);
    expect(
        labeled.preservedBy(policy(sacl: [
          [0x12, 0, 4, 0],
          [0x11, 0, 4, 0]
        ])),
        isFalse);
    expect(
        labeled.preservedBy(policy(sacl: [
          [0x11, 16, 4, 0],
          [0x12, 0, 4, 0]
        ])),
        isFalse);
  });

  test('null access SACL ignores descriptor-wide SACL controls', () {
    for (final bits in [0, 0x10, 0x20, 0x200, 0x800, 0x2000, 0x2a30]) {
      final original = policy(control: 4 | bits);
      expect(original.supportedForReplacement, isTrue, reason: 'bits $bits');
      expect(original.sameAccessSacl(policy()), isTrue, reason: 'bits $bits');
      expect(original.preservedBy(policy()), isTrue, reason: 'bits $bits');
      expect(policy().preservedBy(original), isTrue, reason: 'bits $bits');
    }
  });

  test('non-null access SACLs reject before replacement and on introduction',
      () {
    // SYSTEM_MANDATORY_LABEL_ACE: no-write-up, S-1-16-8192 (medium).
    const mandatoryLabel = [
      0x11,
      0,
      20,
      0,
      1,
      0,
      0,
      0,
      1,
      1,
      0,
      0,
      0,
      0,
      0,
      16,
      0,
      32,
      0,
      0
    ];
    for (final sacl in <List<List<int>>>[
      [],
      [mandatoryLabel]
    ]) {
      for (final bits in [0, 0x10, 0x2a30]) {
        final changed = policy(sacl: sacl, control: 4 | bits);
        expect(changed.supportedForReplacement, isFalse);
        final original = policy(control: 4 | bits);
        expect(original.sameAccessSacl(changed), isFalse);
        expect(original.preservedBy(changed), isFalse);
        expect(changed.preservedBy(original), isFalse);
      }
    }
    for (final type in [0x11, 0x12, 0x13, 0x14, 0x15, 0xff]) {
      expect(
          policy(sacl: [
            [type, 0, 4, 0]
          ]).supportedForReplacement,
          isFalse);
    }
  });

  test('non-null access SACL comparison retains strict control checks', () {
    for (final bit in [0x10, 0x20, 0x200, 0x800, 0x2000]) {
      final original = policy(sacl: []);
      final changed = policy(sacl: [], control: 4 | bit);
      expect(original.sameAccessSacl(changed), isFalse);
      expect(original.preservedBy(changed), isFalse);
      expect(changed.preservedBy(original), isFalse);
    }
  });
}
