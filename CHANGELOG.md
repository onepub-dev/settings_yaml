# 5.0.0-beta.1
- updated to dcli_core 2.0.0 and dart 2.18
# 4.0.0
- moved to dcli_core 1.34 and dart 2.16.

# 3.5.0
- upgraded to dcli_core 1.20.2 which has fixed for running under dart 2.12.
- cleaned up lint warnings.

# 3.4.2
- Fixed a bug when setting a value you couldn't retrieve the same value with out saving/reloading.

# 3.4.1
Fixed a bug for the save method on Windows as it was trying to move the settings file whilst it still had it open.

# 3.4.0
- removed local file utils code and move to using dcli_core and its associated improved errors. moved to lint_hard and cleaned up found errors.

# 3.3.1
- updated the readme with some additional examples.

# 3.3.0
- Added ability to read a yaml attribute via a selection path. e.g. 'dependencies.dcli.path'

# 3.2.0
- Added defaults to each of the 'as' methods to make it easier to handle settings file that are empty.

# 3.1.1
- Added method asStringList to make it easier to extract a list of strings from the yaml without having to do lots of casting.

# 3.1.0
- Added support for lists and single level maps.

# 3.0.6
Fixed another bug related to empty content.

# 3.0.5
Fixed an npe when the document is passed empty content.

# 3.0.4
Fixed a bug where string that looked like no.s are being imported as numbers rather than strings. We know quote strings to ensure this.

# 3.0.3
upgraded to release version of uuid.

# 3.0.3
Added examples of using the validXXX methods.

# 3.0.2
Added methods validXXX which lets you check that a key exists, has a value and that it is a specific type.

# 3.0.1
stable release of nnbd.

# 3.0.1-nullsafety.1
because I can't spell.

# 3.0.0-nullsafety.1
upgraded to latest packags.
removed unnecessary null checks


# 3.0.0-nullsaftey.0
Converted to null saftey with some non-null safe dependencies.

# 2.1.5
Fixed a bug when trying to load a settings file that existed but was empty.


# 2.1.4
Corrected the constructor calls on the readme page.

# 2.1.3
reduced the min dart sdk to 2.7.

# 2.1.2
cleaned up the logic of the 'load' method.
It no longer creates the settings file if it doesn't exists. We leave that to the save method.

# 2.1.1
upgraded uuid version.

# 2.1.0
Removed the projects dependency on dcli to reduce the chance of circular dependency conflicts.

# 2.0.1
upgraded to dcli

# 2.0.0
Further simplification of the api.
updated example and test to reflect the api changes. Added doco and test for doubles.
Improved the api doco with examples. 
Fixed the readme to use the revised class name. 
Added an integer example.

# 1.0.6
Updated the readme to include more complete example.

# 1.0.5
Renamed project from SimpleYaml to settings_yaml to better reflect its usage and improve its discoverablity in pub.dev.
Small improvement to the README.md

# 1.0.4
Moved project to settings_yaml.

# 1.0.3
added logic to handle loading an empty settings file.

# 1.0.2
load was failig to create the file if create was true.

# 1.0.1
Added examples.
Change the ctor to take a named arg for consistency.

# 1.0.0
cleanup
Create LICENSE

# 1.0.0 
first commit 
## 1.0.0

- Initial version, created by Stagehand
