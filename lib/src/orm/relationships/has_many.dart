import '../model.dart';
import 'relationship.dart';

/// Represents a one-to-many relationship where the parent model has many related models
///
/// This relationship type is used when a model is associated with multiple
/// instances of another model, and the foreign key is stored in the related models.
///
/// ## Example
///
/// ```dart
/// class User extends DModel {
///   static String get tableName => 'users';
///
///   // User has many Posts
///   HasMany<Post> posts() => hasMany<Post>();
///
///   // Custom foreign key
///   HasMany<Post> articles() => hasMany<Post>(foreignKey: 'author_id');
/// }
///
/// class Post extends DModel {
///   static String get tableName => 'posts';
///
///   String? get title => getAttribute<String>('title');
///   String? get content => getAttribute<String>('content');
///   int? get userId => getAttribute<int>('user_id');
/// }
///
/// // Usage
/// final user = await User.find<User>(1);
/// final posts = await user.posts().get();
/// final latestPosts = await user.posts().orderBy('created_at', 'DESC').limit(5).get();
/// ```
class HasMany<T extends DModel> extends Relationship<T> {
  /// Creates a HasMany relationship
  ///
  /// [parent] The model instance that owns this relationship
  /// [foreignKey] The foreign key column in the related table (defaults to parent_id)
  /// [localKey] The local key column in the parent table (defaults to primary key)
  HasMany(
    super.parent, {
    super.foreignKey,
    super.localKey,
  });

  /// Create a new related model and associate it with the parent
  ///
  /// ```dart
  /// final user = User();
  /// user.name = 'John Doe';
  /// await user.save();
  ///
  /// final post = await user.posts().create({
  ///   'title': 'My First Post',
  ///   'content': 'Hello World!',
  /// });
  /// ```
  Future<T?> create(Map<String, dynamic> attributes) async {
    if (!parent.isPersisted) {
      throw RelationshipException(
          'Cannot create related model on unsaved parent model');
    }

    // Set the foreign key to link to parent
    attributes[foreignKey] = parent.getAttribute(localKey);

    // Create the related model
    final relatedModel = Relationship.createInstance<T>({});
    relatedModel.loadAttributes(attributes);

    final saved = await relatedModel.save();
    if (saved) {
      // Clear collection cache since we added a new item
      super.collectionCache = null;
      super.isLoaded = false;
      return relatedModel;
    }

    return null;
  }

  /// Save an existing model instance as a related model
  ///
  /// ```dart
  /// final user = await User.find<User>(1);
  /// final post = Post();
  /// post.title = 'New Post';
  /// post.content = 'Content here';
  ///
  /// await user.posts().save(post);
  /// ```
  Future<bool> save(T model) async {
    if (!parent.isPersisted) {
      throw RelationshipException(
          'Cannot save related model on unsaved parent model');
    }

    // Set the foreign key
    model.setAttribute(foreignKey, parent.getAttribute(localKey));

    final saved = await model.save();
    if (saved) {
      // Clear collection cache since we added/modified an item
      super.collectionCache = null;
      super.isLoaded = false;
    }

    return saved;
  }

  /// Save multiple model instances as related models
  ///
  /// ```dart
  /// final user = await User.find<User>(1);
  /// final posts = [post1, post2, post3];
  /// await user.posts().saveMany(posts);
  /// ```
  Future<List<T>> saveMany(List<T> models) async {
    final saved = <T>[];

    for (final model in models) {
      final success = await save(model);
      if (success) {
        saved.add(model);
      }
    }

    return saved;
  }

  /// Create multiple related models
  ///
  /// ```dart
  /// final user = await User.find<User>(1);
  /// final posts = await user.posts().createMany([
  ///   {'title': 'Post 1', 'content': 'Content 1'},
  ///   {'title': 'Post 2', 'content': 'Content 2'},
  /// ]);
  /// ```
  Future<List<T>> createMany(List<Map<String, dynamic>> attributesList) async {
    final created = <T>[];

    for (final attributes in attributesList) {
      final model = await create(attributes);
      if (model != null) {
        created.add(model);
      }
    }

    return created;
  }

  /// Update all related models with new attributes
  ///
  /// ```dart
  /// final user = await User.find<User>(1);
  /// await user.posts().updateAll({'status': 'published'});
  /// ```
  Future<int> updateAll(Map<String, dynamic> attributes) async {
    final query = buildQuery();

    if (attributes.isEmpty) {
      return 0;
    }

    final setClause = attributes.keys.map((key) => '$key = @$key').join(', ');
    final whereClause =
        query.wheres.isNotEmpty ? 'AND ${query.wheres.join(' AND ')}' : '';

    final parentKeyValue = parent.getAttribute(localKey);
    final parameters = Map<String, dynamic>.from(attributes);
    parameters['parent_key'] = parentKeyValue;
    parameters.addAll(query.parameters);

    final sql = '''
      UPDATE ${relatedTable}
      SET $setClause
      WHERE $foreignKey = @parent_key $whereClause
    ''';

    final connection = DModel.connection;
    final rowsAffected = await connection.execute(sql, parameters);

    // Clear cache since we updated related models
    clearCache();

    return rowsAffected;
  }

  /// Delete all related models
  ///
  /// ```dart
  /// final user = await User.find<User>(1);
  /// await user.posts().deleteAll();
  /// ```
  Future<int> deleteAll() async {
    final query = buildQuery();
    final whereClause =
        query.wheres.isNotEmpty ? 'AND ${query.wheres.join(' AND ')}' : '';

    final parentKeyValue = parent.getAttribute(localKey);
    final parameters = <String, dynamic>{'parent_key': parentKeyValue};
    parameters.addAll(query.parameters);

    final sql = '''
      DELETE FROM ${relatedTable}
      WHERE $foreignKey = @parent_key $whereClause
    ''';

    final connection = DModel.connection;
    final rowsAffected = await connection.execute(sql, parameters);

    // Clear cache since we deleted related models
    clearCache();

    return rowsAffected;
  }

  /// Dissociate all related models by setting foreign key to null
  ///
  /// ```dart
  /// final user = await User.find<User>(1);
  /// await user.posts().dissociateAll();
  /// ```
  Future<int> dissociateAll() async {
    return await updateAll({foreignKey: null});
  }

  /// Get models with additional WHERE conditions
  ///
  /// ```dart
  /// final user = await User.find<User>(1);
  /// final publishedPosts = await user.posts().wherePublished().get();
  /// ```
  HasMany<T> wherePublished() {
    return whereCondition('status = @status', {'status': 'published'});
  }

  /// Add a WHERE condition and return a new HasMany instance
  HasMany<T> whereCondition(String condition,
      [Map<String, dynamic>? parameters]) {
    final newRelationship =
        HasMany<T>(parent, foreignKey: foreignKey, localKey: localKey);
    final query = newRelationship.buildQuery();
    query.where(condition, parameters);
    return newRelationship;
  }

  /// Add an ORDER BY clause and return a new HasMany instance
  HasMany<T> orderBy(String column, [String direction = 'ASC']) {
    final newRelationship =
        HasMany<T>(parent, foreignKey: foreignKey, localKey: localKey);
    final query = newRelationship.buildQuery();
    query.orderBy(column, direction);
    return newRelationship;
  }

  /// Add a LIMIT clause and return a new HasMany instance
  HasMany<T> limit(int count) {
    final newRelationship =
        HasMany<T>(parent, foreignKey: foreignKey, localKey: localKey);
    final query = newRelationship.buildQuery();
    query.limit(count);
    return newRelationship;
  }

  /// Add an OFFSET clause and return a new HasMany instance
  HasMany<T> offset(int count) {
    final newRelationship =
        HasMany<T>(parent, foreignKey: foreignKey, localKey: localKey);
    final query = newRelationship.buildQuery();
    query.offset(count);
    return newRelationship;
  }

  /// Build the query for this relationship
  @override
  RelationshipQuery<T> buildQuery() {
    final query = RelationshipQuery<T>(relatedTable);

    // Add WHERE condition to match foreign key with parent's local key
    final parentKeyValue = parent.getAttribute(localKey);
    if (parentKeyValue != null) {
      query.where('$relatedTable.$foreignKey = @parent_key', {
        'parent_key': parentKeyValue,
      });
    } else {
      // If parent key is null, return empty result
      query.where('1 = 0');
    }

    return query;
  }

  /// Get all related models (alias for get())
  Future<List<T>> get all async => await get();

  /// Get the first related model (alias for first())
  Future<T?> get firstOrNull async => await first();

  /// Get the first related model or throw exception
  Future<T> get firstOrFail async {
    final result = await first();
    if (result == null) {
      throw RelationshipException('No related $T found');
    }
    return result;
  }

  @override
  String toString() {
    return 'HasMany<$T>(foreignKey: $foreignKey, localKey: $localKey)';
  }
}
