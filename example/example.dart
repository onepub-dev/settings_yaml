import 'package:simpleyaml/simpleyaml.dart';

void main() {
  save();

  load();
}

void save() {
  var settings = SimpleYaml(filePath: '.settings.yaml');

  settings['dbname'] = 'billing';
  settings['dbusername'] = 'username';
  settings['dbpassword'] = 'apassword';

  settings.save();
}

void load() {
  var settings = SimpleYaml.load(filePath: '.settings.yaml');

  var dbname = settings['dbname'];
  var username = settings['dbusername'];
  var password = settings['dbpassword'];

  print('dbname $dbname, username: $username, password: $password');
}
