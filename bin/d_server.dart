#!/usr/bin/env dart

import 'dart:io';
import 'dart:mirrors';
import 'package:d_server/d_server.dart';
import 'package:yaml/yaml.dart';

/// D_Server CLI tool for project management and development
///
/// Commands:
/// - new <project_name>: Create a new D_Server project
/// - generate <type> <name>: Generate code (controller, model, migration)
/// - server: Start the development server
/// - db:create: Create database
/// - db:drop: Drop database
/// - db:migrate: Run database migrations
/// - db:rollback: Rollback database migrations
/// - db:reset: Reset database (drop, create, migrate)
/// - version: Show version information
void main(List<String> args) async {
  if (args.isEmpty) {
    _printUsage();
    exit(1);
  }

  final command = args[0];

  try {
    switch (command) {
      case 'new':
        await _createProject(args);
        break;
      case 'generate':
      case 'g':
        await _generate(args);
        break;
      case 'server':
      case 's':
        await _startServer(args);
        break;
      case 'dev':
        await _startDevServer(args);
        break;
      case 'db:create':
        await _createDatabase(args);
        break;
      case 'db:drop':
        await _dropDatabase(args);
        break;
      case 'db:migrate':
        await _runMigrations(args);
        break;
      case 'db:rollback':
        await _rollbackMigrations(args);
        break;
      case 'db:reset':
        await _resetDatabase(args);
        break;
      case 'version':
      case '--version':
      case '-v':
        _printVersion();
        break;
      case 'help':
      case '--help':
      case '-h':
        _printUsage();
        break;
      default:
        DLogger.error('Unknown command: $command');
        _printUsage();
        exit(1);
    }
  } catch (e) {
    DLogger.error('Command failed: $e');
    exit(1);
  }
}

/// Create a new D_Server project
Future<void> _createProject(List<String> args) async {
  if (args.length < 2) {
    DLogger.error('Usage: d_server new <project_name>');
    exit(1);
  }

  final projectName = args[1];

  // Validate project name
  if (!RegExp(r'^[a-zA-Z][a-zA-Z0-9_]*$').hasMatch(projectName)) {
    DLogger.error(
        'Invalid project name. Use only letters, numbers, and underscores.');
    exit(1);
  }

  // Check if directory already exists
  final projectDir = Directory(projectName);
  if (projectDir.existsSync()) {
    DLogger.error('Directory $projectName already exists');
    exit(1);
  }

  DLogger.info('Creating D_Server project: $projectName');
  await DServer.createProject(projectName);

  DLogger.success('Project created successfully!');
  DLogger.info('');
  DLogger.info('Next steps:');
  DLogger.info('  cd $projectName');
  DLogger.info('  dart pub get');
  DLogger.info('  d_server server');
}

/// Generate code (controllers, models, migrations)
Future<void> _generate(List<String> args) async {
  if (args.length < 3) {
    DLogger.error('Usage: d_server generate <type> <name>');
    DLogger.info('Types: controller, model, migration');
    exit(1);
  }

  final type = args[1];
  final name = args[2];
  final extraArgs = args.length > 3 ? args.sublist(3) : <String>[];

  switch (type) {
    case 'controller':
      await _generateController(name);
      break;
    case 'model':
      await _generateModel(name);
      break;
    case 'migration':
      await _generateMigration(name, extraArgs);
      break;
    default:
      DLogger.error('Unknown generator type: $type');
      DLogger.info('Available types: controller, model, migration');
      exit(1);
  }
}

/// Generate a controller
Future<void> _generateController(String name) async {
  final className =
      '${_pascalCase(name.replaceAll('_controller', ''))}Controller';
  final fileName = _snakeCase(className);
  final filePath = 'lib/controllers/$fileName.dart';

  final controllerContent = '''
import 'package:d_server/d_server.dart';

class $className extends DController {
  /// GET /${_snakeCase(name.replaceAll('_controller', ''))}
  @override
  Future<Response> index() async {
    // TODO: Implement index action
    return json({'message': 'Hello from $className.index'});
  }

  /// GET /${_snakeCase(name.replaceAll('_controller', ''))}/:id
  @override
  Future<Response> show() async {
    final id = param<String>('id');
    // TODO: Implement show action
    return json({'id': id, 'message': 'Hello from $className.show'});
  }

  /// POST /${_snakeCase(name.replaceAll('_controller', ''))}
  @override
  Future<Response> create() async {
    final body = await parseBody();
    // TODO: Implement create action
    return json({'message': 'Created', 'data': body}, status: 201);
  }

  /// PUT/PATCH /${_snakeCase(name.replaceAll('_controller', ''))}/:id
  @override
  Future<Response> update() async {
    final id = param<String>('id');
    final body = await parseBody();
    // TODO: Implement update action
    return json({'id': id, 'message': 'Updated', 'data': body});
  }

  /// DELETE /${_snakeCase(name.replaceAll('_controller', ''))}/:id
  @override
  Future<Response> destroy() async {
    final id = param<String>('id');
    // TODO: Implement destroy action
    return json({'id': id, 'message': 'Deleted'});
  }
}
''';

  // Ensure controllers directory exists
  await Directory('lib/controllers').create(recursive: true);

  // Write controller file
  final file = File(filePath);
  await file.writeAsString(controllerContent);

  DLogger.success('Generated controller: $filePath');
  DLogger.info('Add routes in your main.dart:');
  DLogger.info(
      "  app.router.resource('${_snakeCase(name.replaceAll('_controller', ''))}', $className);");
}

/// Generate a model
Future<void> _generateModel(String name) async {
  final className = _pascalCase(name);
  final fileName = _snakeCase(className);
  final tableName = _pluralize(_snakeCase(className));
  final filePath = 'lib/models/$fileName.dart';

  final modelContent = '''
import 'package:d_server/d_server.dart';

class $className extends DModel {
  static String get tableName => '$tableName';

  // Example attributes - modify as needed
  String? get name => getAttribute<String>('name');
  set name(String? value) => setAttribute('name', value);

  String? get email => getAttribute<String>('email');
  set email(String? value) => setAttribute('email', value);

  DateTime? get createdAt => getAttribute<DateTime>('created_at');
  DateTime? get updatedAt => getAttribute<DateTime>('updated_at');

  // Add your model methods here

  /// Validation rules (implement as needed)
  bool validate() {
    // TODO: Add validation logic
    return name != null && name!.isNotEmpty;
  }

  /// Custom finder methods
  static Future<List<$className>> findByName(String name) async {
    return await where<$className>('name = @name', {'name': name});
  }
}
''';

  // Ensure models directory exists
  await Directory('lib/models').create(recursive: true);

  // Write model file
  final file = File(filePath);
  await file.writeAsString(modelContent);

  DLogger.success('Generated model: $filePath');
  DLogger.info('Don\'t forget to create a migration:');
  DLogger.info('  d_server generate migration create_$tableName');
}

/// Generate a migration
Future<void> _generateMigration(String name, List<String> fields) async {
  final now = DateTime.now();
  final timestamp =
      '${now.year.toString().padLeft(4, '0')}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}${now.second.toString().padLeft(2, '0')}';
  final className = _pascalCase(name);
  final fileName = '${timestamp}_${_snakeCase(name)}.dart';
  final filePath = 'db/migrate/$fileName';

  String migrationContent;

  // Generate different migration types based on name pattern
  if (name.toLowerCase().startsWith('create_')) {
    final tableName = name.toLowerCase().replaceFirst('create_', '');
    migrationContent =
        _generateCreateTableMigration(className, timestamp, tableName, fields);
  } else if (name.toLowerCase().startsWith('add_') &&
      name.toLowerCase().contains('_to_')) {
    migrationContent =
        _generateAddColumnMigration(className, timestamp, name, fields);
  } else if (name.toLowerCase().startsWith('remove_') &&
      name.toLowerCase().contains('_from_')) {
    migrationContent =
        _generateRemoveColumnMigration(className, timestamp, name, fields);
  } else {
    migrationContent = _generateGenericMigration(className, timestamp);
  }

  // Ensure migrations directory exists
  await Directory('db/migrate').create(recursive: true);

  // Write migration file
  final file = File(filePath);
  await file.writeAsString(migrationContent);

  DLogger.success('Generated migration: $filePath');

  // Generate migration index after creating migration
  await _generateMigrationRunner();

  DLogger.info('Run migration with: d_server db:migrate');
}

/// Start the development server
Future<void> _startServer(List<String> args) async {
  DLogger.info('Starting D_Server development server...');

  // Check if we're in a D_Server project
  if (!File('lib/main.dart').existsSync()) {
    DLogger.error('No main.dart found. Are you in a D_Server project?');
    exit(1);
  }

  // Start the server using dart run
  final process = await Process.start(
    'dart',
    ['run', 'lib/main.dart'],
    mode: ProcessStartMode.inheritStdio,
  );

  // Handle Ctrl+C gracefully
  ProcessSignal.sigint.watch().listen((signal) async {
    DLogger.info('Shutting down server...');
    process.kill();
    exit(0);
  });

  final exitCode = await process.exitCode;
  exit(exitCode);
}

/// Start the development server with hot reload
Future<void> _startDevServer(List<String> args) async {
  DLogger.info('Starting D_Server development server...');

  // Validate project structure
  if (!File('lib/main.dart').existsSync()) {
    DLogger.error('No main.dart found. Are you in a D_Server project?');
    exit(1);
  }

  // Load hot reload configuration
  HotReloadConfig hotReloadConfig;
  try {
    final configFile = File('config/config.yml');
    if (configFile.existsSync()) {
      final yamlString = await configFile.readAsString();
      final yamlDoc = loadYaml(yamlString);
      final yamlMap =
          yamlDoc is Map ? Map<String, dynamic>.from(yamlDoc) : null;
      final hotReloadSection = yamlMap?['hot_reload'];
      final hotReloadMap = hotReloadSection is Map
          ? Map<String, dynamic>.from(hotReloadSection)
          : null;
      hotReloadConfig = HotReloadConfig.fromYaml(hotReloadMap);
    } else {
      hotReloadConfig = HotReloadConfig(); // Use defaults
      DLogger.warning('No config.yml found, using default hot reload settings');
    }
  } catch (e) {
    DLogger.error('Failed to load config: $e');
    hotReloadConfig = HotReloadConfig(); // Fallback to defaults
  }

  // Start hot reload manager
  try {
    final hotReloadManager = HotReloadManager(hotReloadConfig);
    await hotReloadManager.start();
  } catch (e) {
    DLogger.error('Failed to start development server: $e');
    exit(1);
  }
}

/// Create database
Future<void> _createDatabase(List<String> args) async {
  try {
    DLogger.info('Creating database...');

    // Load database configuration
    final config = await DConfig.loadFromFile('config/config.yml');
    final dbConfig = {
      'ssl': config.get<bool>('database.ssl'),
      'host': config.get<String>('database.host'),
      'port': config.get<int>('database.port'),
      'database': config.get<String>('database.database'),
      'username': config.get<String>('database.username'),
      'password': config.get<String>('database.password'),
    };

    // TODO: Implement database creation
    DLogger.info('Database creation not yet fully implemented');
    DLogger.info('Please create your database manually:');
    DLogger.info(
        '  createdb ${dbConfig['database'] ?? 'your_app_development'}');
  } catch (e) {
    DLogger.error('Failed to create database: $e');
    exit(1);
  }
}

/// Drop database
Future<void> _dropDatabase(List<String> args) async {
  try {
    DLogger.info('Dropping database...');

    // Load database configuration
    final config = await DConfig.loadFromFile('config/config.yml');
    final dbConfig = {
      'ssl': config.get<bool>('database.ssl'),
      'host': config.get<String>('database.host'),
      'port': config.get<int>('database.port'),
      'database': config.get<String>('database.database'),
      'username': config.get<String>('database.username'),
      'password': config.get<String>('database.password'),
    };

    // TODO: Implement database dropping
    DLogger.info('Database dropping not yet fully implemented');
    DLogger.info('Please drop your database manually:');
    DLogger.info('  dropdb ${dbConfig['database'] ?? 'your_app_development'}');
  } catch (e) {
    DLogger.error('Failed to drop database: $e');
    exit(1);
  }
}

/// Run database migrations
Future<void> _runMigrations(List<String> args) async {
  try {
    DLogger.info('Running database migrations...');

    // Check if run_migration.dart exists
    final runMigrationFile = File('db/migrations/run_migration.dart');
    if (!await runMigrationFile.exists()) {
      DLogger.warning(
          'No migration runner found at db/migrations/run_migration.dart');
      DLogger.info(
          'Create migrations first with: d_server generate migration <name>');
      return;
    }

    // Prepare arguments for the migration script
    final migrationArgs = <String>[];

    // Check if specific migration file was requested
    if (args.length > 1) {
      final specificMigration = args[1];
      migrationArgs.add(specificMigration);
      DLogger.info('Running specific migration: $specificMigration');
    } else {
      DLogger.info('Running all pending migrations...');
    }

    // Execute the migration script
    final result = await Process.run(
      'dart',
      ['run', 'db/migrations/run_migration.dart', ...migrationArgs],
      workingDirectory: Directory.current.path,
    );

    if (result.exitCode == 0) {
      if (result.stdout.isNotEmpty) {
        DLogger.info(result.stdout);
      }
      DLogger.success('Migrations completed successfully');
    } else {
      DLogger.error('Migration failed with exit code: ${result.exitCode}');
      if (result.stderr.isNotEmpty) {
        DLogger.error('Error: ${result.stderr}');
      }
      if (result.stdout.isNotEmpty) {
        DLogger.info('Output: ${result.stdout}');
      }
    }
  } catch (e) {
    DLogger.error('Migration failed: $e');
  } finally {
    exit(1);
  }
}

/// Rollback database migrations
Future<void> _rollbackMigrations(List<String> args) async {
  try {
    DLogger.info('Rolling back database migrations...');

    // Check if run_migration.dart exists
    final runMigrationFile = File('db/migrations/run_migration.dart');
    if (!await runMigrationFile.exists()) {
      DLogger.warning(
          'No migration runner found at db/migrations/run_migration.dart');
      DLogger.info(
          'Create migrations first with: d_server generate migration <name>');
      return;
    }

    // Prepare arguments for the migration script
    final migrationArgs = ['rollback'];

    // Check if specific migration file or steps were requested
    if (args.length > 1) {
      final target = args[1];
      migrationArgs.add(target);

      // Check if it's a number (steps) or filename (specific migration)
      if (int.tryParse(target) != null) {
        DLogger.info('Rolling back $target steps');
      } else {
        DLogger.info('Rolling back specific migration: $target');
      }
    } else {
      DLogger.info('Rolling back 1 step...');
    }

    // Execute the migration script with rollback command
    final result = await Process.run(
      'dart',
      ['run', 'db/migrations/run_migration.dart', ...migrationArgs],
      workingDirectory: Directory.current.path,
    );

    if (result.exitCode == 0) {
      if (result.stdout.isNotEmpty) {
        DLogger.info(result.stdout);
      }
      DLogger.success('Rollback completed successfully');
    } else {
      DLogger.error('Rollback failed with exit code: ${result.exitCode}');
      if (result.stderr.isNotEmpty) {
        DLogger.error('Error: ${result.stderr}');
      }
      if (result.stdout.isNotEmpty) {
        DLogger.info('Output: ${result.stdout}');
      }
    }
  } catch (e) {
    DLogger.error('Rollback failed: $e');
  } finally {
    exit(1);
  }
}

/// Reset database (drop, create, migrate)
Future<void> _resetDatabase(List<String> args) async {
  try {
    DLogger.info('Resetting database...');

    // Load database configuration and connect
    final config = await DConfig.loadFromFile('config/config.yml');
    final dbConfig = {
      'host': config.get<String>('database.host'),
      'port': config.get<int>('database.port'),
      'database': config.get<String>('database.database'),
      'username': config.get<String>('database.username'),
      'password': config.get<String>('database.password'),
    };

    if (dbConfig['database'] == null) {
      DLogger.error('No database configuration found');
      exit(1);
    }

    await DatabaseConnection.fromConfig(dbConfig);

    // Initialize and reset database
    final runner = MigrationRunner();
    await runner.reset();

    DLogger.success('Database reset completed successfully');
  } catch (e) {
    DLogger.error('Database reset failed: $e');
    exit(1);
  }
}

/// Print version information
void _printVersion() {
  print('D_Server version 0.1.0');
  print('A cool web framework for Dart');
}

/// Print usage information
void _printUsage() {
  print('D_Server - Dart Web Framework');
  print('');
  print('Usage: d_server <command> [arguments]');
  print('');
  print('Commands:');
  print('  new <project_name>        Create a new D_Server project');
  print(
      '  generate <type> <name>    Generate code (controller, model, migration)');
  print('  server                    Start the production server');
  print('  dev                       Start development server with hot reload');
  print('  db:create                 Create database');
  print('  db:drop                   Drop database');
  print('  db:migrate [file]         Run database migrations');
  print('  db:rollback [steps|file]  Rollback database migrations');
  print('  db:reset                  Reset database (drop, create, migrate)');
  print('  version                   Show version information');
  print('  help                      Show this help message');
  print('');
  print('Examples:');
  print('  d_server new my_app');
  print('  d_server generate controller users');
  print('  d_server generate model user');
  print(
      '  d_server generate migration CreateUsers email:string password_digest:string');
  print('  d_server generate migration AddNameToUsers name:string');
  print('  d_server db:create');
  print('  d_server db:migrate');
  print('  d_server db:migrate 20241020_create_users.dart');
  print('  d_server db:rollback');
  print('  d_server db:rollback 3');
  print('  d_server db:rollback 20241020_create_users.dart');
  print('  d_server dev');
  print('  d_server server');
}

/// Convert string to PascalCase
String _pascalCase(String input) {
  // If input is already in PascalCase (starts with uppercase), return as-is
  if (input.isNotEmpty &&
      input[0] == input[0].toUpperCase() &&
      !input.contains('_')) {
    return input;
  }

  return input
      .split('_')
      .map((word) => word.isEmpty
          ? ''
          : word[0].toUpperCase() + word.substring(1).toLowerCase())
      .join('');
}

/// Convert string to snake_case
String _snakeCase(String input) {
  return input
      .replaceAllMapped(
          RegExp(r'([a-z])([A-Z])'), (match) => '${match[1]}_${match[2]}')
      .toLowerCase();
}

/// Simple pluralization (basic English rules)
String _pluralize(String word) {
  if (word.endsWith('y')) {
    return '${word.substring(0, word.length - 1)}ies';
  } else if (word.endsWith('s') || word.endsWith('sh') || word.endsWith('ch')) {
    return '${word}es';
  } else {
    return '${word}s';
  }
}

/// Generate create table migration content
String _generateCreateTableMigration(
    String className, String timestamp, String tableName, List<String> fields) {
  final tableBuilder = StringBuffer();
  tableBuilder.writeln('    await createTable(\'$tableName\', (table) {');
  tableBuilder.writeln('      table.serial(\'id\').primaryKey();');

  for (final field in fields) {
    final parts = field.split(':');
    if (parts.length == 2) {
      final fieldName = parts[0];
      final fieldType = parts[1];

      switch (fieldType.toLowerCase()) {
        case 'string':
          tableBuilder.writeln(
              '      table.string(\'$fieldName\').notNull().finalize();');
          break;
        case 'text':
          tableBuilder.writeln('      table.text(\'$fieldName\').finalize();');
          break;
        case 'integer':
        case 'int':
          tableBuilder
              .writeln('      table.integer(\'$fieldName\').finalize();');
          break;
        case 'boolean':
        case 'bool':
          tableBuilder.writeln(
              '      table.boolean(\'$fieldName\').defaultValue(\'false\').finalize();');
          break;
        case 'timestamp':
        case 'datetime':
          tableBuilder
              .writeln('      table.timestamp(\'$fieldName\').finalize();');
          break;
        case 'decimal':
          tableBuilder
              .writeln('      table.decimal(\'$fieldName\').finalize();');
          break;
        default:
          tableBuilder
              .writeln('      table.string(\'$fieldName\').finalize();');
      }
    }
  }

  tableBuilder.writeln('      table.timestamps();');
  tableBuilder.writeln('    });');

  return '''
import 'package:d_server/d_server.dart';

class $className extends Migration {
  @override
  String get version => '$timestamp';

  @override
  Future<void> up() async {
$tableBuilder  }

  @override
  Future<void> down() async {
    await dropTable('$tableName');
  }
}
''';
}

/// Generate add column migration content
String _generateAddColumnMigration(
    String className, String timestamp, String name, List<String> fields) {
  final parts = name.toLowerCase().split('_to_');
  final tableName = parts.length > 1 ? parts[1] : 'table_name';

  final addColumns = StringBuffer();
  final removeColumns = StringBuffer();

  for (final field in fields) {
    final fieldParts = field.split(':');
    if (fieldParts.length == 2) {
      final fieldName = fieldParts[0];
      final fieldType = fieldParts[1];

      String sqlType;
      switch (fieldType.toLowerCase()) {
        case 'string':
          sqlType = 'VARCHAR(255)';
          break;
        case 'text':
          sqlType = 'TEXT';
          break;
        case 'integer':
        case 'int':
          sqlType = 'INTEGER';
          break;
        case 'boolean':
        case 'bool':
          sqlType = 'BOOLEAN';
          break;
        case 'timestamp':
        case 'datetime':
          sqlType = 'TIMESTAMP';
          break;
        case 'decimal':
          sqlType = 'DECIMAL(10,2)';
          break;
        default:
          sqlType = 'VARCHAR(255)';
      }

      addColumns.writeln(
          '    await addColumn(\'$tableName\', \'$fieldName\', \'$sqlType\');');
      removeColumns
          .writeln('    await removeColumn(\'$tableName\', \'$fieldName\');');
    }
  }

  return '''
import 'package:d_server/d_server.dart';

class $className extends Migration {
  @override
  String get version => '$timestamp';

  @override
  Future<void> up() async {
$addColumns  }

  @override
  Future<void> down() async {
$removeColumns  }
}
''';
}

/// Generate remove column migration content
String _generateRemoveColumnMigration(
    String className, String timestamp, String name, List<String> fields) {
  final parts = name.toLowerCase().split('_from_');
  final tableName = parts.length > 1 ? parts[1] : 'table_name';

  final removeColumns = StringBuffer();
  final addColumns = StringBuffer();

  for (final field in fields) {
    final fieldParts = field.split(':');
    final fieldName = fieldParts[0];

    removeColumns
        .writeln('    await removeColumn(\'$tableName\', \'$fieldName\');');

    if (fieldParts.length == 2) {
      final fieldType = fieldParts[1];
      String sqlType;
      switch (fieldType.toLowerCase()) {
        case 'string':
          sqlType = 'VARCHAR(255)';
          break;
        case 'text':
          sqlType = 'TEXT';
          break;
        case 'integer':
        case 'int':
          sqlType = 'INTEGER';
          break;
        case 'boolean':
        case 'bool':
          sqlType = 'BOOLEAN';
          break;
        case 'timestamp':
        case 'datetime':
          sqlType = 'TIMESTAMP';
          break;
        case 'decimal':
          sqlType = 'DECIMAL(10,2)';
          break;
        default:
          sqlType = 'VARCHAR(255)';
      }
      addColumns.writeln(
          '    await addColumn(\'$tableName\', \'$fieldName\', \'$sqlType\');');
    }
  }

  return '''
import 'package:d_server/d_server.dart';

class $className extends Migration {
  @override
  String get version => '$timestamp';

  @override
  Future<void> up() async {
$removeColumns  }

  @override
  Future<void> down() async {
$addColumns  }
}
''';
}

/// Generate generic migration content
String _generateGenericMigration(String className, String timestamp) {
  return '''
import 'package:d_server/d_server.dart';

class $className extends Migration {
  @override
  String get version => '$timestamp';

  @override
  Future<void> up() async {
    // TODO: Implement up migration
    // Example:
    // await execute("""
    //   CREATE TABLE example_table (
    //     id SERIAL PRIMARY KEY,
    //     name VARCHAR(255) NOT NULL,
    //     created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
    //   )
    // """);
  }

  @override
  Future<void> down() async {
    // TODO: Implement down migration
    // Example:
    // await execute('DROP TABLE IF EXISTS example_table');
  }
}
''';
}

/// Extract class name from migration file
Future<String?> _extractClassName(File file) async {
  try {
    final content = await file.readAsString();
    final classMatch =
        RegExp(r'class\s+(\w+)\s+extends\s+Migration').firstMatch(content);
    return classMatch?.group(1);
  } catch (e) {
    DLogger.warning('Could not extract class name from ${file.path}: $e');
    return null;
  }
}

/// Generate migration runner file
Future<void> _generateMigrationRunner() async {
  final migrateDir = Directory('db/migrate');
  if (!await migrateDir.exists()) {
    return;
  }

  final files = await migrateDir
      .list()
      .where((file) => file.path.endsWith('.dart'))
      .cast<File>()
      .toList();

  files.sort((a, b) => a.path.compareTo(b.path));

  final buffer = StringBuffer();
  buffer.writeln('// Generated file - DO NOT EDIT');
  buffer.writeln(
      '// This file is automatically generated when migrations are created');
  buffer.writeln();

  buffer.writeln("import 'dart:io';");
  buffer.writeln();

  buffer.writeln("import 'package:d_server/d_server.dart';");
  buffer.writeln();

  // Generate imports for all migration files
  for (final file in files) {
    final fileName = file.path.split('/').last;
    buffer.writeln("import '../migrate/$fileName';");
  }
  buffer.writeln();

  // Generate main function
  buffer.writeln('void main(List<String> args) async {');
  buffer.writeln('  // Setup database connection');
  buffer.writeln('  try {');
  buffer.writeln(
      '    final config = await DConfig.loadFromFile(\'config/config.yml\');');
  buffer.writeln('    final dbConfig = {');
  buffer.writeln('      \'ssl\': config.get<bool>(\'database.ssl\'),');
  buffer.writeln('      \'host\': config.get<String>(\'database.host\'),');
  buffer.writeln('      \'port\': config.get<int>(\'database.port\'),');
  buffer.writeln(
      '      \'database\': config.get<String>(\'database.database\'),');
  buffer.writeln(
      '      \'username\': config.get<String>(\'database.username\'),');
  buffer.writeln(
      '      \'password\': config.get<String>(\'database.password\'),');
  buffer.writeln('    };');
  buffer.writeln('    await DatabaseConnection.fromConfig(dbConfig);');
  buffer.writeln('  } catch (e) {');
  buffer.writeln('    print(\'Failed to setup database connection: \$e\');');
  buffer.writeln('    return;');
  buffer.writeln('  }');
  buffer.writeln();
  buffer.writeln('  final command = args.isNotEmpty ? args[0] : \'migrate\';');
  buffer.writeln('  final target = args.length > 1 ? args[1] : null;');
  buffer.writeln();

  // Generate migrations map
  buffer.writeln('  final migrations = <String, Migration Function()>{');
  for (final file in files) {
    final fileName = file.path.split('/').last;
    final className = await _extractClassName(file);
    if (className != null) {
      buffer.writeln("    '$fileName': () => $className(),");
    }
  }
  buffer.writeln('  };');
  buffer.writeln();

  // Generate command handling
  buffer.writeln('  if (command == \'rollback\') {');
  buffer.writeln('    await handleRollback(target, migrations);');
  buffer.writeln('  } else {');
  buffer.writeln('    await handleMigrate(target, migrations);');
  buffer.writeln('  }');
  buffer.writeln('  exit(0);');
  buffer.writeln('}');
  buffer.writeln();

  // Generate migrate function
  buffer.writeln(
      'Future<void> handleMigrate(String? target, Map<String, Migration Function()> migrations) async {');
  buffer.writeln('  if (target != null) {');
  buffer.writeln('    // Run specific migration');
  buffer.writeln('    final migrationFactory = migrations[target];');
  buffer.writeln('    if (migrationFactory != null) {');
  buffer.writeln('      final migration = migrationFactory();');
  buffer.writeln('      print("Running migration: \$target");');
  buffer.writeln('      await migration.up();');
  buffer.writeln('      print("Migration \$target completed");');
  buffer.writeln('    } else {');
  buffer.writeln('      print("Migration \$target not found");');
  buffer.writeln('    }');
  buffer.writeln('  } else {');
  buffer.writeln('    // Run all migrations');
  buffer.writeln('    print("Running all migrations...");');
  buffer.writeln('    for (final entry in migrations.entries) {');
  buffer.writeln('      final migration = entry.value();');
  buffer.writeln('      print("Running migration: \${entry.key}");');
  buffer.writeln('      await migration.up();');
  buffer.writeln('      print("Migration \${entry.key} completed");');
  buffer.writeln('    }');
  buffer.writeln('    print("All migrations completed");');
  buffer.writeln('  }');
  buffer.writeln('}');
  buffer.writeln();

  // Generate rollback function
  buffer.writeln(
      'Future<void> handleRollback(String? target, Map<String, Migration Function()> migrations) async {');
  buffer.writeln('  if (target != null) {');
  buffer.writeln('    final steps = int.tryParse(target);');
  buffer.writeln('    if (steps != null) {');
  buffer.writeln('      // Rollback N steps');
  buffer.writeln('      print("Rolling back \$steps step(s)...");');
  buffer.writeln(
      '      final migrationList = migrations.entries.toList().reversed.take(steps);');
  buffer.writeln('      for (final entry in migrationList) {');
  buffer.writeln('        final migration = entry.value();');
  buffer.writeln('        print("Rolling back migration: \${entry.key}");');
  buffer.writeln('        await migration.down();');
  buffer.writeln('        print("Migration \${entry.key} rolled back");');
  buffer.writeln('      }');
  buffer.writeln('    } else {');
  buffer.writeln('      // Rollback specific migration');
  buffer.writeln('      final migrationFactory = migrations[target];');
  buffer.writeln('      if (migrationFactory != null) {');
  buffer.writeln('        final migration = migrationFactory();');
  buffer.writeln('        print("Rolling back migration: \$target");');
  buffer.writeln('        await migration.down();');
  buffer.writeln('        print("Migration \$target rolled back");');
  buffer.writeln('      } else {');
  buffer.writeln('        print("Migration \$target not found");');
  buffer.writeln('      }');
  buffer.writeln('    }');
  buffer.writeln('  } else {');
  buffer.writeln('    // Rollback last migration');
  buffer.writeln('    print("Rolling back last migration...");');
  buffer.writeln('    if (migrations.isNotEmpty) {');
  buffer.writeln('      final lastEntry = migrations.entries.last;');
  buffer.writeln('      final migration = lastEntry.value();');
  buffer.writeln('      print("Rolling back migration: \${lastEntry.key}");');
  buffer.writeln('      await migration.down();');
  buffer.writeln('      print("Migration \${lastEntry.key} rolled back");');
  buffer.writeln('    } else {');
  buffer.writeln('      print("No migrations to rollback");');
  buffer.writeln('    }');
  buffer.writeln('  }');
  buffer.writeln('}');

  // Write to file
  final runnerFile = File('db/migrations/run_migration.dart');
  await runnerFile.parent.create(recursive: true);
  await runnerFile.writeAsString(buffer.toString());

  DLogger.success('Generated migration runner: ${runnerFile.path}');
}
