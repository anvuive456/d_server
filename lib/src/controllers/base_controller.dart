import 'dart:convert';
import 'dart:io';
import 'package:d_server/src/auth/authenticatable.dart';
import 'package:shelf/shelf.dart';
import '../core/logger.dart';
import '../templates/template_engine.dart';

/// Base controller class for D_Server framework
///
/// Provides action filters, response helpers, request parameter handling,
/// and session management.
///
/// ## Usage
///
/// ```dart
/// class UsersController extends DController {
///   @override
///   Future<void> beforeAction() async {
///     // Authentication check
///     if (!isAuthenticated) {
///       throw UnauthorizedException('Login required');
///     }
///   }
///
///   Future<Response> index() async {
///     final users = await User.all<User>();
///     return json({'users': users.map((u) => u.attributes).toList()});
///   }
///
///   Future<Response> show() async {
///     final id = param<int>('id');
///     final user = await User.find<User>(id);
///
///     if (user == null) {
///       return json({'error': 'User not found'}, status: 404);
///     }
///
///     return render('users/show', {'user': user.attributes});
///   }
///
///   Future<Response> create() async {
///     final body = await parseBody();
///     final user = await User.create<User>(body);
///
///     if (user != null) {
///       return json({'user': user.attributes}, status: 201);
///     } else {
///       return json({'error': 'Failed to create user'}, status: 422);
///     }
///   }
/// }
/// ```
abstract class DController {
  static final ScopedLogger _logger = DLogger.scoped('CONTROLLER');
  static TemplateEngine? _templateEngine;

  late Request request;
  late Map<String, dynamic> params;
  Map<String, dynamic> session = {};
  Map<String, dynamic> flash = {};

  /// Set the template engine for all controllers
  static void setTemplateEngine(TemplateEngine engine) {
    _templateEngine = engine;
  }

  /// Initialize the controller with request data
  void initialize(Request req, Map<String, dynamic> routeParams) {
    request = req;
    params = Map<String, dynamic>.from(routeParams);

    // Extract query parameters
    request.url.queryParameters.forEach((key, value) {
      params[key] = value;
    });

    // Load session and flash from request context
    if (request.context.containsKey('session')) {
      final sessionData = request.context['session'];
      session = sessionData is Map<String, dynamic>
          ? Map<String, dynamic>.from(sessionData)
          : <String, dynamic>{};
    }

    if (request.context.containsKey('flash')) {
      final flashData = request.context['flash'];
      flash = flashData is Map<String, dynamic>
          ? Map<String, dynamic>.from(flashData)
          : <String, dynamic>{};
    }
  }

  /// Get a query parameter value with type casting
  T queryParam<T>(String key, {T? defaultValue}) {
    final value = query[key];

    if (value == null) return defaultValue as T;

    // Handle type conversion
    if (T == String) {
      return value as T;
    } else if (T == int) {
      return int.tryParse(value) as T? ?? defaultValue as T;
    } else if (T == double) {
      return double.tryParse(value) as T? ?? defaultValue as T;
    } else if (T == bool) {
      final lower = value.toLowerCase();
      if (lower == 'true' || lower == '1') return true as T;
      if (lower == 'false' || lower == '0') return false as T;
      return defaultValue as T;
    }

    return value as T;
  }

  /// Process the controller action with filters
  Future<Response> processAction(String actionName) async {
    final stopwatch = Stopwatch()..start();

    try {
      // Before action filter
      await beforeAction();

      // Execute the specific action filter if it exists
      await beforeSpecificAction(actionName);

      // Get the action method and execute it
      final response = await _executeAction(actionName);

      // After action filters
      await afterSpecificAction(actionName);
      await afterAction();

      stopwatch.stop();
      _logger.debug(
          'Action ${runtimeType}.$actionName completed in ${stopwatch.elapsedMilliseconds}ms');

      return response;
    } catch (e) {
      stopwatch.stop();
      _logger
          .error('Action ${runtimeType}.$actionName failed: ${e.toString()}');

      return await handleException(e);
    }
  }

  // Action Filters

  /// Called before every action
  Future<void> beforeAction() async {}

  /// Called after every action
  Future<void> afterAction() async {}

  /// Called before a specific action
  Future<void> beforeSpecificAction(String actionName) async {}

  /// Called after a specific action
  Future<void> afterSpecificAction(String actionName) async {}

  // Response Helpers

  /// Return a JSON response
  Response json(
    Object data, {
    int status = 200,
    Map<String, String>? headers,
  }) {
    final jsonData = jsonEncode(data);
    final responseHeaders = <String, String>{
      'content-type': 'application/json; charset=utf-8',
      ...?headers,
    };

    return Response(status, body: jsonData, headers: responseHeaders);
  }

  /// Render a template with optional layout
  Response render(
    String templateName, {
    Map<String, dynamic>? locals,
    String? layout = 'application',
    int status = 200,
    Map<String, String>? headers,
  }) {
    if (_templateEngine == null) {
      throw StateError('Template engine not configured');
    }
    final templateEngine = _templateEngine!;

    final context = <String, dynamic>{
      'params': params,
      'session': session,
      'flash': flash,
      'request': _requestToMap(),
      ...?locals,
      'has_title': locals != null && locals.containsKey('title'),
    };

    final html = layout != null
        ? templateEngine.renderWithLayout(templateName, layout, context)
        : templateEngine.render(templateName, context);

    final responseHeaders = <String, String>{
      'content-type': 'text/html; charset=utf-8',
      ...?headers,
    };

    return Response(status, body: html, headers: responseHeaders);
  }

  /// Return a plain text response
  Response text(
    String content, {
    int status = 200,
    Map<String, String>? headers,
  }) {
    final responseHeaders = <String, String>{
      'content-type': 'text/plain; charset=utf-8',
      ...?headers,
    };

    return Response(status, body: content, headers: responseHeaders);
  }

  /// Return an HTML response
  Response html(
    String content, {
    int status = 200,
    Map<String, String>? headers,
  }) {
    final responseHeaders = <String, String>{
      'content-type': 'text/html; charset=utf-8',
      ...?headers,
    };

    return Response(status, body: content, headers: responseHeaders);
  }

  /// Redirect to another URL
  Response redirect(
    String location, {
    int status = 302,
    Map<String, String>? headers,
  }) {
    final responseHeaders = <String, String>{
      'location': location,
      ...?headers,
    };

    return Response(status, headers: responseHeaders);
  }

  /// Return a file download response
  Response download(
    File file, {
    String? filename,
    String? contentType,
    Map<String, String>? headers,
  }) {
    final actualFilename = filename ?? file.uri.pathSegments.last;
    final actualContentType = contentType ?? _guessContentType(actualFilename);

    final responseHeaders = <String, String>{
      'content-type': actualContentType,
      'content-disposition': 'attachment; filename="$actualFilename"',
      'content-length': file.lengthSync().toString(),
      ...?headers,
    };

    return Response.ok(
      file.openRead(),
      headers: responseHeaders,
    );
  }

  /// Return a 404 Not Found response
  Response notFound([String? message]) {
    return json(
      {'error': message ?? 'Not Found'},
      status: 404,
    );
  }

  /// Return a 400 Bad Request response
  Response badRequest([String? message]) {
    return json(
      {'error': message ?? 'Bad Request'},
      status: 400,
    );
  }

  /// Return a 401 Unauthorized response
  Response unauthorized([String? message]) {
    return json(
      {'error': message ?? 'Unauthorized'},
      status: 401,
    );
  }

  /// Return a 403 Forbidden response
  Response forbidden([String? message]) {
    return json(
      {'error': message ?? 'Forbidden'},
      status: 403,
    );
  }

  /// Return a 422 Unprocessable Entity response
  Response unprocessableEntity(
    Map<String, dynamic> errors, [
    String? message,
  ]) {
    return json({
      'error': message ?? 'Unprocessable Entity',
      'errors': errors,
    }, status: 422);
  }

  /// Return a 500 Internal Server Error response
  Response internalServerError([String? message]) {
    return json(
      {'error': message ?? 'Internal Server Error'},
      status: 500,
    );
  }

  // Request Helpers

  /// Get a parameter value with type casting
  T? param<T>(String key, {T? defaultValue}) {
    final value = params[key];

    if (value == null) return defaultValue;

    // Handle type conversion
    if (T == String) {
      return value.toString() as T;
    } else if (T == int) {
      if (value is int) return value as T;
      if (value is String) return int.tryParse(value) as T?;
      return defaultValue;
    } else if (T == double) {
      if (value is double) return value as T;
      if (value is num) return value.toDouble() as T;
      if (value is String) return double.tryParse(value) as T?;
      return defaultValue;
    } else if (T == bool) {
      if (value is bool) return value as T;
      if (value is String) {
        final lower = value.toLowerCase();
        if (lower == 'true' || lower == '1') return true as T;
        if (lower == 'false' || lower == '0') return false as T;
      }
      return defaultValue;
    }

    return value as T?;
  }

  /// Parse the request body as JSON
  Future<Map<String, dynamic>> parseBody() async {
    final body = await request.readAsString();

    if (body.isEmpty) {
      return {};
    }

    final contentType = request.headers['content-type'] ?? '';

    if (contentType.contains('application/json')) {
      try {
        final decoded = jsonDecode(body);
        if (decoded is Map<String, dynamic>) {
          return decoded;
        }
        return {'data': decoded};
      } catch (e) {
        throw FormatException('Invalid JSON in request body');
      }
    } else if (contentType.contains('application/x-www-form-urlencoded')) {
      return Uri.splitQueryString(body);
    }

    // Default: treat as plain text
    return {'body': body};
  }

  /// Check if the request is an AJAX request
  bool get isAjax {
    final xRequestedWith = request.headers['x-requested-with'];
    return xRequestedWith?.toLowerCase() == 'xmlhttprequest';
  }

  /// Check if the request is a JSON request
  bool get isJson {
    final contentType = request.headers['content-type'] ?? '';
    final accept = request.headers['accept'] ?? '';
    return contentType.contains('application/json') ||
        accept.contains('application/json');
  }

  /// Get the request method
  String get method => request.method;

  /// Get the request path
  String get path => request.url.path;

  /// Get the request query parameters
  Map<String, String> get query => request.url.queryParameters;

  /// Get request headers
  Map<String, String> get headers => request.headers;

  // Session and Flash Helpers

  /// Set a flash message
  void setFlash(String key, String message) {
    flash[key] = message;
  }

  /// Get a flash message
  String? getFlash(String key) {
    return flash[key];
  }

  /// Set a session value
  void setSession(String key, dynamic value) {
    session[key] = value;
  }

  /// Get a session value
  T? getSession<T>(String key) {
    return session[key] as T?;
  }

  // Private Methods

  Future<Response> _executeAction(String actionName) async {
    // This would typically use reflection to call the method
    // For now, this is a simplified version
    switch (actionName) {
      case 'index':
        return await index();
      case 'show':
        return await show();
      case 'new':
        return await newAction();
      case 'create':
        return await create();
      case 'edit':
        return await edit();
      case 'update':
        return await update();
      case 'destroy':
        return await destroy();
      default:
        throw NoSuchMethodError.withInvocation(
          this,
          Invocation.method(Symbol(actionName), []),
        );
    }
  }

  Map<String, dynamic> _requestToMap() {
    return {
      'method': request.method,
      'path': request.url.path,
      'query': request.url.queryParameters,
      'headers': request.headers,
    };
  }

  String _guessContentType(String filename) {
    final extension = filename.split('.').last.toLowerCase();
    switch (extension) {
      case 'pdf':
        return 'application/pdf';
      case 'zip':
        return 'application/zip';
      case 'txt':
        return 'text/plain';
      case 'csv':
        return 'text/csv';
      case 'json':
        return 'application/json';
      case 'xml':
        return 'application/xml';
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'png':
        return 'image/png';
      case 'gif':
        return 'image/gif';
      default:
        return 'application/octet-stream';
    }
  }

  /// Handle exceptions thrown during action execution
  Future<Response> handleException(dynamic exception) async {
    if (exception is UnauthorizedException) {
      return unauthorized(exception.message);
    } else if (exception is ForbiddenException) {
      return forbidden(exception.message);
    } else if (exception is NotFoundException) {
      return notFound(exception.message);
    } else if (exception is ValidationException) {
      return unprocessableEntity(exception.errors, exception.message);
    } else if (exception is FormatException) {
      return badRequest(exception.message);
    } else if (exception is DRedirectException) {
      return redirect(exception.location, status: exception.statusCode);
    } else {
      _logger.error('Unhandled exception in controller: $exception');
      return internalServerError();
    }
  }

  // Default CRUD actions (can be overridden by subclasses)

  /// GET /resource
  Future<Response> index() async {
    throw UnimplementedError('index action not implemented');
  }

  /// GET /resource/:id
  Future<Response> show() async {
    throw UnimplementedError('show action not implemented');
  }

  /// POST /resource
  Future<Response> create() async {
    throw UnimplementedError('create action not implemented');
  }

  /// PUT/PATCH /resource/:id
  Future<Response> update() async {
    throw UnimplementedError('update action not implemented');
  }

  /// GET /resource/new
  Future<Response> newAction() async {
    throw UnimplementedError('new action not implemented');
  }

  /// GET /resource/:id/edit
  Future<Response> edit() async {
    throw UnimplementedError('edit action not implemented');
  }

  /// DELETE /resource/:id
  Future<Response> destroy() async {
    throw UnimplementedError('destroy action not implemented');
  }
}

// Custom Exceptions

class UnauthorizedException implements Exception {
  final String message;
  UnauthorizedException(this.message);
  @override
  String toString() => 'UnauthorizedException: $message';
}

class ForbiddenException implements Exception {
  final String message;
  ForbiddenException(this.message);
  @override
  String toString() => 'ForbiddenException: $message';
}

class NotFoundException implements Exception {
  final String message;
  NotFoundException(this.message);
  @override
  String toString() => 'NotFoundException: $message';
}

class ValidationException implements Exception {
  final String message;
  final Map<String, dynamic> errors;
  ValidationException(this.message, this.errors);
  @override
  String toString() => 'ValidationException: $message';
}
