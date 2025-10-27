import 'package:d_server/src/orm/relationships/foreign_actions.dart';

import '../orm/database_connection.dart';
import '../core/logger.dart';

/// Base class for database migrations in D_Server framework
///
/// Provides a migration system with up/down methods
/// for applying and rolling back database schema changes.
///
/// ## Usage
///
/// ```dart
/// class CreateUsers extends Migration {
///   @override
///   String get version => '20241019180000';
///
///   @override
///   Future<void> up() async {
///     await createTable('users', (table) {
///       table.serial('id').primaryKey();
///       table.string('email').unique().notNull();
///       table.string('password_digest').notNull();
///       table.timestamps();
///     });
///   }
///
///   @override
///   Future<void> down() async {
///     await dropTable('users');
///   }
/// }
/// ```
abstract class Migration {
  static final ScopedLogger _logger = DLogger.scoped('MIGRATION');

  /// The version/timestamp of this migration (format: YYYYMMDDHHMMSS)
  String get version;

  /// The name of this migration (derived from class name)
  String get name => runtimeType.toString();

  /// Apply the migration (create tables, add columns, etc.)
  Future<void> up();

  /// Rollback the migration (drop tables, remove columns, etc.)
  Future<void> down();

  /// Get the database connection
  DatabaseConnection get db => DatabaseConnection.defaultConnection;

  /// Execute the migration up
  Future<void> migrate() async {
    _logger.info('Migrating $name ($version)');
    try {
      await up();
      await _recordMigration();
      _logger.success('Migrated $name');
    } catch (e) {
      _logger.error('Migration failed for $name: $e');
      rethrow;
    }
  }

  /// Execute the migration down
  Future<void> rollback() async {
    _logger.info('Rolling back $name ($version)');
    try {
      await down();
      await _removeMigrationRecord();
      _logger.success('Rolled back $name');
    } catch (e) {
      _logger.error('Rollback failed for $name: $e');
      rethrow;
    }
  }

  /// Create a new table
  Future<void> createTable(
      String tableName, Function(TableBuilder) builder) async {
    final tableBuilder = TableBuilder(tableName);
    builder(tableBuilder);
    await db.execute(tableBuilder.build());
  }

  /// Drop a table
  Future<void> dropTable(String tableName) async {
    await db.execute('DROP TABLE IF EXISTS $tableName CASCADE');
  }

  /// Add a column to an existing table
  Future<void> addColumn(
    String tableName,
    String columnName,
    String type, {
    bool nullable = true,
    String? defaultValue,
    bool unique = false,
  }) async {
    final constraints = <String>[];

    if (!nullable) constraints.add('NOT NULL');
    if (unique) constraints.add('UNIQUE');
    if (defaultValue != null) constraints.add('DEFAULT $defaultValue');

    final constraintStr =
        constraints.isNotEmpty ? ' ${constraints.join(' ')}' : '';

    await db.execute(
        'ALTER TABLE $tableName ADD COLUMN $columnName $type$constraintStr');
  }

  /// Remove a column from a table
  Future<void> removeColumn(String tableName, String columnName) async {
    await db.execute('ALTER TABLE $tableName DROP COLUMN $columnName');
  }

  /// Add an index
  Future<void> addIndex(
    String tableName,
    List<String> columns, {
    String? name,
    bool unique = false,
  }) async {
    final indexName = name ?? '${tableName}_${columns.join('_')}_idx';
    final uniqueStr = unique ? 'UNIQUE ' : '';
    final columnStr = columns.join(', ');

    await db.execute(
        'CREATE ${uniqueStr}INDEX $indexName ON $tableName ($columnStr)');
  }

  /// Remove an index
  Future<void> removeIndex(String indexName) async {
    await db.execute('DROP INDEX IF EXISTS $indexName');
  }

  /// Add a foreign key constraint to existing table
  Future<void> addForeignKey(
    String tableName,
    String columnName,
    String referencedTable, {
    String referencedColumn = 'id',
    String? constraintName,

    /// Optional actions on delete and update
    /// e.g., [ForeignKeyAction.cascade], [ForeignKeyAction.setNull], [ForeignKeyAction.restrict]
    ForeignKeyAction? onDelete,

    /// Optional action on update
    /// e.g., [ForeignKeyAction.cascade], [ForeignKeyAction.setNull], [ForeignKeyAction.restrict]
    ForeignKeyAction? onUpdate,
  }) async {
    final constraintNameStr =
        constraintName ?? 'fk_${tableName}_${columnName}_${referencedTable}';

    String sql = 'ALTER TABLE $tableName ADD CONSTRAINT $constraintNameStr '
        'FOREIGN KEY ($columnName) REFERENCES $referencedTable($referencedColumn)';

    if (onDelete != null && onDelete != ForeignKeyAction.noAction) {
      sql += ' ON DELETE ${onDelete.sql}';
    }

    if (onUpdate != null && onUpdate != ForeignKeyAction.noAction) {
      sql += ' ON UPDATE ${onUpdate.sql}';
    }

    await db.execute(sql);
  }

  /// Drop a foreign key constraint
  Future<void> dropForeignKey(
    String tableName,
    String constraintName,
  ) async {
    await db.execute('ALTER TABLE $tableName DROP CONSTRAINT $constraintName');
  }

  /// Create a pivot table for many-to-many relationships
  Future<void> createPivotTable(
    String table1,
    String table2, {
    String? pivotTableName,
    String? foreignKey1,
    String? foreignKey2,
    bool withTimestamps = false,
    Map<String, String>? additionalColumns,
  }) async {
    final pivotName = pivotTableName ?? _defaultPivotTableName(table1, table2);
    final fk1 = foreignKey1 ?? '${_singularize(table1)}_id';
    final fk2 = foreignKey2 ?? '${_singularize(table2)}_id';

    await createTable(pivotName, (table) {
      table.integer(fk1).notNull();
      table.integer(fk2).notNull();

      // Add foreign key constraints
      table._constraints
          .add('FOREIGN KEY ($fk1) REFERENCES $table1(id) ON DELETE CASCADE');
      table._constraints
          .add('FOREIGN KEY ($fk2) REFERENCES $table2(id) ON DELETE CASCADE');

      // Add composite primary key
      table._constraints.add('PRIMARY KEY ($fk1, $fk2)');

      // Add additional columns if provided
      if (additionalColumns != null) {
        additionalColumns.forEach((columnName, columnType) {
          table._addColumn('$columnName $columnType');
        });
      }

      if (withTimestamps) {
        table.timestamps();
      }
    });
  }

  /// Get default pivot table name
  String _defaultPivotTableName(String table1, String table2) {
    final tables = [table1, table2]..sort();
    return tables.join('_');
  }

  /// Helper method to singularize table names
  String _singularize(String tableName) {
    if (tableName.endsWith('ies')) {
      return '${tableName.substring(0, tableName.length - 3)}y';
    } else if (tableName.endsWith('s')) {
      return tableName.substring(0, tableName.length - 1);
    }
    return tableName;
  }

  /// Execute raw SQL
  Future<void> execute(String sql) async {
    await db.execute(sql);
  }

  /// Record this migration as completed
  Future<void> _recordMigration() async {
    await db.execute(
      'INSERT INTO schema_migrations (version, name, migrated_at) VALUES (@version, @name, @timestamp)',
      {
        'version': version,
        'name': name,
        'timestamp': DateTime.now().toIso8601String(),
      },
    );
  }

  /// Remove migration record
  Future<void> _removeMigrationRecord() async {
    await db.execute(
      'DELETE FROM schema_migrations WHERE version = @version',
      {'version': version},
    );
  }
}

/// Table builder for creating database tables
class TableBuilder {
  final String tableName;
  final List<String> _columns = [];
  final List<String> _constraints = [];

  TableBuilder(this.tableName);

  /// Add a serial (auto-increment) column
  ColumnBuilder serial(String name) {
    return ColumnBuilder(this, name, 'SERIAL');
  }

  /// Add an integer column
  ColumnBuilder integer(String name) {
    return ColumnBuilder(this, name, 'INTEGER');
  }

  /// Add a bigint column
  ColumnBuilder bigint(String name) {
    return ColumnBuilder(this, name, 'BIGINT');
  }

  /// Add a string/varchar column
  ColumnBuilder string(String name, {int length = 255}) {
    return ColumnBuilder(this, name, 'VARCHAR($length)');
  }

  /// Add a text column
  ColumnBuilder text(String name) {
    return ColumnBuilder(this, name, 'TEXT');
  }

  /// Add a boolean column
  ColumnBuilder boolean(String name) {
    return ColumnBuilder(this, name, 'BOOLEAN');
  }

  /// Add a timestamp column
  ColumnBuilder timestamp(String name) {
    return ColumnBuilder(this, name, 'TIMESTAMP');
  }

  /// Add a date column
  ColumnBuilder date(String name) {
    return ColumnBuilder(this, name, 'DATE');
  }

  /// Add a decimal column
  ColumnBuilder decimal(String name, {int precision = 10, int scale = 2}) {
    return ColumnBuilder(this, name, 'DECIMAL($precision,$scale)');
  }

  /// Add created_at and updated_at timestamp columns
  void timestamps() {
    timestamp('created_at').defaultValue('CURRENT_TIMESTAMP').finalize();
    timestamp('updated_at').defaultValue('CURRENT_TIMESTAMP').finalize();
  }

  /// Add a foreign key reference
  ColumnBuilder references(String table, {String column = 'id'}) {
    final columnName = '${table.replaceAll(RegExp(r's$'), '')}_id';
    final builder = integer(columnName);
    _constraints.add('FOREIGN KEY ($columnName) REFERENCES $table($column)');
    return builder;
  }

  /// Add a foreign key constraint with cascade options
  ColumnBuilder foreignKey(
    String table, {
    String? column = 'id',
    String? columnName,
    String? onDelete,
    String? onUpdate,
    bool addIndex = true,
  }) {
    final keyColumnName = columnName ?? '${_singularize(table)}_id';
    final builder = integer(keyColumnName);

    // Build constraint with cascade options
    String constraintSql =
        'FOREIGN KEY ($keyColumnName) REFERENCES $table(${column ?? 'id'})';

    if (onDelete != null) {
      constraintSql += ' ON DELETE $onDelete';
    }

    if (onUpdate != null) {
      constraintSql += ' ON UPDATE $onUpdate';
    }

    _constraints.add(constraintSql);

    // Add index for foreign key if requested
    if (addIndex) {
      _constraints
          .add('INDEX idx_${tableName}_$keyColumnName ($keyColumnName)');
    }

    return builder;
  }

  /// Add a composite foreign key
  void compositeForeignKey(
    List<String> columns,
    String referencedTable,
    List<String> referencedColumns, {
    String? onDelete,
    String? onUpdate,
  }) {
    if (columns.length != referencedColumns.length) {
      throw ArgumentError(
          'Columns and referenced columns must have the same length');
    }

    final columnList = columns.join(', ');
    final referencedColumnList = referencedColumns.join(', ');

    String constraintSql =
        'FOREIGN KEY ($columnList) REFERENCES $referencedTable($referencedColumnList)';

    if (onDelete != null) {
      constraintSql += ' ON DELETE $onDelete';
    }

    if (onUpdate != null) {
      constraintSql += ' ON UPDATE $onUpdate';
    }

    _constraints.add(constraintSql);
  }

  /// Helper method to singularize table names
  String _singularize(String tableName) {
    if (tableName.endsWith('ies')) {
      return tableName.substring(0, tableName.length - 3) + 'y';
    } else if (tableName.endsWith('s')) {
      return tableName.substring(0, tableName.length - 1);
    }
    return tableName;
  }

  /// Build the CREATE TABLE SQL
  String build() {
    final columnsStr = _columns.join(', ');
    final constraintsStr =
        _constraints.isNotEmpty ? ', ${_constraints.join(', ')}' : '';

    return 'CREATE TABLE $tableName ($columnsStr$constraintsStr)';
  }

  void _addColumn(String definition) {
    _columns.add(definition);
  }

  void _addConstraint(String constraint) {
    _constraints.add(constraint);
  }
}

/// Column builder for defining table columns
class ColumnBuilder {
  final TableBuilder _table;
  final String _name;
  final String _type;
  final List<String> _modifiers = [];

  ColumnBuilder(this._table, this._name, this._type);

  /// Make column the primary key
  ColumnBuilder primaryKey() {
    _modifiers.add('PRIMARY KEY');
    return this;
  }

  /// Make column not null
  ColumnBuilder notNull() {
    _modifiers.add('NOT NULL');
    return this;
  }

  /// Make column unique
  ColumnBuilder unique() {
    _modifiers.add('UNIQUE');
    return this;
  }

  /// Set default value
  ColumnBuilder defaultValue(String value) {
    _modifiers.add('DEFAULT $value');
    return this;
  }

  /// Finalize the column definition
  void finalize() {
    final modifiersStr =
        _modifiers.isNotEmpty ? ' ${_modifiers.join(' ')}' : '';
    _table._addColumn('$_name $_type$modifiersStr');
  }
}

/// Extension to automatically finalize column builders
extension on ColumnBuilder {
  void _autoFinalize() {
    finalize();
  }
}

/// Override operators to auto-finalize columns
extension TableBuilderExtension on TableBuilder {
  ColumnBuilder operator [](String name) {
    return string(name).._autoFinalize();
  }
}
