import 'package:d_server/d_server.dart';

import 'todo.dart';

class Task extends DModel {
  static String get tableName => 'tasks';

  // Example attributes - modify as needed
  String? get name => getAttribute<String>('name');
  set name(String? value) => setAttribute('name', value);

  bool get completed => getNotNullAttribute<bool>('completed');
  set completed(bool? value) => setAttribute('completed', value);

  DateTime? get createdAt => getAttribute<DateTime>('created_at');
  DateTime? get updatedAt => getAttribute<DateTime>('updated_at');

  // Add your model methods here
  /// Belongs to relationship with Todo
  BelongsTo<Todo> get todo => belongsTo<Todo>(foreignKey: 'todo_id');
}
