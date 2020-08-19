import 'package:settings_yaml/settings_yaml.dart';

void main() {
  save();

  load();
}

void save() {
  var settings = SettingsYaml.load(filePath: '.settings.yaml');

  settings['dbname'] = 'billing';
  settings['dbusername'] = 'username';
  settings['dbpassword'] = 'apassword';
  settings['timeout'] = 300;
  settings['coefficient'] = 10.85;

  settings.save();
}

void load() {
  var settings = SettingsYaml.load(filePath: '.settings.yaml');

  var dbname = settings['dbname'];
  var username = settings['dbusername'];
  var password = settings['dbpassword'];
  var timeout = settings['timeout'];
  var coefficient = settings['coefficient'];

  print('dbname $dbname, username: $username, password: $password, timeout: $timeout, coefficient: $coefficient');

  settings.save();
}
