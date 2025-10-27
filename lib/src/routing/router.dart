import 'dart:io';
import 'dart:mirrors';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:shelf_web_socket/shelf_web_socket.dart';
import '../controllers/base_controller.dart';
import '../core/logger.dart';
import 'route_handler.dart';

/// RESTful routing system for D_Server framework
///
/// Provides resource routing, manual route definition, nested routes,
/// and middleware support.
///
/// ## Usage
///
/// ```dart
/// final router = DRouter();
///
/// // Resource routes (RESTful)
/// router.resource('users', UsersController);
/// router.resource('posts', PostsController, only: ['index', 'show']);
/// router.resource('admin/users', AdminUsersController, except: ['destroy']);
///
/// // Manual routes
/// router.get('/', (req) => Response.ok('Hello World!'));
/// router.post('/webhook', webhookHandler);
///
/// // Nested routes
/// router.group('/api/v1', (router) {
///   router.resource('users', ApiUsersController);
///   router.get('/status', statusHandler);
/// });
///
/// // Middleware
/// router.use(corsMiddleware);
/// router.use(authMiddleware, only: ['/admin']);
/// ```
class DRouter {
  final Router _router = Router();
  final List<Middleware> _globalMiddleware = [];
  final Map<String, List<Middleware>> _routeMiddleware = {};
  final ScopedLogger _logger = DLogger.scoped('ROUTER');
  bool _staticFilesEnabled = false;
  bool _webSocketEnabled = false;

  /// Get the underlying Shelf router handler
  Handler get handler {
    Handler baseHandler = _router.call;

    // Apply global middleware in reverse order
    for (final middleware in _globalMiddleware.reversed) {
      baseHandler = middleware(baseHandler);
    }

    return baseHandler;
  }

  /// Add global middleware that applies to all routes
  void use(Middleware middleware, {List<String>? only, List<String>? except}) {
    if (only != null || except != null) {
      // Route-specific middleware
      final routeMiddleware = RouteSpecificMiddleware(
        middleware,
        only: only,
        except: except,
      );
      _globalMiddleware.add(routeMiddleware.call);
    } else {
      _globalMiddleware.add(middleware);
    }
  }

  /// Define RESTful resource routes for a controller
  void resource(
    String name,
    Type controllerType, {
    /// Optional actions to include
    List<String>? only,

    /// Optional actions to exclude
    List<String>? except,

    /// Optional custom path for the resource
    String? path,

    /// Optional alias for the resource name
    String? as,
  }) {
    final resourcePath = path ?? '/$name';
    final resourceName = as ?? name;

    final actions = _getResourceActions(only: only, except: except).toList();
    // sort actions
    // index, new, create, show, edit, update, destroy
    actions.sort((a, b) {
      const order = {
        'index': 0,
        'new': 1,
        'create': 2,
        'show': 3,
        'edit': 4,
        'update': 5,
        'destroy': 6,
      };
      return order[a]!.compareTo(order[b]!);
    });

    _logger.info(
        'Defining resource routes for $resourceName at $resourcePath with actions: $actions');

    for (final action in actions) {
      String route = _buildResourceRoute(resourcePath, action);
      final handler = _createControllerHandler(controllerType, action);

      _logger.info(
          'Creating route for action $action at path $route for controller $controllerType');

      switch (action) {
        case 'index':
          _router.get(route, handler);
          break;
        case 'show':
          _router.get(route, handler);
          break;
        case 'create':
          _router.post(route, handler);
          break;
        case 'update':
          _router.put(route, handler);
          _router.patch(route, handler);
          break;
        case 'destroy':
          _router.delete(route, handler);
          break;
        case 'new':
          _router.get(route, handler);
          break;
        case 'edit':
          _router.get(route, handler);
          break;
      }

      _logger.debug(
          'Registered ${action.toUpperCase()} $route -> $controllerType.$action');
    }
  }

  /// Define nested resource routes
  void nestedResource(
    String parentName,
    String childName,
    Type controllerType, {
    List<String>? only,
    List<String>? except,
  }) {
    final resourcePath =
        '/$parentName/<${parentName.substring(0, parentName.length - 1)}_id>/$childName';
    final actions = _getResourceActions(only: only, except: except);

    for (final action in actions) {
      final route = _buildNestedResourceRoute(resourcePath, action);
      final handler = _createControllerHandler(controllerType, action);

      switch (action) {
        case 'index':
          _router.get(route, handler);
          break;
        case 'show':
          _router.get('$route/<id>', handler);
          break;
        case 'create':
          _router.post(route, handler);
          break;
        case 'update':
          _router.put('$route/<id>', handler);
          _router.patch('$route/<id>', handler);
          break;
        case 'destroy':
          _router.delete('$route/<id>', handler);
          break;
        case 'new':
          _router.get('$route/new', handler);
          break;
        case 'edit':
          _router.get('$route/<id>/edit', handler);
          break;
      }

      _logger.debug(
          'Registered nested ${action.toUpperCase()} $route -> $controllerType.$action');
    }
  }

  /// Define a GET route
  void get(String path, Handler handler, {List<Middleware>? middleware}) {
    final wrappedHandler = _wrapWithMiddleware(handler, middleware);
    _router.get(path, wrappedHandler);
    _logger.debug('Registered GET $path');
  }

  /// Define a POST route
  void post(String path, Handler handler, {List<Middleware>? middleware}) {
    final wrappedHandler = _wrapWithMiddleware(handler, middleware);
    _router.post(path, wrappedHandler);
    _logger.debug('Registered POST $path');
  }

  /// Define a PUT route
  void put(String path, Handler handler, {List<Middleware>? middleware}) {
    final wrappedHandler = _wrapWithMiddleware(handler, middleware);
    _router.put(path, wrappedHandler);
    _logger.debug('Registered PUT $path');
  }

  /// Define a PATCH route
  void patch(String path, Handler handler, {List<Middleware>? middleware}) {
    final wrappedHandler = _wrapWithMiddleware(handler, middleware);
    _router.patch(path, wrappedHandler);
    _logger.debug('Registered PATCH $path');
  }

  /// Define a DELETE route
  void delete(String path, Handler handler, {List<Middleware>? middleware}) {
    final wrappedHandler = _wrapWithMiddleware(handler, middleware);
    _router.delete(path, wrappedHandler);
    _logger.debug('Registered DELETE $path');
  }

  /// Define routes for any HTTP method
  void all(String path, Handler handler, {List<Middleware>? middleware}) {
    final wrappedHandler = _wrapWithMiddleware(handler, middleware);
    _router.all(path, wrappedHandler);
    _logger.debug('Registered ALL $path');
  }

  /// Group routes with a common prefix
  void group(String prefix, void Function(DRouter) callback,
      {List<Middleware>? middleware}) {
    final groupRouter = DRouter();

    // Add group-specific middleware
    if (middleware != null) {
      for (final m in middleware) {
        groupRouter.use(m);
      }
    }

    callback(groupRouter);

    // Mount the group router under the prefix
    _router.mount(prefix, groupRouter.handler);
    _logger.debug('Registered route group: $prefix');
  }

  /// Define a namespace (alias for group)
  void namespace(String name, void Function(DRouter) callback,
      {List<Middleware>? middleware}) {
    group('/$name', callback, middleware: middleware);
  }

  /// Add a catch-all route for handling 404s
  void notFound(Handler handler) {
    _router.all('/<path|.*>', handler);
    _logger.debug('Registered 404 handler');
  }

  /// Serve static files from a directory
  void serveStatic({
    String directory = 'public',
    String urlPath = '/assets',
    bool listDirectories = false,
    Duration? maxAge,
  }) {
    if (_staticFilesEnabled) {
      _logger.warning('Static files already enabled, skipping...');
      return;
    }

    // Check if directory exists
    final dir = Directory(directory);
    if (!dir.existsSync()) {
      _logger.warning(
          'Static directory "$directory" does not exist, creating it...');
      try {
        dir.createSync(recursive: true);
      } catch (e) {
        _logger.error('Failed to create directory "$directory": $e');
        return;
      }
    }

    // Create static file handler with options
    final staticHandler = RouteHandler.staticFiles(
      directory,
      listDirectories: listDirectories,
      maxAge: maxAge,
    );

    // Register the route
    final routePath =
        urlPath.endsWith('/<path|.*>') ? urlPath : '$urlPath/<path|.*>';

    _router.get(routePath, staticHandler);
    _staticFilesEnabled = true;

    _logger.info('Static files enabled: $urlPath -> $directory');
    _logger.debug('Static route registered: GET $routePath');
  }

  /// Enable default static file serving
  void enableDefaultStatic() {
    serveStatic();
  }

  /// Create a controller action handler
  Handler _createControllerHandler(Type controllerType, String actionName) {
    return (Request request) async {
      try {
        // Create controller instance using reflection
        final classMirror = reflectClass(controllerType);
        final controller =
            classMirror.newInstance(Symbol(''), []).reflectee as DController;

        // Extract route parameters
        final params = <String, dynamic>{};
        request.context.forEach((key, value) {
          if (key != 'shelf_router/params') {
            params[key] = value;
          }
        });

        // Add Shelf router params
        final shelfParams =
            request.context['shelf_router/params'] as Map<String, String>?;
        if (shelfParams != null) {
          params.addAll(shelfParams);
        }

        // Initialize controller with request and params
        controller.initialize(request, params);

        // Process the action
        return await controller.processAction(actionName);
      } catch (e) {
        _logger.error('Controller error in $controllerType.$actionName: $e');
        return Response.internalServerError(
          body: '{"error": "Internal server error"}',
          headers: {'content-type': 'application/json'},
        );
      }
    };
  }

  /// Get the list of actions for a resource
  List<String> _getResourceActions({List<String>? only, List<String>? except}) {
    const allActions = [
      'index',
      'show',
      'new',
      'create',
      'edit',
      'update',
      'destroy'
    ];

    if (only != null) {
      return allActions.where((action) => only.contains(action)).toList();
    }

    if (except != null) {
      return allActions.where((action) => !except.contains(action)).toList();
    }

    return allActions;
  }

  /// Build the route path for a resource action
  String _buildResourceRoute(String basePath, String action) {
    switch (action) {
      case 'new':
        return '$basePath/new';
      case 'edit':
        return '$basePath/<id>/edit';
      case 'index':
      case 'create':
        return basePath;
      case 'show':
      case 'update':
      case 'destroy':
        return '$basePath/<id>';
      default:
        return basePath;
    }
  }

  /// Build the route path for a nested resource action
  String _buildNestedResourceRoute(String basePath, String action) {
    switch (action) {
      case 'new':
        return '$basePath/new';
      case 'edit':
        return '$basePath/<id>/edit';
      case 'index':
      case 'create':
        return basePath;
      case 'show':
      case 'update':
      case 'destroy':
        return '$basePath/<id>';
      default:
        return basePath;
    }
  }

  /// Wrap a handler with middleware
  Handler _wrapWithMiddleware(Handler handler, List<Middleware>? middleware) {
    if (middleware == null || middleware.isEmpty) {
      return handler;
    }

    Handler wrappedHandler = handler;
    for (final m in middleware.reversed) {
      wrappedHandler = m(wrappedHandler);
    }

    return wrappedHandler;
  }

  /// Get route information for debugging
  Map<String, dynamic> getRouteInfo() {
    return {
      'global_middleware_count': _globalMiddleware.length,
      'route_middleware_count': _routeMiddleware.length,
      'static_files_enabled': _staticFilesEnabled,
    };
  }
}

/// Middleware that applies only to specific routes
class RouteSpecificMiddleware {
  final Middleware _middleware;
  final List<String>? _only;
  final List<String>? _except;

  RouteSpecificMiddleware(this._middleware,
      {List<String>? only, List<String>? except})
      : _only = only,
        _except = except;

  Middleware get call => (Handler innerHandler) {
        return (Request request) {
          final path = request.url.path;

          // Check if middleware should be applied
          if (_only != null) {
            final shouldApply =
                _only!.any((pattern) => _matchesPattern(path, pattern));
            if (!shouldApply) {
              return innerHandler(request);
            }
          }

          if (_except != null) {
            final shouldSkip =
                _except!.any((pattern) => _matchesPattern(path, pattern));
            if (shouldSkip) {
              return innerHandler(request);
            }
          }

          // Apply middleware
          return _middleware(innerHandler)(request);
        };
      };

  bool _matchesPattern(String path, String pattern) {
    // Simple pattern matching - you could implement more sophisticated matching here
    if (pattern.endsWith('*')) {
      return path.startsWith(pattern.substring(0, pattern.length - 1));
    }
    return path == pattern;
  }
}

/// Route definition for storing route metadata
class RouteDefinition {
  final String method;
  final String path;
  final Type? controllerType;
  final String? action;
  final Handler? handler;
  final List<Middleware> middleware;

  RouteDefinition({
    required this.method,
    required this.path,
    this.controllerType,
    this.action,
    this.handler,
    this.middleware = const [],
  });

  @override
  String toString() {
    if (controllerType != null && action != null) {
      return '$method $path -> $controllerType.$action';
    }
    return '$method $path -> [Handler]';
  }
}

/// Exception thrown when routing operations fail
class RoutingException implements Exception {
  final String message;

  RoutingException(this.message);

  @override
  String toString() => 'RoutingException: $message';
}
