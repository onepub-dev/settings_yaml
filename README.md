Provide a very simple method to use yaml files for saving an apps configuration.

Saving config data:

```dart
void save() {
  /// create a new .settings.yaml
  var settings = SimpleYaml(filePath: '.settings.yaml');

  settings['dbname'] = 'billing';
  settings['dbusername'] = 'username';
  settings['dbpassword'] = 'apassword';

  settings.save();
}
```

Loading config data.

```dart
void load() {

  /// load an existing .settings.yaml
  var settings = SimpleYaml.load(filePath: '.settings.yaml');

  var dbname = settings['dbname'];
  var username = settings['dbusername'];
  var password = settings['dbpassword'];

  print('dbname $dbname, username: $username, password: $password');

  /// change something

  var newPassword = ask('password');
  settings['dbpassword'] = newPassword;

  settings.save();
}
```

