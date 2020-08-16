import 'package:settings_yaml/settings_yaml.dart';

void main() {
  save();

  load();
}

void save() {
  var settings = SettingsYaml(filePath: '.settings.yaml');

  settings['dbname'] = 'billing';
  settings['dbusername'] = 'username';
  settings['dbpassword'] = 'apassword';

  settings.save();
}

void load() {
  var settings = SettingsYaml.load(filePath: '.settings.yaml');

  var dbname = settings['dbname'];
  var username = settings['dbusername'];
  var password = settings['dbpassword'];

  print('dbname $dbname, username: $username, password: $password');

  settings['another_setting'] = 'the number 10';
  settings.save();
}
