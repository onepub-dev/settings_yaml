Provide a very simple method to use yaml files for reading/writing an app's configuration.

# Saving a config data

```dart
void save() {
  /// create a new .settings.yaml
  var settings = SettingsYaml.load(pathToSettings: '.settings.yaml');

  settings['dbname'] = 'billing';
  settings['dbusername'] = 'username';
  settings['dbpassword'] = 'apassword';
  settings['timeout'] = 200;
  settings['ats'] = <String>['cat', 'bat', 'rat'];
  settings['hosts'] = <String, String>{
        'host1': 'one',
        'host2': 'two',
        'host3': 'three'
      };

  settings.save();
}
```

# Loading config data

```dart
void load() {

  /// load an existing .settings.yaml, if it doesn't exist then create it.
  var settings = SettingsYaml.load(pathToSettings: '.settings.yaml', create: true);

  /// Access simple top level keys.
  var dbname = settings['dbname'] as String;
  var username = settings['dbusername']as String;
  var password = settings['dbpassword']as String;
  var timeout = settings['timeout']as String;
  var ats = settings['ats']; // List<dynamic>


  
  List<String> atsAsString = settings.asStringList['ats'];
  var hosts = settings['hosts'] as Map<String, String>;

  settings['a_String'] = 'hello world';
  settings['an_int'] = 10;
  settings['a_double'] = 10.0;
  settings['a_bool'] = true;

  var a_String = settings.asString('a_String');
  var an_int = settings.asInt('an_int');
  var a_double = settings.asDoule('a_double');
  var a_bool = settings.asBool('a_bool');


  print('dbname $dbname, username: $username, password: $password, timeout: $timeout');

  /// change something
  var newPassword = ask('password');
  settings['dbpassword'] = newPassword;

  /// Write a map into a top level key.
  settings['hosts'] = <String, String>{
        'host1': 'one',
        'host2': 'two',
        'host3': 'three';
  settings['ats'] = <String>['cat', 'bat', 'rat'];

  
  settings.save();

  /// We can access a value at a path using the 'selectAsXxx' methods.
  settings.selectAsString('hosts.host1');
}
```

# Access nested content

SettingsYaml also provides access to nested attributes using path selectors:

```dart
 var content = '''name: brett
hostname: slayer
port: 10
active: true
volume: 10.0
imageid: "65385002e970"
people:
  - person:
    name: brett
  - person:
    name: john
''';

    var settings = SettingsYaml.fromString(content: content, filePath: path);
    // use a path selector to read an attribute.
    expect(settings.selectAsString('people.person[0].name'), equals('brett'));
    expect(settings.selectAsString('people.person[1].name'), equals('john'));
```    

Each selector is made up of a word.

To access an element in a list use 'word[n]'.
where 'n' is the nth instance of the word in a yaml array.


e.g.
```
one:
  - two
  - two
    three:
      name: brett
      password: abc123

```

To return the value of four

```dart
settings.selectAsString('one.two[1].three.name') == 'brett'
settings.selectAsString('one.two[1].three.password') == 'abc123'
```

You can also get a Dart map or list:

```dart
settings.selectAsString('one.two[1].three') as Map;
settings.selectAsString('one')  as List;
```



