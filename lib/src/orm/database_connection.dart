import 'dart:async';
import 'package:postgres/postgres.dart';
import '../core/logger.dart';

/// Database connection management for D_Server framework
///
/// Provides PostgreSQL connection pooling, transaction management,
/// and query execution with logging and error handling.
///
/// ## Usage
///
/// ```dart
/// // Create connection from config
/// final db = DatabaseConnection.fromConfig({
///   'host': 'localhost',
///   'port': 5432,
///   'database': 'myapp',
///   'username': 'user',
///   'password': 'password',
/// });
///
/// // Execute queries
/// final result = await db.query('SELECT * FROM users WHERE id = @id', {'id': 1});
/// await db.execute('INSERT INTO users (name, email) VALUES (@name, @email)', {
///   'name': 'John',
///   'email': 'john@example.com'
/// });
///
/// // Use transactions
/// await db.transaction((tx) async {
///   await tx.execute('INSERT INTO users (name) VALUES (@name)', {'name': 'Alice'});
///   await tx.execute('INSERT INTO posts (title, user_id) VALUES (@title, @user_id)', {
///     'title': 'Hello World',
///     'user_id': 1
///   });
/// });
/// ```
class DatabaseConnection {
  static final Map<String, DatabaseConnection> _connections = {};
  static DatabaseConnection? _defaultConnection;
  static SslMode _ssl = SslMode.disable;

  final Endpoint _endpoint;
  Connection? _connection;
  final ScopedLogger _logger = DLogger.scoped('DATABASE');

  DatabaseConnection._(this._endpoint);

  /// Create a database connection from configuration map
  static Future<DatabaseConnection> fromConfig(
    Map<String, dynamic> config, {
    String? name,
  }) async {
    _ssl = (config['ssl'] ?? false) ? SslMode.require : SslMode.disable;
    final endpoint = Endpoint(
      host: config['host'] ?? 'localhost',
      port: config['port'] ?? 5432,
      database: config['database'] ?? config['name'],
      username: config['username'] ?? config['user'],
      password: config['password'],
    );

    final connection = DatabaseConnection._(endpoint);

    // Store connection in registry
    if (name != null) {
      _connections[name] = connection;
    } else {
      _defaultConnection = connection;
    }

    // Test the connection
    await connection._testConnection();

    return connection;
  }

  /// Get the default database connection
  static DatabaseConnection get defaultConnection {
    if (_defaultConnection == null) {
      throw DatabaseException('No default database connection configured');
    }
    return _defaultConnection!;
  }

  /// Get a named database connection
  static DatabaseConnection connection(String name) {
    if (!_connections.containsKey(name)) {
      throw DatabaseException('Database connection not found: $name');
    }
    return _connections[name]!;
  }

  /// Execute a SELECT query and return results
  Future<List<Map<String, dynamic>>> query(
    String sql, [
    Map<String, dynamic>? parameters,
  ]) async {
    final stopwatch = Stopwatch()..start();

    try {
      _connection ??= await Connection.open(
        _endpoint,
        settings: ConnectionSettings(
          sslMode: _ssl,
        ),
      );

      final result = parameters == null || parameters.isEmpty
          ? await _connection!.execute(sql)
          : await _connection!.execute(Sql.named(sql), parameters: parameters);

      stopwatch.stop();
      _logger.debug('QUERY: $sql - ${stopwatch.elapsedMilliseconds}ms');

      return result.map((row) => row.toColumnMap()).toList();
    } catch (e) {
      stopwatch.stop();
      _logger.error('QUERY ERROR: $sql - ${e.toString()}');
      throw DatabaseException('Query failed: ${e.toString()}');
    }
  }

  /// Execute a single SELECT query and return the first result
  Future<Map<String, dynamic>?> queryOne(
    String sql, [
    Map<String, dynamic>? parameters,
  ]) async {
    final results = await query(sql, parameters);
    return results.isNotEmpty ? results.first : null;
  }

  /// Execute an INSERT, UPDATE, or DELETE statement
  Future<int> execute(String sql, [Map<String, dynamic>? parameters]) async {
    final stopwatch = Stopwatch()..start();

    try {
      _connection ??= await Connection.open(
        _endpoint,
        settings: ConnectionSettings(
          sslMode: _ssl,
        ),
      );

      final result = parameters == null || parameters.isEmpty
          ? await _connection!.execute(sql)
          : await _connection!.execute(Sql.named(sql), parameters: parameters);

      stopwatch.stop();
      _logger.debug('EXECUTE: $sql - ${stopwatch.elapsedMilliseconds}ms');

      return result.affectedRows;
    } catch (e) {
      stopwatch.stop();
      _logger.error('EXECUTE ERROR: $sql - ${e.toString()}');
      throw DatabaseException('Execute failed: ${e.toString()}');
    }
  }

  /// Execute an INSERT statement and return the generated ID
  Future<T?> insert<T>(String sql, [Map<String, dynamic>? parameters]) async {
    final stopwatch = Stopwatch()..start();

    try {
      _connection ??= await Connection.open(
        _endpoint,
        settings: ConnectionSettings(
          sslMode: _ssl,
        ),
      );

      final result = parameters == null || parameters.isEmpty
          ? await _connection!.execute('$sql RETURNING id')
          : await _connection!
              .execute(Sql.named('$sql RETURNING id'), parameters: parameters);

      stopwatch.stop();
      _logger.debug('INSERT: $sql - ${stopwatch.elapsedMilliseconds}ms');

      if (result.isNotEmpty) {
        final row = result.first.toColumnMap();
        return row['id'] as T?;
      }
      return null;
    } catch (e) {
      stopwatch.stop();
      _logger.error('INSERT ERROR: $sql - ${e.toString()}');
      throw DatabaseException('Insert failed: ${e.toString()}');
    }
  }

  /// Execute multiple statements in a transaction
  Future<T> transaction<T>(
    Future<T> Function(DatabaseTransaction) callback,
  ) async {
    final stopwatch = Stopwatch()..start();
    _logger.debug('BEGIN TRANSACTION');

    try {
      _connection ??= await Connection.open(
        _endpoint,
        settings: ConnectionSettings(
          sslMode: _ssl,
        ),
      );

      final result = await _connection!.runTx((txSession) async {
        final transaction = DatabaseTransaction._(txSession, _logger);
        return await callback(transaction);
      });

      stopwatch.stop();
      _logger.debug('COMMIT TRANSACTION - ${stopwatch.elapsedMilliseconds}ms');
      return result;
    } catch (e) {
      stopwatch.stop();
      _logger.error('ROLLBACK TRANSACTION - ${e.toString()}');
      rethrow;
    }
  }

  /// Check if a table exists
  Future<bool> tableExists(String tableName) async {
    final result = await queryOne(
      '''
      SELECT EXISTS (
        SELECT FROM information_schema.tables
        WHERE table_schema = 'public'
        AND table_name = @table_name
      )
      ''',
      {'table_name': tableName},
    );

    return result?['exists'] == true;
  }

  /// Get table column information
  Future<List<Map<String, dynamic>>> getTableColumns(String tableName) async {
    return await query(
      '''
      SELECT column_name, data_type, is_nullable, column_default
      FROM information_schema.columns
      WHERE table_schema = 'public' AND table_name = @table_name
      ORDER BY ordinal_position
      ''',
      {'table_name': tableName},
    );
  }

  /// Close the database connection
  Future<void> close() async {
    if (_connection != null) {
      await _connection!.close();
      _connection = null;
      _logger.info('Database connection closed');
    }
  }

  /// Test the database connection
  Future<void> _testConnection() async {
    try {
      await query('SELECT 1 as test', null);
      _logger.success(
        'Connected to PostgreSQL at ${_endpoint.host}:${_endpoint.port}/${_endpoint.database}',
      );
    } catch (e) {
      _logger.error('Failed to connect to database: ${e.toString()}');
      throw DatabaseException(
        'Database connection test failed: ${e.toString()}',
      );
    }
  }
}

/// Database transaction wrapper
class DatabaseTransaction {
  final dynamic _session;
  final ScopedLogger _logger;

  DatabaseTransaction._(this._session, this._logger);

  /// Execute a SELECT query within the transaction
  Future<List<Map<String, dynamic>>> query(
    String sql, [
    Map<String, dynamic>? parameters,
  ]) async {
    final stopwatch = Stopwatch()..start();

    try {
      final result = parameters == null || parameters.isEmpty
          ? await _session.execute(sql)
          : await _session.execute(Sql.named(sql), parameters: parameters);

      stopwatch.stop();
      _logger.debug('TX QUERY: $sql - ${stopwatch.elapsedMilliseconds}ms');

      return result.map((row) => row.toColumnMap()).toList();
    } catch (e) {
      stopwatch.stop();
      _logger.error('TX QUERY ERROR: $sql - ${e.toString()}');
      throw DatabaseException('Transaction query failed: ${e.toString()}');
    }
  }

  /// Execute a single SELECT query within the transaction
  Future<Map<String, dynamic>?> queryOne(
    String sql, [
    Map<String, dynamic>? parameters,
  ]) async {
    final results = await query(sql, parameters);
    return results.isNotEmpty ? results.first : null;
  }

  /// Execute an INSERT, UPDATE, or DELETE within the transaction
  Future<int> execute(String sql, [Map<String, dynamic>? parameters]) async {
    final stopwatch = Stopwatch()..start();

    try {
      final result = parameters == null || parameters.isEmpty
          ? await _session.execute(sql)
          : await _session.execute(Sql.named(sql), parameters: parameters);

      stopwatch.stop();
      _logger.debug('TX EXECUTE: $sql - ${stopwatch.elapsedMilliseconds}ms');

      return result.affectedRows;
    } catch (e) {
      stopwatch.stop();
      _logger.error('TX EXECUTE ERROR: $sql - ${e.toString()}');
      throw DatabaseException('Transaction execute failed: ${e.toString()}');
    }
  }

  /// Execute an INSERT and return the generated ID within the transaction
  Future<T?> insert<T>(String sql, [Map<String, dynamic>? parameters]) async {
    final stopwatch = Stopwatch()..start();

    try {
      final result = parameters == null || parameters.isEmpty
          ? await _session.execute('$sql RETURNING id')
          : await _session.execute(Sql.named('$sql RETURNING id'),
              parameters: parameters);

      stopwatch.stop();
      _logger.debug('TX INSERT: $sql - ${stopwatch.elapsedMilliseconds}ms');

      if (result.isNotEmpty) {
        final row = result.first.toColumnMap();
        return row['id'] as T?;
      }
      return null;
    } catch (e) {
      stopwatch.stop();
      _logger.error('TX INSERT ERROR: $sql - ${e.toString()}');
      throw DatabaseException('Transaction insert failed: ${e.toString()}');
    }
  }
}

/// Exception thrown when database operations fail
class DatabaseException implements Exception {
  final String message;

  DatabaseException(this.message);

  @override
  String toString() => 'DatabaseException: $message';
}
