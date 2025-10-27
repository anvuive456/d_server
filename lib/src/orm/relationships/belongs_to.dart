import '../model.dart';
import 'relationship.dart';

/// Represents a belongs-to relationship (inverse of has-one/has-many)
///
/// This relationship type is used when a model belongs to another model,
/// and the foreign key is stored in the current model.
///
/// ## Example
///
/// ```dart
/// class Post extends DModel {
///   static String get tableName => 'posts';
///
///   // Post belongs to User
///   BelongsTo<User> user() => belongsTo<User>();
///
///   // Custom foreign key
///   BelongsTo<User> author() => belongsTo<User>(foreignKey: 'author_id');
/// }
///
/// class User extends DModel {
///   static String get tableName => 'users';
///
///   String? get name => getAttribute<String>('name');
///   String? get email => getAttribute<String>('email');
/// }
///
/// // Usage
/// final post = await Post.find<Post>(1);
/// final user = await post.user().first();
/// ```
class BelongsTo<T extends DModel> extends Relationship<T> {
  /// Creates a BelongsTo relationship
  ///
  /// [parent] The model instance that owns this relationship
  /// [foreignKey] The foreign key column in the current table (defaults to related_id)
  /// [ownerKey] The key column in the related table (defaults to primary key)
  BelongsTo(
    super.parent, {
    super.foreignKey,
    String? ownerKey,
  }) : super(localKey: ownerKey ?? DModel.primaryKey);

  /// Associate the parent model with another model
  ///
  /// ```dart
  /// final post = Post();
  /// final user = await User.find<User>(1);
  ///
  /// await post.user().associate(user);
  /// await post.save();
  /// ```
  Future<bool> associate(T model) async {
    if (!model.isPersisted) {
      throw RelationshipException('Cannot associate with unsaved model');
    }

    // Set the foreign key to the related model's key
    final relatedKeyValue = model.getAttribute(localKey);
    parent.setAttribute(foreignKey, relatedKeyValue);

    // Update cache
    super.singleCache = model;
    super.isLoaded = true;

    return true;
  }

  /// Associate the parent model using a key value
  ///
  /// ```dart
  /// final post = Post();
  /// await post.user().associateById(1);
  /// await post.save();
  /// ```
  Future<bool> associateById(dynamic id) async {
    parent.setAttribute(foreignKey, id);

    // Clear cache since we changed the association
    clearCache();

    return true;
  }

  /// Dissociate the parent model from the related model
  ///
  /// ```dart
  /// final post = await Post.find<Post>(1);
  /// await post.user().dissociate();
  /// await post.save();
  /// ```
  Future<bool> dissociate() async {
    parent.setAttribute(foreignKey, null);

    // Clear cache
    clearCache();

    return true;
  }

  /// Update the related model
  ///
  /// ```dart
  /// final post = await Post.find<Post>(1);
  /// await post.user().update({'name': 'Updated Name'});
  /// ```
  Future<bool> update(Map<String, dynamic> attributes) async {
    final related = await first();
    if (related != null) {
      return await related.update(attributes);
    }
    return false;
  }

  /// Create a new related model and associate it
  ///
  /// ```dart
  /// final post = Post();
  /// final user = await post.user().create({
  ///   'name': 'John Doe',
  ///   'email': 'john@example.com',
  /// });
  /// await post.save();
  /// ```
  Future<T?> create(Map<String, dynamic> attributes) async {
    // Create the related model
    final relatedModel = Relationship.createInstance<T>({});
    relatedModel.loadAttributes(attributes);

    final saved = await relatedModel.save();
    if (saved) {
      // Associate with the newly created model
      await associate(relatedModel);
      return relatedModel;
    }

    return null;
  }

  /// Get or create the related model
  ///
  /// ```dart
  /// final post = await Post.find<Post>(1);
  /// final user = await post.user().firstOrCreate({'name': 'Default User'});
  /// ```
  Future<T> firstOrCreate(Map<String, dynamic> attributes) async {
    final existing = await first();
    if (existing != null) {
      return existing;
    }

    final created = await create(attributes);
    if (created == null) {
      throw RelationshipException('Failed to create related model');
    }

    return created;
  }

  /// Check if the parent model is associated with another model
  ///
  /// ```dart
  /// final post = await Post.find<Post>(1);
  /// final isAssociated = post.user().isAssociated();
  /// ```
  bool isAssociated() {
    final foreignKeyValue = parent.getAttribute(foreignKey);
    return foreignKeyValue != null;
  }

  /// Get the foreign key value
  ///
  /// ```dart
  /// final post = await Post.find<Post>(1);
  /// final userId = post.user().getForeignKeyValue();
  /// ```
  dynamic getForeignKeyValue() {
    return parent.getAttribute(foreignKey);
  }

  /// Build the query for this relationship
  @override
  RelationshipQuery<T> buildQuery() {
    final query = RelationshipQuery<T>(relatedTable);

    // Add WHERE condition to match related model's key with foreign key value
    final foreignKeyValue = parent.getAttribute(foreignKey);
    if (foreignKeyValue != null) {
      query.where('$relatedTable.$localKey = @foreign_key_value', {
        'foreign_key_value': foreignKeyValue,
      });
    } else {
      // If foreign key is null, return empty result
      query.where('1 = 0');
    }

    return query;
  }

  /// Get the related model (alias for first())
  Future<T?> get getRelated async => await first();

  /// Get the related model or throw exception if not found
  Future<T> get getRelatedOrFail async {
    final result = await first();
    if (result == null) {
      throw RelationshipException('No related $T found');
    }
    return result;
  }

  /// Get the owner key (alias for localKey for consistency)
  String get ownerKey => localKey;

  @override
  String toString() {
    return 'BelongsTo<$T>(foreignKey: $foreignKey, ownerKey: $ownerKey)';
  }
}
