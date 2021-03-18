import 'package:settings_yaml/settings_yaml.dart';

void main() {
  save();

  load();
}

void save() {
  var settings = SettingsYaml.load(pathToSettings: '.settings.yaml');

  settings['dbname'] = 'billing';
  settings['dbusername'] = 'username';
  settings['dbpassword'] = 'apassword';
  settings['timeout'] = 300;
  settings['coefficient'] = 10.85;
  settings['active'] = true;

  settings.save();
}

void load() {
  var settings = SettingsYaml.load(pathToSettings: '.settings.yaml');

  assert(settings.validString('dbname'));
  assert(settings.validInt('timeout'));
  assert(settings.validDouble('coefficient'));
  assert(settings.validBool('active'));

  var dbname = settings['dbname'] as String;
  // we haven't validated the dbusername and dbpassword so
  // they could be null.
  var username = settings['dbusername'] as String?;
  var password = settings['dbpassword'] as String?;
  
  var timeout = settings['timeout'] as int;
  var coefficient = settings['coefficient'] as double;
  var active = settings['active'] as bool;

  print(
      'dbname $dbname, username: $username, password: $password, timeout: $timeout, coefficient: $coefficient, active: $active');

  settings.save();
}
