import 'package:d_server/d_server.dart';
import 'controllers/todo_controller.dart';

void main() async {
  final app = await DApplication.fromConfigFile('config/config.yml');
  app.router.resource('todos', TodoController, path: '/todo', as: 'todo');

  // Start the server
  await app.start();
}
