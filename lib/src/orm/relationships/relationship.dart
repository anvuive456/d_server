import 'dart:mirrors';

import '../model.dart';
import '../database_connection.dart';
import '../../core/logger.dart';

/// Abstract base class for all relationship types in D_Server ORM
///
/// Provides common functionality for defining and managing relationships
/// between models, including lazy loading, caching, and query building.
///
/// ## Usage
///
/// This class should not be instantiated directly. Use specific relationship
/// classes like HasOne, HasMany, BelongsTo, or BelongsToMany.
///
/// ```dart
/// class User extends DModel {
///   HasMany<Post> posts() => hasMany<Post>();
/// }
/// ```
abstract class Relationship<T extends DModel> {
  static final ScopedLogger _logger = DLogger.scoped('RELATIONSHIP');

  /// The parent model that owns this relationship
  final DModel parent;

  /// The foreign key column name
  final String foreignKey;

  /// The local key column name (usually primary key)
  final String localKey;

  /// Cache for loaded relationship data
  T? singleCache;
  List<T>? collectionCache;
  bool isLoaded = false;

  /// Constructor for relationship
  Relationship(
    this.parent, {
    String? foreignKey,
    String? localKey,
  })  : foreignKey = foreignKey ?? _defaultForeignKey<T>(),
        localKey = localKey ?? DModel.primaryKey;

  /// Get the target model's table name
  String get relatedTable => getTableName<T>();

  /// Get the parent model's table name
  String get parentTable => parent.runtimeType.toString().toLowerCase() + 's';

  /// Check if the relationship has been loaded
  bool get loaded => isLoaded;

  /// Clear the relationship cache
  void clearCache() {
    singleCache = null;
    collectionCache = null;
    isLoaded = false;
  }

  /// Load a single related model
  Future<T?> first() async {
    if (isLoaded && singleCache != null) {
      return singleCache;
    }

    final results = await buildQuery().limit(1).get();
    singleCache = results.isNotEmpty ? results.first : null;
    isLoaded = true;

    return singleCache;
  }

  /// Load all related models
  Future<List<T>> get() async {
    if (isLoaded && collectionCache != null) {
      return collectionCache!;
    }

    final results = await buildQuery().get();
    collectionCache = results;
    isLoaded = true;

    return results;
  }

  /// Count related models without loading them
  Future<int> count() async {
    final query = buildQuery();
    return await query.count();
  }

  /// Check if any related models exist
  Future<bool> exists() async {
    final count = await this.count();
    return count > 0;
  }

  /// Find a related model by ID
  Future<T?> find(dynamic id) async {
    final query = buildQuery();
    return await query.where(
        '${relatedTable}.${DModel.primaryKey} = @id', {'id': id}).first();
  }

  /// Filter related models with a condition
  Future<List<T>> where(String condition,
      [Map<String, dynamic>? parameters]) async {
    final query = buildQuery();
    return await query.where(condition, parameters).get();
  }

  /// Build the base query for this relationship
  RelationshipQuery<T> buildQuery();

  /// Get the default foreign key name for a model type
  static String _defaultForeignKey<T>() {
    final className = T.toString();
    return _camelToSnake(className) + '_id';
  }

  /// Get table name for a model type using reflection
  static String getTableName<T>() {
    try {
      final classMirror = reflectClass(T);
      final tableNameMirror = classMirror.declarations[#tableName];

      if (tableNameMirror != null &&
          tableNameMirror is MethodMirror &&
          tableNameMirror.isStatic) {
        return classMirror.getField(#tableName).reflectee as String;
      }

      // Fallback: convert class name to snake_case
      return _camelToSnake(T.toString());
    } catch (e) {
      _logger.warning(
          'Could not get table name for $T, using fallback: ${e.toString()}');
      return _camelToSnake(T.toString());
    }
  }

  /// Convert camelCase to snake_case
  static String _camelToSnake(String camelCase) {
    return camelCase
        .replaceAllMapped(
          RegExp(r'([a-z])([A-Z])'),
          (match) => '${match[1]}_${match[2]}',
        )
        .toLowerCase();
  }

  /// Create an instance of the related model from database data
  static T createInstance<T extends DModel>(Map<String, dynamic> data) {
    final classMirror = reflectClass(T);
    final instanceMirror = classMirror.newInstance(Symbol(''), []);
    final instance = instanceMirror.reflectee as T;
    instance.loadAttributes(data);
    return instance;
  }
}

/// Query builder specifically for relationships
class RelationshipQuery<T extends DModel> {
  final String table;
  final List<String> wheres = [];
  final List<String> joins = [];
  final Map<String, dynamic> parameters = {};
  int? limitValue;
  int? offsetValue;
  String? orderByClause;

  RelationshipQuery(this.table);

  /// Add a WHERE condition
  RelationshipQuery<T> where(String condition,
      [Map<String, dynamic>? parameters]) {
    wheres.add(condition);
    if (parameters != null) {
      this.parameters.addAll(parameters);
    }
    return this;
  }

  /// Add a JOIN clause
  RelationshipQuery<T> join(String table, String condition) {
    joins.add('JOIN $table ON $condition');
    return this;
  }

  /// Add a LEFT JOIN clause
  RelationshipQuery<T> leftJoin(String table, String condition) {
    joins.add('LEFT JOIN $table ON $condition');
    return this;
  }

  /// Set limit
  RelationshipQuery<T> limit(int count) {
    limitValue = count;
    return this;
  }

  /// Set offset
  RelationshipQuery<T> offset(int count) {
    offsetValue = count;
    return this;
  }

  /// Set order by
  RelationshipQuery<T> orderBy(String column, [String direction = 'ASC']) {
    orderByClause = '$column $direction';
    return this;
  }

  /// Execute the query and return results
  Future<List<T>> get() async {
    final sql = _buildSelect();
    final connection = DatabaseConnection.defaultConnection;

    try {
      final results = await connection.query(sql, parameters);
      return results.map((row) => Relationship.createInstance<T>(row)).toList();
    } catch (e) {
      final logger = DLogger.scoped('RELATIONSHIP_QUERY');
      logger.error('Query failed: $sql');
      logger.error('Parameters: $parameters');
      logger.error('Error: ${e.toString()}');
      rethrow;
    }
  }

  /// Execute the query and return first result
  Future<T?> first() async {
    limit(1);
    final results = await get();
    return results.isNotEmpty ? results.first : null;
  }

  /// Count the results
  Future<int> count() async {
    final sql = _buildCount();
    final connection = DatabaseConnection.defaultConnection;

    final result = await connection.queryOne(sql, parameters);
    return result?['count'] ?? 0;
  }

  /// Build SELECT SQL
  String _buildSelect() {
    final parts = <String>['SELECT $table.* FROM $table'];

    if (joins.isNotEmpty) {
      parts.addAll(joins);
    }

    if (wheres.isNotEmpty) {
      parts.add('WHERE ${wheres.join(' AND ')}');
    }

    if (orderByClause != null) {
      parts.add('ORDER BY $orderByClause');
    }

    if (limitValue != null) {
      parts.add('LIMIT $limitValue');
    }

    if (offsetValue != null) {
      parts.add('OFFSET $offsetValue');
    }

    return parts.join(' ');
  }

  /// Build COUNT SQL
  String _buildCount() {
    final parts = <String>['SELECT COUNT(*) as count FROM $table'];

    if (joins.isNotEmpty) {
      parts.addAll(joins);
    }

    if (wheres.isNotEmpty) {
      parts.add('WHERE ${wheres.join(' AND ')}');
    }

    return parts.join(' ');
  }
}

/// Exception thrown when relationship operations fail
class RelationshipException implements Exception {
  final String message;

  RelationshipException(this.message);

  @override
  String toString() => 'RelationshipException: $message';
}
