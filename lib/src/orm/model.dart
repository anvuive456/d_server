import 'dart:mirrors';

import '../core/logger.dart';
import 'database_connection.dart';

/// Base Active Record model class for D_Server framework
///
/// Provides CRUD operations, query methods, and attribute management
/// following the Active Record pattern.
///
/// ## Usage
///
/// ```dart
/// class User extends DModel {
///   static String get tableName => 'users';
///
///   String? get name => getAttribute<String>('name');
///   set name(String? value) => setAttribute('name', value);
///
///   String? get email => getAttribute<String>('email');
///   set email(String? value) => setAttribute('email', value);
///
///   DateTime? get createdAt => getAttribute<DateTime>('created_at');
///   DateTime? get updatedAt => getAttribute<DateTime>('updated_at');
/// }
///
/// // Usage examples:
/// final user = User();
/// user.name = 'John Doe';
/// user.email = 'john@example.com';
/// await user.save();
///
/// final users = await User.all<User>();
/// final user = await User.find<User>(1);
/// final activeUsers = await User.where<User>('active = @active', {'active': true});
/// ```
abstract class DModel {
  static DatabaseConnection? _connection;
  static final ScopedLogger _logger = DLogger.scoped('ORM');

  final Map<String, dynamic> _attributes = {};
  final Map<String, dynamic> _originalAttributes = {};
  bool _isNewRecord = true;
  bool _isDestroyed = false;

  /// Get the table name for this model
  /// Must be implemented by subclasses
  static String get tableName {
    throw UnimplementedError('tableName must be implemented by subclasses');
  }

  /// Primary key column name (defaults to 'id')
  static String get primaryKey => 'id';

  /// Timestamp columns that should be automatically managed
  static List<String> get timestampColumns => ['created_at', 'updated_at'];

  /// Set the database connection for all models
  static void setConnection(DatabaseConnection connection) {
    _connection = connection;
  }

  /// Get the current database connection
  static DatabaseConnection get connection {
    _connection ??= DatabaseConnection.defaultConnection;
    return _connection!;
  }

  /// Constructor for new records
  DModel([Map<String, dynamic>? attributes]) {
    if (attributes != null) {
      _setAttributes(attributes, isNewRecord: true);
    }
  }

  /// Constructor for existing records loaded from database
  DModel.fromDatabase(Map<String, dynamic> attributes) {
    _setAttributes(attributes, isNewRecord: false);
  }

  /// Validate the model before saving
  bool validate() {
    // Override in subclasses to implement validation logic
    return true;
  }

  // CRUD Operations

  /// Save the record to the database (insert or update)
  Future<bool> save() async {
    if (_isDestroyed) {
      throw StateError('Cannot save a destroyed record');
    }

    try {
      if (_isNewRecord) {
        return await _insert();
      } else {
        return await _update();
      }
    } catch (e) {
      _logger.error('Failed to save $runtimeType: ${e.toString()}');
      return false;
    }
  }

  /// Update the record with new attributes
  Future<bool> update(Map<String, dynamic> attributes) async {
    _setAttributes(attributes);
    return await save();
  }

  /// Delete the record from the database
  Future<bool> delete() async {
    if (_isNewRecord) {
      throw StateError('Cannot delete a new record that has not been saved');
    }

    if (_isDestroyed) {
      return true;
    }

    try {
      final tableName = _getTableName();
      final primaryKeyValue = _attributes[primaryKey];

      final rowsAffected = await connection.execute(
        'DELETE FROM $tableName WHERE $primaryKey = @id',
        {'id': primaryKeyValue},
      );

      if (rowsAffected > 0) {
        _isDestroyed = true;
        _logger.debug('Deleted $runtimeType with id: $primaryKeyValue');
        return true;
      }

      return false;
    } catch (e) {
      _logger.error('Failed to delete $runtimeType: ${e.toString()}');
      return false;
    }
  }

  /// Reload the record from the database
  Future<bool> reload() async {
    if (_isNewRecord) {
      throw StateError('Cannot reload a new record');
    }

    final primaryKeyValue = _attributes[primaryKey];
    final record = await _findByPrimaryKey(primaryKeyValue);

    if (record != null) {
      _setAttributes(record, isNewRecord: false);
      return true;
    }

    return false;
  }

  // Query Methods

  /// Find all records
  static Future<List<T>> all<T extends DModel>() async {
    final tableName = _getTableNameStatic<T>();
    final results = await connection.query('SELECT * FROM $tableName');
    return results.map((row) => _createFromMap<T>(row)).toList();
  }

  /// Find a record by primary key
  static Future<T?> find<T extends DModel>(dynamic id) async {
    final tableName = _getTableNameStatic<T>();
    final result = await connection.queryOne(
      'SELECT * FROM $tableName WHERE $primaryKey = @id',
      {'id': id},
    );

    return result != null ? _createFromMap<T>(result) : null;
  }

  /// Find records matching a condition
  static Future<List<T>> where<T extends DModel>(
    String condition, [
    Map<String, dynamic>? parameters,
  ]) async {
    final tableName = _getTableNameStatic<T>();
    final results = await connection.query(
      'SELECT * FROM $tableName WHERE $condition',
      parameters,
    );
    return results.map((row) => _createFromMap<T>(row)).toList();
  }

  /// Find the first record matching a condition
  static Future<T?> findBy<T extends DModel>(
    String condition, [
    Map<String, dynamic>? parameters,
  ]) async {
    final records = await where<T>(condition, parameters);
    return records.isNotEmpty ? records.first : null;
  }

  /// Count records matching a condition
  static Future<int> count<T extends DModel>([
    String? condition,
    Map<String, dynamic>? parameters,
  ]) async {
    final tableName = _getTableNameStatic<T>();
    final whereClause = condition != null ? 'WHERE $condition' : '';

    final result = await connection.queryOne(
      'SELECT COUNT(*) as count FROM $tableName $whereClause',
      parameters,
    );

    return result?['count'] ?? 0;
  }

  /// Check if any records exist matching a condition
  static Future<bool> exists<T extends DModel>([
    String? condition,
    Map<String, dynamic>? parameters,
  ]) async {
    final count = await DModel.count<T>(condition, parameters);
    return count > 0;
  }

  /// Create a new record and save it to the database
  static Future<T?> create<T extends DModel>(
    Map<String, dynamic> attributes,
  ) async {
    final record = _createFromMap<T>({});
    record._setAttributes(attributes);
    final saved = await record.save();
    return saved ? record : null;
  }

  // Attribute Management

  /// Get an attribute value with type casting
  T? getAttribute<T>(String key) {
    final value = _attributes[key];

    if (value == null) return null;

    if (T == DateTime && value is String) {
      return DateTime.tryParse(value) as T?;
    }

    return value as T?;
  }

  /// Get a non-null attribute value with type casting
  T getNotNullAttribute<T>(String key) {
    final value = getAttribute<T>(key);
    if (value == null) {
      throw StateError('Attribute $key is null');
    }
    return value;
  }

  /// Set an attribute value
  void setAttribute(String key, dynamic value) {
    _attributes[key] = value;
  }

  /// Check if an attribute exists
  bool hasAttribute(String key) {
    return _attributes.containsKey(key);
  }

  /// Load attributes from a map (used for loading from database)
  void loadAttributes(Map<String, dynamic> attributes) {
    _setAttributes(attributes, isNewRecord: false);
  }

  /// Get all attributes as a map
  Map<String, dynamic> get attributes => Map.unmodifiable(_attributes);

  /// Convert model to map
  Map<String, dynamic> toMap() {
    return Map<String, dynamic>.from(_attributes.map((key, value) {
      if (value is DateTime) {
        return MapEntry(key, value.toIso8601String());
      }
      return MapEntry(key, value);
    }));
  }

  /// Check if the record has been persisted to the database
  bool get isPersisted => !_isNewRecord;

  /// Check if the record is a new record
  bool get isNewRecord => _isNewRecord;

  /// Check if the record has been destroyed
  bool get isDestroyed => _isDestroyed;

  /// Check if the record has been changed since last save
  bool get isChanged => _hasChanges();

  /// Get the list of changed attributes
  List<String> get changedAttributes {
    final changed = <String>[];
    _attributes.forEach((key, value) {
      if (_originalAttributes[key] != value) {
        changed.add(key);
      }
    });
    return changed;
  }

  /// Get the primary key value
  dynamic get id => _attributes[primaryKey];

  // Private Methods

  Future<bool> _insert() async {
    // REMIND: Should we throw an error if validation fails?
    if (!validate()) {
      _logger.error('Validation failed for $runtimeType');
      return false;
    }
    final tableName = _getTableName();
    final attrs = Map<String, dynamic>.from(_attributes);

    // Add timestamps
    final now = DateTime.now().toUtc();
    if (timestampColumns.contains('created_at')) {
      attrs['created_at'] = now;
    }
    if (timestampColumns.contains('updated_at')) {
      attrs['updated_at'] = now;
    }

    // Remove null values and primary key if it's null
    attrs.removeWhere((key, value) => value == null);
    if (attrs[primaryKey] == null) {
      attrs.remove(primaryKey);
    }

    final columns = attrs.keys.join(', ');
    final placeholders = attrs.keys.map((key) => '@$key').join(', ');

    final sql = 'INSERT INTO $tableName ($columns) VALUES ($placeholders)';
    final id = await connection.insert<dynamic>(sql, attrs);

    if (id != null) {
      _attributes[primaryKey] = id;
      _attributes.addAll(attrs);
      _originalAttributes.clear();
      _originalAttributes.addAll(_attributes);
      _isNewRecord = false;

      _logger.debug('Created $runtimeType with id: $id');
      return true;
    }

    return false;
  }

  Future<bool> _update() async {
    // REMIND: Should we throw an error if validation fails?
    if (!validate()) {
      _logger.error('Validation failed for $runtimeType');
      return false;
    }
    if (!_hasChanges()) {
      return true; // No changes to save
    }

    final tableName = _getTableName();
    final changes = <String, dynamic>{};

    // Get only changed attributes
    _attributes.forEach((key, value) {
      if (_originalAttributes[key] != value && key != primaryKey) {
        changes[key] = value;
      }
    });

    if (changes.isEmpty) {
      return true;
    }

    // Add updated_at timestamp
    if (timestampColumns.contains('updated_at')) {
      changes['updated_at'] = DateTime.now().toUtc();
    }

    final setClause = changes.keys.map((key) => '$key = @$key').join(', ');
    final primaryKeyValue = _attributes[primaryKey];
    changes['id'] = primaryKeyValue;

    final sql = 'UPDATE $tableName SET $setClause WHERE $primaryKey = @id';
    final rowsAffected = await connection.execute(sql, changes);

    if (rowsAffected > 0) {
      _originalAttributes.clear();
      _originalAttributes.addAll(_attributes);

      _logger.debug('Updated $runtimeType with id: $primaryKeyValue');
      return true;
    }

    return false;
  }

  Future<Map<String, dynamic>?> _findByPrimaryKey(dynamic id) async {
    final tableName = _getTableName();
    return await connection.queryOne(
      'SELECT * FROM $tableName WHERE $primaryKey = @id',
      {'id': id},
    );
  }

  void _setAttributes(
    Map<String, dynamic> attributes, {
    bool isNewRecord = true,
  }) {
    _attributes.clear();
    _attributes.addAll(attributes);

    _originalAttributes.clear();
    _originalAttributes.addAll(attributes);

    _isNewRecord = isNewRecord;
  }

  bool _hasChanges() {
    return _attributes.keys.any(
      (key) => _originalAttributes[key] != _attributes[key],
    );
  }

  String _getTableName() {
    return _getTableNameStatic(runtimeType);
  }

  static String _getTableNameStatic<T>([Type? type]) {
    type ??= T;

    // print('Getting table name for type: $type');

    // Use reflection to get the tableName static getter
    final classMirror = reflectClass(type);
    // print('Class mirror declarations: ${classMirror.declarations}');
    final tableNameMirror = classMirror.declarations[Symbol('tableName')];
    // print('Table name mirror: $tableNameMirror');

    if (tableNameMirror != null &&
        tableNameMirror is MethodMirror &&
        tableNameMirror.isStatic) {
      return classMirror.getField(Symbol('tableName')).reflectee as String;
    }

    // Fallback: convert class name to snake_case table name
    final className = type.toString();
    return _camelToSnake(className);
  }

  static T _createFromMap<T extends DModel>(Map<String, dynamic> data) {
    // Create instance using default constructor then set attributes
    // This approach eliminates the need for each model class to define
    // a fromDatabase constructor, making the ORM more user-friendly
    final classMirror = reflectClass(T);

    // Create instance with default constructor
    final instanceMirror = classMirror.newInstance(Symbol(''), []);
    final instance = instanceMirror.reflectee as T;

    // Set attributes as if loaded from database (not a new record)
    instance._setAttributes(data, isNewRecord: false);

    return instance;
  }

  static String _camelToSnake(String camelCase) {
    return camelCase
        .replaceAllMapped(
          RegExp(r'([a-z])([A-Z])'),
          (match) => '${match[1]}_${match[2]}',
        )
        .toLowerCase();
  }

  @override
  String toString() {
    final className = runtimeType.toString();
    final id = _attributes[primaryKey];
    return '$className(id: $id, attributes: $_attributes)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! DModel) return false;
    if (runtimeType != other.runtimeType) return false;

    final thisId = _attributes[primaryKey];
    final otherId = other._attributes[primaryKey];

    return thisId != null && otherId != null && thisId == otherId;
  }

  @override
  int get hashCode {
    final id = _attributes[primaryKey];
    return id != null ? id.hashCode : super.hashCode;
  }
}

/// Exception thrown when model operations fail
class ModelException implements Exception {
  final String message;

  ModelException(this.message);

  @override
  String toString() => 'ModelException: $message';
}
