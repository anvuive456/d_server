import 'dart:mirrors';

import '../core/logger.dart';
import 'database_connection.dart';
import 'model.dart';
import 'relationships/relationship.dart';

/// Query builder for D_Server ORM with eager loading support
///
/// Provides a fluent interface for building database queries with relationship loading.
///
/// ## Usage
///
/// ```dart
/// // Basic queries
/// final users = await User.query().get();
/// final user = await User.query().where('id = @id', {'id': 1}).first();
///
/// // Eager loading
/// final users = await User.query().withRelation('profile').get();
/// final posts = await Post.query().withRelation('user').withRelation('comments').get();
///
/// // Nested eager loading
/// final posts = await Post.query().withRelation('comments.user').get();
///
/// // Complex queries with eager loading
/// final posts = await Post.query()
///     .withRelation('user.profile')
///     .withRelation('tags')
///     .where('status = @status', {'status': 'published'})
///     .orderBy('created_at', 'DESC')
///     .limit(10)
///     .get();
/// ```
class QueryBuilder<T extends DModel> {
  static final ScopedLogger _logger = DLogger.scoped('QUERY_BUILDER');

  final Type _modelType;
  final String _tableName;
  final List<String> _with = [];
  final List<String> _wheres = [];
  final List<String> _joins = [];
  final List<String> _orderBys = [];
  final Map<String, dynamic> _parameters = {};
  String? _selectClause;
  int? _limitValue;
  int? _offsetValue;

  /// Constructor for QueryBuilder
  QueryBuilder(this._modelType) : _tableName = _getTableNameForType(_modelType);

  /// Add relationships to eager load
  ///
  /// ```dart
  /// User.query().withRelation('profile').withRelation('posts.comments')
  /// ```
  QueryBuilder<T> withRelation(String relationship) {
    _with.add(relationship);
    return this;
  }

  /// Add WHERE condition
  ///
  /// ```dart
  /// User.query().where('age > @age', {'age': 18})
  /// ```
  QueryBuilder<T> where(String condition, [Map<String, dynamic>? parameters]) {
    _wheres.add(condition);
    if (parameters != null) {
      _parameters.addAll(parameters);
    }
    return this;
  }

  /// Add WHERE IN condition
  ///
  /// ```dart
  /// User.query().whereIn('id', [1, 2, 3])
  /// ```
  QueryBuilder<T> whereIn(String column, List<dynamic> values) {
    if (values.isEmpty) {
      _wheres.add('1 = 0'); // Always false condition
      return this;
    }

    final placeholders = <String>[];
    for (int i = 0; i < values.length; i++) {
      final key = '${column}_in_$i';
      placeholders.add('@$key');
      _parameters[key] = values[i];
    }

    _wheres.add('$column IN (${placeholders.join(', ')})');
    return this;
  }

  /// Add WHERE NOT IN condition
  ///
  /// ```dart
  /// User.query().whereNotIn('status', ['deleted', 'banned'])
  /// ```
  QueryBuilder<T> whereNotIn(String column, List<dynamic> values) {
    if (values.isEmpty) {
      return this; // No condition needed
    }

    final placeholders = <String>[];
    for (int i = 0; i < values.length; i++) {
      final key = '${column}_not_in_$i';
      placeholders.add('@$key');
      _parameters[key] = values[i];
    }

    _wheres.add('$column NOT IN (${placeholders.join(', ')})');
    return this;
  }

  /// Add WHERE NULL condition
  ///
  /// ```dart
  /// User.query().whereNull('deleted_at')
  /// ```
  QueryBuilder<T> whereNull(String column) {
    _wheres.add('$column IS NULL');
    return this;
  }

  /// Add WHERE NOT NULL condition
  ///
  /// ```dart
  /// User.query().whereNotNull('email_verified_at')
  /// ```
  QueryBuilder<T> whereNotNull(String column) {
    _wheres.add('$column IS NOT NULL');
    return this;
  }

  /// Add ORDER BY clause
  ///
  /// ```dart
  /// User.query().orderBy('created_at', 'DESC')
  /// ```
  QueryBuilder<T> orderBy(String column, [String direction = 'ASC']) {
    _orderBys.add('$column $direction');
    return this;
  }

  /// Add LIMIT clause
  ///
  /// ```dart
  /// User.query().limit(10)
  /// ```
  QueryBuilder<T> limit(int count) {
    _limitValue = count;
    return this;
  }

  /// Add OFFSET clause
  ///
  /// ```dart
  /// User.query().offset(20)
  /// ```
  QueryBuilder<T> offset(int count) {
    _offsetValue = count;
    return this;
  }

  /// Add JOIN clause
  ///
  /// ```dart
  /// User.query().join('profiles', 'users.id = profiles.user_id')
  /// ```
  QueryBuilder<T> join(String table, String condition) {
    _joins.add('JOIN $table ON $condition');
    return this;
  }

  /// Add LEFT JOIN clause
  ///
  /// ```dart
  /// User.query().leftJoin('profiles', 'users.id = profiles.user_id')
  /// ```
  QueryBuilder<T> leftJoin(String table, String condition) {
    _joins.add('LEFT JOIN $table ON $condition');
    return this;
  }

  /// Set custom SELECT clause
  ///
  /// ```dart
  /// User.query().select('id, name, email')
  /// ```
  QueryBuilder<T> select(String columns) {
    _selectClause = columns;
    return this;
  }

  /// Execute query and return all results
  ///
  /// ```dart
  /// final users = await User.query().get();
  /// ```
  Future<List<T>> get() async {
    final sql = _buildSelectSql();
    final connection = DatabaseConnection.defaultConnection;

    try {
      _logger.debug('Executing query: $sql');
      _logger.debug('Parameters: $_parameters');

      final results = await connection.query(sql, _parameters);
      final models = results.map((row) => _createModelInstance(row)).toList();

      // Load eager relationships
      if (_with.isNotEmpty) {
        await _loadEagerRelationships(models);
      }

      return models;
    } catch (e) {
      _logger.error('Query failed: $sql');
      _logger.error('Parameters: $_parameters');
      _logger.error('Error: ${e.toString()}');
      rethrow;
    }
  }

  /// Execute query and return first result
  ///
  /// ```dart
  /// final user = await User.query().first();
  /// ```
  Future<T?> first() async {
    limit(1);
    final results = await get();
    return results.isNotEmpty ? results.first : null;
  }

  /// Execute query and return first result or throw exception
  ///
  /// ```dart
  /// final user = await User.query().firstOrFail();
  /// ```
  Future<T> firstOrFail() async {
    final result = await first();
    if (result == null) {
      throw StateError('No records found');
    }
    return result;
  }

  /// Count the results
  ///
  /// ```dart
  /// final count = await User.query().count();
  /// ```
  Future<int> count() async {
    final sql = _buildCountSql();
    final connection = DatabaseConnection.defaultConnection;

    final result = await connection.queryOne(sql, _parameters);
    return result?['count'] ?? 0;
  }

  /// Check if any records exist
  ///
  /// ```dart
  /// final exists = await User.query().exists();
  /// ```
  Future<bool> exists() async {
    final count = await this.count();
    return count > 0;
  }

  /// Execute query with pagination
  ///
  /// ```dart
  /// final page = await User.query().paginate(page: 1, perPage: 10);
  /// ```
  Future<PaginationResult<T>> paginate({
    int page = 1,
    int perPage = 15,
  }) async {
    if (page < 1) page = 1;
    if (perPage < 1) perPage = 15;

    final totalCount = await count();
    final totalPages = (totalCount / perPage).ceil();

    offset((page - 1) * perPage);
    limit(perPage);

    final items = await get();

    return PaginationResult<T>(
      items: items,
      currentPage: page,
      perPage: perPage,
      totalCount: totalCount,
      totalPages: totalPages,
    );
  }

  /// Load eager relationships for a collection of models
  Future<void> _loadEagerRelationships(List<T> models) async {
    if (models.isEmpty || _with.isEmpty) return;

    for (final relationshipPath in _with) {
      await _loadRelationshipPath(models, relationshipPath);
    }
  }

  /// Load a specific relationship path (e.g., 'posts.comments.user')
  Future<void> _loadRelationshipPath(
      List<T> models, String relationshipPath) async {
    final parts = relationshipPath.split('.');
    await _loadNestedRelationship(models.cast<DModel>(), parts, 0);
  }

  /// Recursively load nested relationships
  Future<void> _loadNestedRelationship(
      List<DModel> models, List<String> pathParts, int depth) async {
    if (depth >= pathParts.length || models.isEmpty) return;

    final relationshipName = pathParts[depth];
    final isLastLevel = depth == pathParts.length - 1;

    // Group models by type to optimize queries
    final modelsByType = <Type, List<DModel>>{};
    for (final model in models) {
      final type = model.runtimeType;
      modelsByType.putIfAbsent(type, () => []).add(model);
    }

    final nextLevelModels = <DModel>[];

    for (final entry in modelsByType.entries) {
      final type = entry.key;
      final modelsOfType = entry.value;

      try {
        // Use reflection to get the relationship method
        final classMirror = reflectClass(type);
        final relationshipMethod =
            classMirror.declarations[Symbol(relationshipName)];

        if (relationshipMethod == null || relationshipMethod is! MethodMirror) {
          _logger.warning(
              'Relationship method $relationshipName not found on $type');
          continue;
        }

        // Check if method is a getter or normal method
        if (relationshipMethod.isGetter) {
          _logger.debug('$relationshipName is a getter method');
        } else if (relationshipMethod.parameters.isNotEmpty) {
          _logger.warning(
              'Relationship method $relationshipName requires parameters, skipping');
          continue;
        }

        // Load relationship for each model - batch loading would be better here
        final allRelatedModels = <DModel, dynamic>{};

        for (final model in modelsOfType) {
          try {
            final instanceMirror = reflect(model);
            _logger.debug(
                'Invoking relationship method: $relationshipName on ${model.runtimeType}');

            // Get the relationship - handle both getter and method calls
            dynamic relationship;
            if (relationshipMethod.isGetter) {
              relationship =
                  instanceMirror.getField(Symbol(relationshipName)).reflectee;
            } else {
              relationship =
                  instanceMirror.invoke(Symbol(relationshipName), []).reflectee;
            }

            _logger.debug('Relationship type: ${relationship.runtimeType}');

            // Check if it's a valid Relationship object
            if (relationship == null) {
              _logger.warning(
                  'Relationship method $relationshipName returned null for ${model.runtimeType}');
              continue;
            }

            if (relationship is! Relationship) {
              _logger.warning(
                  'Relationship $relationshipName returned non-Relationship object: ${relationship.runtimeType}');
              continue;
            }

            // Load the related models
            final relatedModels = await relationship.get();
            allRelatedModels[model] = relatedModels;

            _logger.debug(
                'Loaded ${relatedModels.length} related models for $relationshipName');

            // Add to next level for nested loading
            if (!isLastLevel) {
              // Handle List of models
              final list = relatedModels as List;
              for (final item in list) {
                if (item is DModel) {
                  nextLevelModels.add(item);
                }
              }
            }
          } catch (modelError) {
            _logger.error(
                'Failed to load relationship $relationshipName for model ${model.runtimeType}: $modelError');
            _logger.error('Stack trace: ${StackTrace.current}');
            // Continue with next model instead of failing completely
            continue;
          }
        }

        // Cache relationships in model - no need to call loadRelationship again
        // The relationship.get() call above already loaded and cached the data
        for (final entry in allRelatedModels.entries) {
          final model = entry.key;
          final relatedModels = entry.value;
          // Store in model's relationship cache
          _logger.debug(
              'Caching relationship $relationshipName for ${model.runtimeType} ${model.getAttribute('id')} with ${relatedModels is List ? (relatedModels as List).length : 1} related models');
          model.setRelationshipCache(relationshipName, relatedModels);
          _logger.debug(
              'Relationship cached. Is loaded: ${model.isRelationshipLoaded(relationshipName)}');
        }
      } catch (e) {
        _logger.error(
            'Failed to load relationship $relationshipName for $type: $e');
        rethrow;
      }
    }

    // Continue to next level if not at the end
    if (!isLastLevel && nextLevelModels.isNotEmpty) {
      await _loadNestedRelationship(nextLevelModels, pathParts, depth + 1);
    }
  }

  /// Build SELECT SQL query
  String _buildSelectSql() {
    final selectClause = _selectClause ?? '$_tableName.*';
    final parts = <String>['SELECT $selectClause FROM $_tableName'];

    if (_joins.isNotEmpty) {
      parts.addAll(_joins);
    }

    if (_wheres.isNotEmpty) {
      parts.add('WHERE ${_wheres.join(' AND ')}');
    }

    if (_orderBys.isNotEmpty) {
      parts.add('ORDER BY ${_orderBys.join(', ')}');
    }

    if (_limitValue != null) {
      parts.add('LIMIT $_limitValue');
    }

    if (_offsetValue != null) {
      parts.add('OFFSET $_offsetValue');
    }

    return parts.join(' ');
  }

  /// Build COUNT SQL query
  String _buildCountSql() {
    final parts = <String>['SELECT COUNT(*) as count FROM $_tableName'];

    if (_joins.isNotEmpty) {
      parts.addAll(_joins);
    }

    if (_wheres.isNotEmpty) {
      parts.add('WHERE ${_wheres.join(' AND ')}');
    }

    return parts.join(' ');
  }

  /// Create model instance from database row
  T _createModelInstance(Map<String, dynamic> row) {
    final classMirror = reflectClass(_modelType);
    final instanceMirror = classMirror.newInstance(Symbol(''), []);
    final instance = instanceMirror.reflectee as T;
    instance.loadAttributes(row);
    return instance;
  }

  /// Get table name for a model type
  static String _getTableNameForType(Type type) {
    try {
      final classMirror = reflectClass(type);
      final tableNameMirror = classMirror.declarations[#tableName];

      if (tableNameMirror != null &&
          tableNameMirror is MethodMirror &&
          tableNameMirror.isStatic) {
        return classMirror.getField(#tableName).reflectee as String;
      }

      // Fallback: convert class name to snake_case
      return _camelToSnake(type.toString());
    } catch (e) {
      return _camelToSnake(type.toString());
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
}

/// Pagination result wrapper
class PaginationResult<T> {
  final List<T> items;
  final int currentPage;
  final int perPage;
  final int totalCount;
  final int totalPages;

  PaginationResult({
    required this.items,
    required this.currentPage,
    required this.perPage,
    required this.totalCount,
    required this.totalPages,
  });

  bool get hasNextPage => currentPage < totalPages;
  bool get hasPreviousPage => currentPage > 1;
  int? get nextPage => hasNextPage ? currentPage + 1 : null;
  int? get previousPage => hasPreviousPage ? currentPage - 1 : null;
  int get firstItem => items.isEmpty ? 0 : (currentPage - 1) * perPage + 1;
  int get lastItem => items.isEmpty ? 0 : firstItem + items.length - 1;

  Map<String, dynamic> toMap() {
    return {
      'items': items,
      'current_page': currentPage,
      'per_page': perPage,
      'total_count': totalCount,
      'total_pages': totalPages,
      'has_next_page': hasNextPage,
      'has_previous_page': hasPreviousPage,
      'next_page': nextPage,
      'previous_page': previousPage,
      'first_item': firstItem,
      'last_item': lastItem,
    };
  }

  @override
  String toString() {
    return 'PaginationResult(page: $currentPage/$totalPages, items: ${items.length}/$totalCount)';
  }
}
