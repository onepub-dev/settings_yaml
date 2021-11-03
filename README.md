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
  settings['numbers'] = <String>['one', 'two', 'three'];
  settings['hosts'] = <String, String>{
        'host1': 'one',
        'host2': 'two',
        'host3': 'three'
      };

  settings.save();
}
```

Loading config data.

```dart
void load() {

  /// load an existing .settings.yaml, if it doesn't exist then create it.
  var settings = SettingsYaml.load(pathToSettings: '.settings.yaml', create: true);

  var dbname = settings['dbname'] as String;
  var username = settings['dbusername']as String;
  var password = settings['dbpassword']as String;
  var timeout = settings['timeout']as String;
  var numbers = settings['numbers'] as List<String>;
  var hosts = settings['hosts'] as Map<String, String>;


  print('dbname $dbname, username: $username, password: $password, timeout: $timeout');

  /// change something
  var newPassword = ask('password');
  settings['dbpassword'] = newPassword;
  settings['hosts'] = <String, String>{
        'host1': 'one',
        'host2': 'two',
        'host3': 'three';
  settings['list'] = <String>['one', 'two', 'three'];

  settings.save();
}
```

