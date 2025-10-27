import 'package:d_server/d_server.dart';

import '../models/task.dart';
import '../models/todo.dart';

/// Controller for managing Todo items
class TodoController extends DController with Authenticatable {
  /// GET /todo
  @override
  Future<Response> index() async {
    final todos = await DModel.query<Todo>()
        .withRelation('tasks')
        .withRelation('tasks.todo')
        .get();
    DLogger.info('Fetched ${todos} todos from database');

    DLogger.info('Rendering ${todos.length} todos with tasks');

    DLogger.info('Todos data: ${todos.map((t) => t.toMap())}');

    return render(
      'todo/index',
      locals: {
        'title': 'Todo List',
        'todos': todos
            .map((todo) => {
                  'id': todo.id,
                  'title': todo.title,
                  'completed': todo.completed,
                  'created_at': todo.createdAt?.toIso8601String(),
                  'updated_at': todo.updatedAt?.toIso8601String(),
                  'tasks': todo.taskList
                      .map((task) => {
                            'id': task.id,
                            'name': task.name,
                            'completed': task.completed,
                            'created_at': task.createdAt?.toIso8601String(),
                            'updated_at': task.updatedAt?.toIso8601String(),
                          })
                      .toList(),
                })
            .toList(),
      },
    );
  }

  /// GET /todo/:id
  @override
  Future<Response> show() async {
    final id = param<String>('id');
    if (id == null) {
      return render('errors/404');
    }

    final todo = await Todo.findById(id);
    if (todo == null) {
      return render('errors/404');
    }

    return render(
      'todo/show',
      locals: {
        'title': 'Todo Detail',
        'todo': todo.toMap(),
      },
    );
  }

  /// POST /todo
  @override
  Future<Response> create() async {
    final body = await parseBody();
    // TODO: Implement create action
    final todo = Todo();
    todo.title = body['title'] as String?;
    todo.completed = body['completed'] as bool? ?? false;
    final saved = await todo.save();
    if (saved) {
      setFlash('success', 'Todo item created successfully.');
    }
    return redirect('/todos');
  }

  /// PUT/PATCH /todo/:id
  @override
  Future<Response> update() async {
    final id = param<String>('id');
    final body = await parseBody();
    // TODO: Implement update action
    return json({'id': id, 'message': 'Updated', 'data': body});
  }

  /// DELETE /todo/:id
  @override
  Future<Response> destroy() async {
    final id = param<String>('id');
    // TODO: Implement destroy action
    return json({'id': id, 'message': 'Deleted'});
  }
}
