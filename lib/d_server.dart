/// D_Server - A cool web framework for Dart
///
/// D_Server provides a complete web framework with:
/// - Active Record ORM with PostgreSQL support
/// - RESTful routing system
/// - Controller-based architecture with action filters
/// - Mustache template engine integration
/// - Built-in authentication (JWT + Sessions)
/// - CLI tools for code generation
/// - Hot reload development server
///
/// ## Quick Start
///
/// ```dart
/// import 'package:d_server/d_server.dart';
///
/// void main() async {
///   final app = DApplication({
///     'database': {
///       'host': 'localhost',
///       'port': 5432,
///       'database': 'myapp',
///       'username': 'user',
///       'password': 'password',
///     },
///     'port': 3000,
///     'jwt_secret': 'your-secret-key',
///   });
///
///   // Define routes
///   app.router.resource('users', UsersController);
///   app.router.get('/', (req) => Response.ok('Hello World!'));
///
///   await app.start();
/// }
/// ```
library d_server;

// Core framework
export 'src/core/application.dart';
export 'src/core/logger.dart';
export 'src/core/config.dart';

// ORM
export 'src/orm/model.dart';
export 'src/orm/database_connection.dart';

// Migrations
export 'src/migrations/migration.dart';
export 'src/migrations/migration_runner.dart';

// Routing
export 'src/routing/router.dart';
export 'src/routing/route_handler.dart';

// Controllers
export 'src/controllers/base_controller.dart' hide UnauthorizedException;
export 'src/controllers/response_helpers.dart';

// Templates
export 'src/templates/template_engine.dart';

// Authentication
export 'src/auth/user.dart';
export 'src/auth/authentication_middleware.dart';
export 'src/auth/authenticatable.dart';
export 'src/auth/session_store.dart';

// Configuration
export 'src/config/hot_reload_config.dart';

// Hot Reload (for development)
export 'src/hot_reload/hot_reload_manager.dart';
export 'src/hot_reload/debounced_file_watcher.dart';

// CLI
// export 'src/cli/cli.dart';
// export 'src/cli/generators.dart';
// export 'src/cli/hot_reload.dart';

// Re-export commonly used Shelf types
export 'package:shelf/shelf.dart'
    show Request, Response, Handler, Middleware, Pipeline;
export 'package:shelf_router/shelf_router.dart' show Router;
