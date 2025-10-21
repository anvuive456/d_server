import 'dart:io';
import '../orm/database_connection.dart';
import '../core/logger.dart';
import 'migration.dart';

/// Migration runner for managing database schema changes
///
/// Handles running pending migrations, rolling back migrations,
/// and tracking migration status in the database.
///
/// ## Usage
///
/// ```dart
/// final runner = MigrationRunner();
///
/// // Run all pending migrations
/// await runner.migrate();
///
/// // Rollback last migration
/// await runner.rollback();
///
/// // Get migration status
/// final status = await runner.status();
/// ```
class MigrationRunner {
  static final ScopedLogger _logger = DLogger.scoped('MIGRATION_RUNNER');

  final DatabaseConnection db;

  MigrationRunner({DatabaseConnection? connection})
      : db = connection ?? DatabaseConnection.defaultConnection;

  /// Initialize the migration system by creating schema_migrations table
  Future<void> initialize() async {
    final exists = await db.tableExists('schema_migrations');

    if (!exists) {
      _logger.info('Creating schema_migrations table');
      await db.execute('''
        CREATE TABLE schema_migrations (
          version VARCHAR(255) PRIMARY KEY,
          name VARCHAR(255) NOT NULL,
          migrated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
        )
      ''');
      _logger.success('Created schema_migrations table');
    }
  }

  /// Run all pending migrations
  Future<void> migrate() async {
    await initialize();

    final pendingMigrations = await _getPendingMigrations();

    if (pendingMigrations.isEmpty) {
      _logger.info('No pending migrations');
      return;
    }

    _logger.info('Running ${pendingMigrations.length} pending migrations');

    for (final migration in pendingMigrations) {
      await migration.migrate();
    }

    _logger.success('All migrations completed');
  }

  /// Rollback the last migration
  Future<void> rollback({int steps = 1}) async {
    await initialize();

    final completedMigrations = await _getCompletedMigrations();

    if (completedMigrations.isEmpty) {
      _logger.info('No migrations to rollback');
      return;
    }

    final migrationsToRollback = completedMigrations.take(steps).toList();

    _logger.info('Rolling back ${migrationsToRollback.length} migrations');

    for (final migration in migrationsToRollback) {
      await migration.rollback();
    }

    _logger.success('Rollback completed');
  }

  /// Reset database by rolling back all migrations and re-running them
  Future<void> reset() async {
    _logger.info('Resetting database');

    // Rollback all migrations
    final completedMigrations = await _getCompletedMigrations();
    for (final migration in completedMigrations) {
      await migration.rollback();
    }

    // Re-run all migrations
    await migrate();

    _logger.success('Database reset completed');
  }

  /// Get migration status
  Future<MigrationStatus> status() async {
    await initialize();

    final allMigrations = await _getAllMigrations();
    final completedVersions = await _getCompletedVersions();

    final completed = <Migration>[];
    final pending = <Migration>[];

    for (final migration in allMigrations) {
      if (completedVersions.contains(migration.version)) {
        completed.add(migration);
      } else {
        pending.add(migration);
      }
    }

    return MigrationStatus(
      completed: completed,
      pending: pending,
      total: allMigrations.length,
    );
  }

  /// Get all migration files from db/migrate directory
  Future<List<Migration>> _getAllMigrations() async {
    final migrations = <Migration>[];
    final migrateDir = Directory('db/migrate');

    if (!await migrateDir.exists()) {
      _logger.warning('Migration directory db/migrate does not exist');
      return migrations;
    }

    final files = await migrateDir.list().toList();
    final dartFiles = files
        .where((file) => file.path.endsWith('.dart'))
        .cast<File>()
        .toList();

    // Sort by filename (which should contain timestamp)
    dartFiles.sort((a, b) => a.path.compareTo(b.path));

    for (final file in dartFiles) {
      try {
        // Load migration class dynamically
        final migration = await _loadMigrationFromFile(file);
        if (migration != null) {
          migrations.add(migration);
        }
      } catch (e) {
        _logger.error('Failed to load migration ${file.path}: $e');
      }
    }

    return migrations;
  }

  /// Load migration class from file using MigrationIndex
  Future<Migration?> _loadMigrationFromFile(File file) async {
    try {
      final content = await file.readAsString();

      // Extract version from filename
      final filename = file.path.split('/').last;
      final versionMatch = RegExp(r'^(\d+)_').firstMatch(filename);
      if (versionMatch == null) {
        _logger.warning('Could not extract version from filename: $filename');
        return null;
      }

      final version = versionMatch.group(1)!;

      // Extract class name
      final classMatch =
          RegExp(r'class\s+(\w+)\s+extends\s+Migration').firstMatch(content);
      if (classMatch == null) {
        _logger.warning('Could not find Migration class in file: ${file.path}');
        return null;
      }

      final className = classMatch.group(1)!;

      // Use dynamic loading from migration index
      final migration = await _loadFromMigrationIndex(className);
      if (migration != null) {
        _logger.info('Loaded migration: $className (version: $version)');
        return migration;
      } else {
        _logger.warning('Migration class $className not found in index');
        return null;
      }
    } catch (e) {
      _logger.error('Failed to load migration file ${file.path}: $e');
      return null;
    }
  }

  /// Load migration from db/migrations/migration_index.dart
  Future<Migration?> _loadFromMigrationIndex(String className) async {
    try {
      final indexFile = File('db/migrations/migration_index.dart');
      if (!await indexFile.exists()) {
        _logger.warning(
            'Migration index not found at db/migrations/migration_index.dart');
        _logger.info('Run "generate migration" to create index');
        return null;
      }

      final content = await indexFile.readAsString();

      // Check if class exists in switch case
      final casePattern = RegExp(
        "case\\s*['\"]" +
            RegExp.escape(className) +
            "['\"]:\\s*return\\s+" +
            RegExp.escape(className) +
            "\\(\\);",
        multiLine: true,
      );

      if (!casePattern.hasMatch(content)) {
        return null;
      }

      // Find class definition
      final classPattern = RegExp(
        r'class\s+' +
            RegExp.escape(className) +
            r'\s+extends\s+Migration\s*\{.*?\n\}',
        multiLine: true,
        dotAll: true,
      );

      final classMatch = classPattern.firstMatch(content);
      if (classMatch == null) {
        return null;
      }

      // Extract version from class definition
      final versionPattern =
          RegExp("get\\s+version\\s*=>\\s*['\"]([0-9]+)['\"]");
      final versionMatch = versionPattern.firstMatch(classMatch.group(0)!);

      if (versionMatch == null) {
        return null;
      }

      final version = versionMatch.group(1)!;

      // Return a migration that can execute the parsed code
      return _IndexedMigration(className, version, classMatch.group(0)!);
    } catch (e) {
      _logger.error('Failed to load migration $className from index: $e');
      return null;
    }
  }

  /// Get pending migrations
  Future<List<Migration>> _getPendingMigrations() async {
    final allMigrations = await _getAllMigrations();
    final completedVersions = await _getCompletedVersions();

    return allMigrations
        .where((migration) => !completedVersions.contains(migration.version))
        .toList();
  }

  /// Get completed migrations in reverse order (for rollback)
  Future<List<Migration>> _getCompletedMigrations() async {
    final allMigrations = await _getAllMigrations();
    final completedVersions = await _getCompletedVersions();

    final completed = allMigrations
        .where((migration) => completedVersions.contains(migration.version))
        .toList();

    // Sort in reverse order (latest first)
    completed.sort((a, b) => b.version.compareTo(a.version));

    return completed;
  }

  /// Get list of completed migration versions from database
  Future<Set<String>> _getCompletedVersions() async {
    final results = await db
        .query('SELECT version FROM schema_migrations ORDER BY version');

    return results.map((row) => row['version'] as String).toSet();
  }

  /// Run a specific migration by version
  Future<void> runMigration(String version) async {
    final allMigrations = await _getAllMigrations();
    final migration =
        allMigrations.where((m) => m.version == version).firstOrNull;

    if (migration == null) {
      throw ArgumentError('Migration not found: $version');
    }

    final completedVersions = await _getCompletedVersions();
    if (completedVersions.contains(version)) {
      _logger.warning('Migration $version already completed');
      return;
    }

    await migration.migrate();
    _logger.success('Migration $version completed');
  }

  /// Rollback a specific migration by version
  Future<void> rollbackMigration(String version) async {
    final allMigrations = await _getAllMigrations();
    final migration =
        allMigrations.where((m) => m.version == version).firstOrNull;

    if (migration == null) {
      throw ArgumentError('Migration not found: $version');
    }

    final completedVersions = await _getCompletedVersions();
    if (!completedVersions.contains(version)) {
      _logger.warning('Migration $version not completed, cannot rollback');
      return;
    }

    await migration.rollback();
    _logger.success('Migration $version rolled back');
  }
}

/// Migration status information
class MigrationStatus {
  final List<Migration> completed;
  final List<Migration> pending;
  final int total;

  MigrationStatus({
    required this.completed,
    required this.pending,
    required this.total,
  });

  bool get hasCompletedMigrations => completed.isNotEmpty;
  bool get hasPendingMigrations => pending.isNotEmpty;
  int get completedCount => completed.length;
  int get pendingCount => pending.length;

  @override
  String toString() {
    return 'MigrationStatus(completed: $completedCount, pending: $pendingCount, total: $total)';
  }
}

/// Migration loaded from index file
class _IndexedMigration extends Migration {
  final String _className;
  final String _version;
  final String _classDefinition;

  _IndexedMigration(this._className, this._version, this._classDefinition);

  @override
  String get version => _version;

  @override
  Future<void> up() async {
    // Parse and execute the up() method from class definition
    final upMatch = RegExp(
      r'Future<void>\s+up\(\)\s+async\s*\{(.*?)\}',
      multiLine: true,
      dotAll: true,
    ).firstMatch(_classDefinition);

    if (upMatch == null) {
      throw Exception('No up() method found in migration $_className');
    }

    final upBody = upMatch.group(1)!.trim();

    // This is a simplified approach - parse and execute common migration commands
    await _executeMigrationCode(upBody);
  }

  @override
  Future<void> down() async {
    // Parse and execute the down() method from class definition
    final downMatch = RegExp(
      r'Future<void>\s+down\(\)\s+async\s*\{(.*?)\}',
      multiLine: true,
      dotAll: true,
    ).firstMatch(_classDefinition);

    if (downMatch == null) {
      throw Exception('No down() method found in migration $_className');
    }

    final downBody = downMatch.group(1)!.trim();

    // This is a simplified approach - parse and execute common migration commands
    await _executeMigrationCode(downBody);
  }

  /// Execute parsed migration code
  Future<void> _executeMigrationCode(String code) async {
    final logger = DLogger.scoped('MIGRATION_RUNNER');

    // Simple parser for common migration commands
    final lines = code
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty);

    for (final line in lines) {
      if (line.startsWith('await createTable(')) {
        logger.info('Executing: $line');
        // TODO: Parse and execute createTable command
        logger.warning('createTable execution not yet implemented');
      } else if (line.startsWith('await dropTable(')) {
        logger.info('Executing: $line');
        // TODO: Parse and execute dropTable command
        logger.warning('dropTable execution not yet implemented');
      } else if (line.startsWith('await execute(')) {
        logger.info('Executing: $line');
        // TODO: Parse and execute SQL command
        logger.warning('execute command execution not yet implemented');
      } else if (line.startsWith('await addIndex(')) {
        logger.info('Executing: $line');
        // TODO: Parse and execute addIndex command
        logger.warning('addIndex execution not yet implemented');
      } else if (line.startsWith('//')) {
        // Skip comments
        continue;
      } else if (line.isNotEmpty) {
        logger.warning('Unknown migration command: $line');
      }
    }
  }
}

/// Simple migration registry for manual registration
class MigrationRegistry {
  static final Map<String, Migration Function()> _migrations = {};

  /// Register a migration class
  static void register(String version, Migration Function() factory) {
    _migrations[version] = factory;
  }

  /// Get all registered migrations
  static List<Migration> getAllMigrations() {
    final migrations = <Migration>[];
    final sortedVersions = _migrations.keys.toList()..sort();

    for (final version in sortedVersions) {
      final factory = _migrations[version]!;
      migrations.add(factory());
    }

    return migrations;
  }

  /// Clear all registered migrations
  static void clear() {
    _migrations.clear();
  }
}
