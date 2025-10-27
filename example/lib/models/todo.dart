import 'package:d_server/d_server.dart';

import 'task.dart';

/// Model class for Todo items
class Todo extends DModel {
  static String get tableName => 'todos';

  // Example attributes - modify as needed
  String? get title => getAttribute<String>('title');
  set title(String? value) => setAttribute('title', value);

  bool get completed => getNotNullAttribute<bool>('completed');
  set completed(bool? value) => setAttribute('completed', value);

  /// Relationship: One Todo has many Tasks
  List<Task> get taskList => getRelationship<List<Task>>('tasks') ?? [];

  DateTime? get createdAt => getAttribute<DateTime>('created_at');
  DateTime? get updatedAt => getAttribute<DateTime>('updated_at');

  // Add your model methods here

  /// Has many relationship with Task
  HasMany<Task> get tasks => hasMany<Task>(foreignKey: 'todo_id');

  /// Custom finder methods
  static Future<List<Todo>> listAll({
    Map<String, dynamic>? filters,
    Map<String, String>? sort,
    int? limit,
    int? offset,
  }) async {
    return await DModel.all<Todo>();
  }

  /// Create a new Todo item
  static Future<Todo?> create({required String title}) async {
    final todo = Todo();
    todo.title = title;
    todo.completed = false;
    final res = await todo.save();
    return res ? todo : null;
  }

  /// Find a Todo item by its ID
  static Future<Todo?> findById(String id) async {
    return await DModel.find<Todo>(id);
  }
}
