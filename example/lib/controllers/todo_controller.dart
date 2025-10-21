import 'package:d_server/d_server.dart';

import '../models/todo.dart';

/// Controller for managing Todo items
class TodoController extends DController {
  /// GET /todo
  @override
  Future<Response> index() async {
    final todos = await Todo.listAll();
    return render(
      'todo/index',
      locals: {
        'title': 'Todo List',
        'todos': todos
            .map((e) => {
                  'id': e.id,
                  'title': e.title,
                  'completed': e.completed,
                  'created_at': e.createdAt?.toIso8601String(),
                  'updated_at': e.updatedAt?.toIso8601String(),
                })
            .toList()
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
