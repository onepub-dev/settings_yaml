/* Copyright (C) S. Brett Sutton - All Rights Reserved
 * Unauthorized copying of this file, via any medium is strictly prohibited
 * Proprietary and confidential
 * Written by Brett Sutton <bsutton@onepub.dev>, Jan 2022
 */

import 'package:settings_yaml/settings_yaml.dart';

Future<void> main() async {
  await save();

  await load();
}

Future<void> save() async {
  final settings = SettingsYaml.load(pathToSettings: '.settings.yaml');

  settings['dbname'] = 'billing';
  settings['dbusername'] = 'username';
  settings['dbpassword'] = 'apassword';
  settings['timeout'] = 300;
  settings['coefficient'] = 10.85;
  settings['active'] = true;

  /// Value stored at a path in the yaml
  /// one:
  ///   two: five
  settings['one.two'] = 'five';

  await settings.save();
}

Future<void> load() async {
  final settings = SettingsYaml.load(pathToSettings: '.settings.yaml');

  /// Obtain the values associated with top level keys in the yaml.
  assert(settings.validString('dbname'), 'Should be a string');
  assert(settings.validInt('timeout'), 'Should be an int');
  assert(settings.validDouble('coefficient'), 'Should be a double');
  assert(settings.validBool('active'), 'Should be a bool');

  final dbname = settings['dbname'] as String;
  // we haven't validated the dbusername and dbpassword so
  // they could be null.
  final username = settings['dbusername'] as String?;
  final password = settings['dbpassword'] as String?;

  final timeout = settings['timeout'] as int;
  final coefficient = settings['coefficient'] as double;
  final active = settings['active'] as bool;

  print('dbname $dbname, username: $username, password: $password, '
      'timeout: $timeout, coefficient: $coefficient, active: $active');

  await settings.save();
}
