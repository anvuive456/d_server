import '../model.dart';
import 'relationship.dart';

/// Represents a many-to-many relationship where models are connected through a pivot table
///
/// This relationship type is used when a model can be associated with multiple
/// instances of another model, and vice versa, through an intermediate pivot table.
///
/// ## Example
///
/// ```dart
/// class User extends DModel {
///   static String get tableName => 'users';
///
///   // User belongs to many Roles
///   BelongsToMany<Role> roles() => belongsToMany<Role>();
///
///   // Custom pivot table and keys
///   BelongsToMany<Role> customRoles() => belongsToMany<Role>(
///     pivotTable: 'user_role_assignments',
///     foreignPivotKey: 'user_id',
///     relatedPivotKey: 'role_id',
///   );
/// }
///
/// class Role extends DModel {
///   static String get tableName => 'roles';
///
///   String? get name => getAttribute<String>('name');
/// }
///
/// // Usage
/// final user = await User.find<User>(1);
/// final roles = await user.roles().get();
/// await user.roles().attach(1, {'assigned_at': DateTime.now()});
/// ```
class BelongsToMany<T extends DModel> extends Relationship<T> {
  /// The pivot table name
  final String pivotTable;

  /// The foreign key column in the pivot table for the parent model
  final String foreignPivotKey;

  /// The foreign key column in the pivot table for the related model
  final String relatedPivotKey;

  /// Whether to include timestamps in the pivot table
  final bool withTimestamps;

  /// Additional pivot columns to select
  final List<String> pivotColumns;

  /// Creates a BelongsToMany relationship
  ///
  /// [parent] The model instance that owns this relationship
  /// [pivotTable] The name of the pivot table (auto-generated if null)
  /// [foreignPivotKey] The foreign key for parent model in pivot table
  /// [relatedPivotKey] The foreign key for related model in pivot table
  /// [localKey] The local key column in the parent table
  /// [relatedKey] The key column in the related table
  /// [withTimestamps] Whether to manage created_at/updated_at in pivot table
  /// [pivotColumns] Additional pivot columns to select
  BelongsToMany(
    super.parent, {
    String? pivotTable,
    String? foreignPivotKey,
    String? relatedPivotKey,
    super.localKey,
    String? relatedKey,
    this.withTimestamps = false,
    this.pivotColumns = const [],
  })  : pivotTable = pivotTable ?? _defaultPivotTable<T>(parent),
        foreignPivotKey = foreignPivotKey ?? _defaultForeignPivotKey(parent),
        relatedPivotKey = relatedPivotKey ?? _defaultRelatedPivotKey<T>(),
        super(foreignKey: relatedKey ?? DModel.primaryKey);

  /// Attach a model to the relationship
  ///
  /// ```dart
  /// final user = await User.find<User>(1);
  /// await user.roles().attach(1);
  /// await user.roles().attach([1, 2, 3]);
  /// await user.roles().attach(1, {'priority': 'high'});
  /// ```
  Future<void> attach(
    dynamic ids, [
    Map<String, dynamic>? pivotData,
  ]) async {
    if (!parent.isPersisted) {
      throw RelationshipException(
          'Cannot attach to relationship on unsaved parent model');
    }

    final idList = _normalizeIds(ids);
    final parentKeyValue = parent.getAttribute(localKey);

    for (final id in idList) {
      final attributes = <String, dynamic>{
        foreignPivotKey: parentKeyValue,
        relatedPivotKey: id,
      };

      // Add pivot data if provided
      if (pivotData != null) {
        attributes.addAll(pivotData);
      }

      // Add timestamps if enabled
      if (withTimestamps) {
        final now = DateTime.now().toUtc();
        attributes['created_at'] = now;
        attributes['updated_at'] = now;
      }

      // Check if relationship already exists
      final exists = await _pivotExists(parentKeyValue, id);
      if (!exists) {
        await _insertPivotRecord(attributes);
      }
    }

    // Clear cache
    clearCache();
  }

  /// Detach a model from the relationship
  ///
  /// ```dart
  /// final user = await User.find<User>(1);
  /// await user.roles().detach(1);
  /// await user.roles().detach([1, 2, 3]);
  /// await user.roles().detach(); // Detach all
  /// ```
  Future<int> detach([dynamic ids]) async {
    if (!parent.isPersisted) {
      throw RelationshipException(
          'Cannot detach from relationship on unsaved parent model');
    }

    final parentKeyValue = parent.getAttribute(localKey);
    final connection = DModel.connection;

    String sql;
    Map<String, dynamic> parameters;

    if (ids == null) {
      // Detach all
      sql = 'DELETE FROM $pivotTable WHERE $foreignPivotKey = @parent_key';
      parameters = {'parent_key': parentKeyValue};
    } else {
      // Detach specific IDs
      final idList = _normalizeIds(ids);
      final placeholders =
          idList.asMap().entries.map((entry) => '@id_${entry.key}').join(', ');

      sql =
          'DELETE FROM $pivotTable WHERE $foreignPivotKey = @parent_key AND $relatedPivotKey IN ($placeholders)';
      parameters = {'parent_key': parentKeyValue};

      for (var i = 0; i < idList.length; i++) {
        parameters['id_$i'] = idList[i];
      }
    }

    final rowsAffected = await connection.execute(sql, parameters);

    // Clear cache
    clearCache();

    return rowsAffected;
  }

  /// Sync the relationship with the given IDs
  ///
  /// ```dart
  /// final user = await User.find<User>(1);
  /// await user.roles().sync([1, 2, 3]);
  /// await user.roles().sync({'1': {'priority': 'high'}, '2': {'priority': 'low'}});
  /// ```
  Future<Map<String, List<dynamic>>> sync(dynamic ids) async {
    final Map<String, List<dynamic>> changes = {
      'attached': [],
      'detached': [],
      'updated': [],
    };

    // Get current related IDs
    final currentIds = await _getCurrentRelatedIds();

    Map<dynamic, Map<String, dynamic>?> newData;

    if (ids is Map) {
      newData = Map<dynamic, Map<String, dynamic>?>.from(ids);
    } else {
      final idList = _normalizeIds(ids);
      newData = {for (var id in idList) id: null};
    }

    final newIds = newData.keys.toList();

    // Determine what to attach, detach, and update
    final toAttach = newIds.where((id) => !currentIds.contains(id)).toList();
    final toDetach = currentIds.where((id) => !newIds.contains(id)).toList();
    final toUpdate = newIds
        .where((id) => currentIds.contains(id) && newData[id] != null)
        .toList();

    // Perform operations
    if (toDetach.isNotEmpty) {
      await detach(toDetach);
      changes['detached'] = toDetach;
    }

    for (final id in toAttach) {
      await attach(id, newData[id]);
      changes['attached']!.add(id);
    }

    for (final id in toUpdate) {
      await _updatePivotRecord(id, newData[id]!);
      changes['updated']!.add(id);
    }

    return changes;
  }

  /// Toggle the relationship with the given IDs
  ///
  /// ```dart
  /// final user = await User.find<User>(1);
  /// await user.roles().toggle([1, 2, 3]);
  /// ```
  Future<Map<String, List<dynamic>>> toggle(dynamic ids) async {
    final idList = _normalizeIds(ids);
    final currentIds = await _getCurrentRelatedIds();

    final Map<String, List<dynamic>> changes = {
      'attached': [],
      'detached': [],
    };

    for (final id in idList) {
      if (currentIds.contains(id)) {
        await detach(id);
        changes['detached']!.add(id);
      } else {
        await attach(id);
        changes['attached']!.add(id);
      }
    }

    return changes;
  }

  /// Update pivot data for existing relationships
  ///
  /// ```dart
  /// final user = await User.find<User>(1);
  /// await user.roles().updateExistingPivot(1, {'priority': 'urgent'});
  /// ```
  Future<bool> updateExistingPivot(
    dynamic id,
    Map<String, dynamic> pivotData,
  ) async {
    return await _updatePivotRecord(id, pivotData) > 0;
  }

  /// Get pivot data for a specific relationship
  ///
  /// ```dart
  /// final user = await User.find<User>(1);
  /// final pivotData = await user.roles().getPivot(1);
  /// ```
  Future<Map<String, dynamic>?> getPivot(dynamic id) async {
    if (!parent.isPersisted) {
      return null;
    }

    final parentKeyValue = parent.getAttribute(localKey);
    final connection = DModel.connection;

    final columns = ['*'];
    if (pivotColumns.isNotEmpty) {
      columns.addAll(pivotColumns);
    }

    final sql = '''
      SELECT ${columns.join(', ')}
      FROM $pivotTable
      WHERE $foreignPivotKey = @parent_key AND $relatedPivotKey = @related_key
    ''';

    final result = await connection.queryOne(sql, {
      'parent_key': parentKeyValue,
      'related_key': id,
    });

    return result;
  }

  /// Build the query for this relationship
  @override
  RelationshipQuery<T> buildQuery() {
    final query = RelationshipQuery<T>(relatedTable);

    final parentKeyValue = parent.getAttribute(localKey);
    if (parentKeyValue != null) {
      // Join with pivot table
      query.join(
        pivotTable,
        '$pivotTable.$relatedPivotKey = $relatedTable.$foreignKey',
      );

      // Add WHERE condition for parent relationship
      query.where('$pivotTable.$foreignPivotKey = @parent_key', {
        'parent_key': parentKeyValue,
      });
    } else {
      // If parent key is null, return empty result
      query.where('1 = 0');
    }

    return query;
  }

  /// Get default pivot table name
  static String _defaultPivotTable<T>(DModel parent) {
    final parentTable = parent.runtimeType.toString().toLowerCase() + 's';
    final relatedTable = Relationship.getTableName<T>();

    // Sort alphabetically and join with underscore
    final tables = [parentTable, relatedTable]..sort();
    return tables.join('_');
  }

  /// Get default foreign pivot key for parent model
  static String _defaultForeignPivotKey(DModel parent) {
    final tableName = parent.runtimeType.toString().toLowerCase() + 's';
    // Remove 's' suffix and add '_id'
    final singularName = tableName.endsWith('s')
        ? tableName.substring(0, tableName.length - 1)
        : tableName;
    return '${singularName}_id';
  }

  /// Get default related pivot key for related model
  static String _defaultRelatedPivotKey<T>() {
    final tableName = Relationship.getTableName<T>();
    // Remove 's' suffix and add '_id'
    final singularName = tableName.endsWith('s')
        ? tableName.substring(0, tableName.length - 1)
        : tableName;
    return '${singularName}_id';
  }

  /// Normalize IDs to a list
  List<dynamic> _normalizeIds(dynamic ids) {
    if (ids is List) {
      return ids;
    } else {
      return [ids];
    }
  }

  /// Check if a pivot relationship exists
  Future<bool> _pivotExists(dynamic parentId, dynamic relatedId) async {
    final connection = DModel.connection;

    final result = await connection.queryOne('''
      SELECT COUNT(*) as count
      FROM $pivotTable
      WHERE $foreignPivotKey = @parent_id AND $relatedPivotKey = @related_id
    ''', {
      'parent_id': parentId,
      'related_id': relatedId,
    });

    return (result?['count'] ?? 0) > 0;
  }

  /// Insert a pivot record
  Future<void> _insertPivotRecord(Map<String, dynamic> attributes) async {
    final connection = DModel.connection;

    final columns = attributes.keys.join(', ');
    final placeholders = attributes.keys.map((key) => '@$key').join(', ');

    final sql = 'INSERT INTO $pivotTable ($columns) VALUES ($placeholders)';
    await connection.insert(sql, attributes);
  }

  /// Update a pivot record
  Future<int> _updatePivotRecord(
    dynamic relatedId,
    Map<String, dynamic> pivotData,
  ) async {
    if (pivotData.isEmpty) {
      return 0;
    }

    final parentKeyValue = parent.getAttribute(localKey);
    final connection = DModel.connection;

    // Add updated_at if timestamps are enabled
    if (withTimestamps) {
      pivotData['updated_at'] = DateTime.now().toUtc();
    }

    final setClause = pivotData.keys.map((key) => '$key = @$key').join(', ');
    final parameters = Map<String, dynamic>.from(pivotData);
    parameters['parent_key'] = parentKeyValue;
    parameters['related_key'] = relatedId;

    final sql = '''
      UPDATE $pivotTable
      SET $setClause
      WHERE $foreignPivotKey = @parent_key AND $relatedPivotKey = @related_key
    ''';

    return await connection.execute(sql, parameters);
  }

  /// Get current related IDs
  Future<List<dynamic>> _getCurrentRelatedIds() async {
    if (!parent.isPersisted) {
      return [];
    }

    final parentKeyValue = parent.getAttribute(localKey);
    final connection = DModel.connection;

    final results = await connection.query('''
      SELECT $relatedPivotKey
      FROM $pivotTable
      WHERE $foreignPivotKey = @parent_key
    ''', {
      'parent_key': parentKeyValue,
    });

    return results.map((row) => row[relatedPivotKey]).toList();
  }

  @override
  String toString() {
    return 'BelongsToMany<$T>(pivotTable: $pivotTable, foreignPivotKey: $foreignPivotKey, relatedPivotKey: $relatedPivotKey)';
  }
}
