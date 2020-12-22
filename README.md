Provide a very simple method to use yaml files for saving an apps configuration.

Saving config data:

```dart
void save() {
  /// create a new .settings.yaml
  var settings = SettingsYaml.load(pathToSettings: '.settings.yaml');

  settings['dbname'] = 'billing';
  settings['dbusername'] = 'username';
  settings['dbpassword'] = 'apassword';
  settings['timeout'] = 200;

  settings.save();
}
```

Loading config data.

```dart
void load() {

  /// load an existing .settings.yaml, if it doesn't exist then create it.
  var settings = SettingsYaml.load(pathToSettings: '.settings.yaml', create: true);

  var dbname = settings['dbname'];
  var username = settings['dbusername'];
  var password = settings['dbpassword'];
  var timeout = settings['timeout'];

  print('dbname $dbname, username: $username, password: $password, timeout: $timeout');

  /// change something

  var newPassword = ask('password');
  settings['dbpassword'] = newPassword;

  settings.save();
}
```

