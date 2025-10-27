import 'package:d_server/d_server.dart';
// import 'controllers/auth_controller.dart';
import 'controllers/todo_controller.dart';

void main() async {
  final app = await DApplication.fromConfigFile('config/config.yml');

  app.router.enableDefaultStatic();
  // final authMiddleware = AuthenticationMiddleware();
  // app.use(authMiddleware.handler);
  app.router.resource('todos', TodoController);
  // app.router.resource('login', AuthController);

  app.router.notFound((Request req) async {
    return Response(
      404,
      headers: {'Content-Type': 'text/html'},
      body: app.templates.renderWithLayout('errors/404', 'application', {}),
    );
  });

  // Start the server
  await app.start();
}
