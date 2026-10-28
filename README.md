# Settings YAML

Read and write an application's YAML configuration using Dart values.

```dart
import 'package:settings_yaml/settings_yaml.dart';

Future<void> main() async {
  final settings = SettingsYaml.load(pathToSettings: '.settings.yaml');
  settings['name'] = 'billing';
  settings['timeout'] = 200;
  settings['hosts'] = {'primary': 'localhost'};
  settings['tags'] = ['local', 'development'];
  await settings.save();

  final reloaded = SettingsYaml.load(pathToSettings: '.settings.yaml');
  final timeout = reloaded.asInt('timeout');
  final tags = reloaded.asStringList('tags');
  final hosts = reloaded['hosts'] as Map<String, dynamic>;
  print('$timeout $tags $hosts');
}
```

The parent directory must already exist. Missing files load as empty settings
and are created when saved. Await `save()` to observe errors.

## Nested settings

`[]` converts YAML collections to Dart maps and lists. Ordinary Dart maps and
lists assigned through `[]=` retain their identity: edits through a getter are
saved. Getters validate these collections, and saving validates them again.
Selectors read current settings values and normalize scalar map keys consistently.

```dart
final settings = SettingsYaml.fromString(
  filePath: 'settings.yaml',
  content: '''
database:
  host: localhost
people:
  - person:
    name: Brett
  - person:
    name: Jane
''',
);
final host = settings.selectAsString('database.host');
final name = settings.selectAsString('people.person[1].name');
final database = settings.selectAsMap('database');
final people = settings.selectAsList('people');
```

List selectors use the first map key as their label (`person` above), followed
by a zero-based index. Empty-document traversal throws `PathNotFoundException`;
`selectorExists()` returns false for that case.

## Serialization and resource limits

Version 8.3.2 writes YAML-compatible JSON flow syntax with a YAML header comment.
Keys and strings are escaped, including control characters and YAML line
separators. Formatting, comments and anchors from the original file are not
preserved. Supported values are null, bool, int, finite double, String, List and
Map, recursively. Unpaired UTF-16 surrogates and other object types are rejected.
Scalar map keys (including wrapped `YamlScalar` keys) are normalized to strings
for YAML conversion, selectors and saving; keys that collide after normalization
(such as `1` and `"1"`) and collection keys are rejected.

Recursive conversion through `[]`, `asStringList`, `traverse`, typed selectors,
and saving rejects cycles and limits each operation to 10,000 expanded nodes
(including keys), nesting depth 64, and 1,048,576 aggregate UTF-16 string units
(including keys). Repeated aliases count on each expansion. Serialized output
is additionally limited to 8,388,608 UTF-16 units before the header. Invalid or
oversized values raise `SettingsYamlException` before saving touches the filesystem.
Direct access to mutable `valueMap` bypasses conversion; save still validates it.

These limits do not bound YAML parsing or file reading. Applications accepting
untrusted documents must separately limit input size and execution resources.

## Filesystem security and recovery

Save adapters are implemented for Linux, macOS and Windows. Native macOS and
Windows validation is still outstanding: this working patch is not release-ready.
Other operating systems reject saves; reading does not require a save adapter.

Saving requires a trusted parent directory and trusted ancestor path components.
Callers must prevent concurrent writers and hostile directory, symlink or mount
changes. This API is not a filesystem sandbox: reads follow links, parent links
are resolved normally, and paths are not protected by descriptor-relative APIs.
Saving rejects an existing symlink or nonregular destination, including dangling
links. It does not claim resistance to races in attacker-controlled directories.

On Linux and macOS, the complete validated output is written inside a fresh
temporary directory in the destination's parent. The empty directory is restricted
to mode 0700 and checked before creating the staged file. On macOS, inherited
extended ACLs are explicitly cleared and verified on both directory and file before
writing settings. On Linux, restrictive mode bits mask inherited POSIX ACL grants.
New files receive mode 0600. Existing owner, group, mode (including 0640) and ACLs
are copied to the staged file and verified before replacement. If these cannot be
read, applied or verified, that save fails before replacing the destination.
The POSIX adapter uses `/usr/bin/stat` for numeric ownership/mode information;
Linux also requires `libacl.so.1` to preserve existing ACLs. It does not invoke a
shell or request elevated privileges.

After flushing the staged POSIX file, a same-filesystem rename replaces the
destination. The original remains in place on pre-replacement failure. There is
no copy fallback or deliberate removal of the destination before rename.

On Windows, `CreateFileW` creates a unique sibling stage directly in the
destination's parent with `CREATE_NEW`, exclusive sharing and an explicit
protected owner-only DACL. Its private policy and file identity are checked while
empty. For an existing destination, the empty stage adopts the original DACL and
protected/unprotected state under the same parent, then verifies the complete
access policy. It is closed and reopened with the rights needed for replacement;
identity and policy are checked again before writing settings. A mismatch or
denied reopen discards the empty stage and leaves the destination unchanged.
If the OS also denies empty-stage cleanup, the error reports its path and confirms
that no content was written.
Existing owner and group must match the stage; differing identities fail before
writing. The stage adopts the original reader policy before writing, including
access for existing authorized readers. Those readers may access staging content
after its exclusive handle closes and before replacement. Staging is therefore
not owner-only until commit for existing files. New files retain the private DACL.
Access-SACL policies, including
mandatory labels, resource attributes, central access policies, process-trust and
access-filter ACEs, are currently unsupported and rejected before replacement.
Even an empty non-null access SACL is rejected: this adapter cannot safely
reproduce its semantics without further validation. When the queried access SACL
is null, descriptor-wide SACL control bits alone do not block saving; they can
describe policy outside the queried access subset. Metadata reads or updates
denied by the OS also fail. Audit-only SACL entries are outside the preservation
contract. Existing encrypted files use
encrypted staging.

Replacement uses `ReplaceFileW` without ACL-ignore flags, preserving the existing
DACL through replacement, with a unique recovery backup in the destination's
parent. Before writing and through a fresh destination open after commitment,
the adapter verifies owner, group, ordered DACL ACE
bytes (including inheritance flags), relevant DACL controls, and that the access
SACL remains null. SACL control differences are ignored when both queried access SACLs
are null; introduction of any non-null access SACL fails verification. The only
permitted DACL control change is `AUTO_INHERITED` from false to true; true to false
is rejected. This records participation in Windows automatic
inheritance and does not change DACL protection. Unprotected files remain subject
to later inheritable parent grants and denials. This exception does not promise
identical historical descriptor bits or behavior under every legacy inheritance
operation.

On a replacement error or post-commit verification failure, the exception reports
destination and recovery paths and all recovery artifacts are retained. The
original may already have moved; a verification failure is not a rollback and
cannot guarantee that the old policy remains active. Inspect those paths before
manual recovery. Recovery policy is checked independently, including when the
fresh destination open fails; an unavailable or unverifiable backup is reported.
New files use a same-volume move that does not overwrite an
unexpectedly existing destination.

The sibling-stage approach remains unproven on native Windows. Release requires
native inherited and mixed explicit/inherited ACL tests, parent grants and
revocations, actual access checks with a nonowner token, and failure/recovery
validation. Linux tests cannot establish these Windows guarantees. Policies that
deny the rights required to reopen or replace a file can fail even when ordinary
in-place writing would be allowed; there is no in-place fallback.

Existing `.bak` files are untouched. On POSIX, atomic replacement keeps the old
file available until commit, replacing the former move-to-`.bak` recovery scheme.
Cleanup is best effort: it cannot hide the primary error or turn a completed
replacement into a reported rollback. A process crash or cleanup failure can leave
staging artifacts for manual removal. There is no directory fsync or guarantee of
durability across power loss. Hard-link relationships and unrelated extended
attributes are not preserved. Unusual network filesystems or access-control models
outside the platform adapter's checks are not a supported security boundary.
