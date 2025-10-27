import '../model.dart';
import 'relationship.dart';

/// Represents a one-to-one relationship where the parent model has one related model
///
/// This relationship type is used when a model is associated with exactly one
/// instance of another model, and the foreign key is stored in the related model.
///
/// ## Example
///
/// ```dart
/// class User extends DModel {
///   static String get tableName => 'users';
///
///   // User has one Profile
///   HasOne<Profile> profile() => hasOne<Profile>();
///
///   // Custom foreign key
///   HasOne<Profile> customProfile() => hasOne<Profile>(foreignKey: 'owner_id');
/// }
///
/// class Profile extends DModel {
///   static String get tableName => 'profiles';
///
///   String? get bio => getAttribute<String>('bio');
///   int? get userId => getAttribute<int>('user_id');
/// }
///
/// // Usage
/// final user = await User.find<User>(1);
/// final profile = await user.profile().first();
/// ```
class HasOne<T extends DModel> extends Relationship<T> {
  /// Creates a HasOne relationship
  ///
  /// [parent] The model instance that owns this relationship
  /// [foreignKey] The foreign key column in the related table (defaults to parent_id)
  /// [localKey] The local key column in the parent table (defaults to primary key)
  HasOne(
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
  /// final profile = await user.profile().create({
  ///   'bio': 'Software Developer',
  ///   'avatar': 'avatar.jpg',
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
      // Update cache
      super.singleCache = relatedModel;
      super.isLoaded = true;
      return relatedModel;
    }

    return null;
  }

  /// Save an existing model instance as the related model
  ///
  /// ```dart
  /// final user = await User.find<User>(1);
  /// final profile = Profile();
  /// profile.bio = 'New bio';
  ///
  /// await user.profile().save(profile);
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
      // Update cache
      super.singleCache = model;
      super.isLoaded = true;
    }

    return saved;
  }

  /// Update the related model with new attributes
  ///
  /// ```dart
  /// final user = await User.find<User>(1);
  /// await user.profile().update({'bio': 'Updated bio'});
  /// ```
  Future<bool> update(Map<String, dynamic> attributes) async {
    final related = await first();
    if (related != null) {
      return await related.update(attributes);
    }
    return false;
  }

  /// Delete the related model
  ///
  /// ```dart
  /// final user = await User.find<User>(1);
  /// await user.profile().delete();
  /// ```
  Future<bool> delete() async {
    final related = await first();
    if (related != null) {
      final deleted = await related.delete();
      if (deleted) {
        clearCache();
      }
      return deleted;
    }
    return false;
  }

  /// Dissociate the related model by setting foreign key to null
  ///
  /// ```dart
  /// final user = await User.find<User>(1);
  /// await user.profile().dissociate();
  /// ```
  Future<bool> dissociate() async {
    final related = await first();
    if (related != null) {
      related.setAttribute(foreignKey, null);
      final saved = await related.save();
      if (saved) {
        clearCache();
      }
      return saved;
    }
    return false;
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

  /// Get the related model (alias for first())
  Future<T?> get getRelated async => await first();

  @override
  String toString() {
    return 'HasOne<$T>(foreignKey: $foreignKey, localKey: $localKey)';
  }
}
