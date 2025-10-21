import 'dart:convert';
import 'dart:io';
import 'package:shelf/shelf.dart';
import '../core/logger.dart';

/// Route handler utilities and helpers for D_Server framework
///
/// Provides utilities for creating handlers, parameter validation,
/// and common response patterns.
class RouteHandler {
  static final ScopedLogger _logger = DLogger.scoped('ROUTE_HANDLER');

  /// Create a simple JSON API handler
  static Handler jsonHandler(
    Future<Map<String, dynamic>> Function(Request) callback,
  ) {
    return (Request request) async {
      try {
        final result = await callback(request);
        return Response.ok(
          jsonEncode(result),
          headers: {'content-type': 'application/json'},
        );
      } catch (e) {
        _logger.error('JSON handler error: $e');
        return Response.internalServerError(
          body: jsonEncode({'error': 'Internal server error'}),
          headers: {'content-type': 'application/json'},
        );
      }
    };
  }

  /// Create a handler that validates required parameters
  static Handler withValidation(
    Handler handler,
    List<String> requiredParams,
  ) {
    return (Request request) async {
      final params = request.url.queryParameters;

      for (final param in requiredParams) {
        if (!params.containsKey(param) || params[param]!.isEmpty) {
          return Response.badRequest(
            body: jsonEncode({'error': 'Missing required parameter: $param'}),
            headers: {'content-type': 'application/json'},
          );
        }
      }

      return handler(request);
    };
  }

  /// Create a handler that requires authentication
  static Handler requireAuth(Handler handler) {
    return (Request request) async {
      final authHeader = request.headers['authorization'];

      if (authHeader == null || !authHeader.startsWith('Bearer ')) {
        return Response(
          401,
          body: jsonEncode({'error': 'Authentication required'}),
          headers: {'content-type': 'application/json'},
        );
      }

      return handler(request);
    };
  }

  /// Create a CORS-enabled handler
  static Handler withCors(
    Handler handler, {
    String allowOrigin = '*',
    String allowMethods = 'GET, POST, PUT, DELETE, OPTIONS',
    String allowHeaders = 'Content-Type, Authorization',
  }) {
    return (Request request) async {
      // Handle preflight OPTIONS requests
      if (request.method == 'OPTIONS') {
        return Response.ok('', headers: {
          'access-control-allow-origin': allowOrigin,
          'access-control-allow-methods': allowMethods,
          'access-control-allow-headers': allowHeaders,
        });
      }

      final response = await handler(request);

      // Add CORS headers to the response
      return response.change(headers: {
        'access-control-allow-origin': allowOrigin,
        'access-control-allow-methods': allowMethods,
        'access-control-allow-headers': allowHeaders,
        ...response.headers,
      });
    };
  }

  /// Create a handler with request logging
  static Handler withLogging(Handler handler, {String? tag}) {
    return (Request request) async {
      final stopwatch = Stopwatch()..start();
      final logger = tag != null ? DLogger.scoped(tag) : _logger;

      logger.info('${request.method} ${request.requestedUri}');

      try {
        final response = await handler(request);
        stopwatch.stop();

        logger.info(
            '${request.method} ${request.requestedUri} - ${response.statusCode} (${stopwatch.elapsedMilliseconds}ms)');

        return response;
      } catch (e) {
        stopwatch.stop();
        logger.error(
            '${request.method} ${request.requestedUri} - ERROR: $e (${stopwatch.elapsedMilliseconds}ms)');
        rethrow;
      }
    };
  }

  /// Create a rate-limited handler
  static Handler withRateLimit(
    Handler handler, {
    int maxRequests = 100,
    Duration window = const Duration(minutes: 1),
  }) {
    final Map<String, List<DateTime>> requestCounts = {};

    return (Request request) async {
      final clientIp = request.headers['x-forwarded-for'] ??
          request.headers['x-real-ip'] ??
          'unknown';

      final now = DateTime.now();
      final windowStart = now.subtract(window);

      // Clean old requests
      requestCounts[clientIp]
          ?.removeWhere((time) => time.isBefore(windowStart));

      // Initialize if needed
      requestCounts[clientIp] ??= [];

      // Check rate limit
      if (requestCounts[clientIp]!.length >= maxRequests) {
        return Response(
          429,
          body: jsonEncode({
            'error': 'Rate limit exceeded',
            'retry_after': window.inSeconds,
          }),
          headers: {
            'content-type': 'application/json',
            'retry-after': window.inSeconds.toString(),
          },
        );
      }

      // Add current request
      requestCounts[clientIp]!.add(now);

      return handler(request);
    };
  }

  /// Create a handler that catches and formats exceptions
  static Handler withErrorHandling(Handler handler) {
    return (Request request) async {
      try {
        return await handler(request);
      } on FormatException catch (e) {
        return Response.badRequest(
          body: jsonEncode({'error': 'Invalid format: ${e.message}'}),
          headers: {'content-type': 'application/json'},
        );
      } on StateError catch (e) {
        return Response(
          422,
          body: jsonEncode({'error': 'Invalid state: ${e.message}'}),
          headers: {'content-type': 'application/json'},
        );
      } catch (e) {
        _logger.error('Unhandled error in route handler: $e');
        return Response.internalServerError(
          body: jsonEncode({'error': 'Internal server error'}),
          headers: {'content-type': 'application/json'},
        );
      }
    };
  }

  /// Create a simple static file handler
  static Handler staticFiles(String directory) {
    return (Request request) async {
      final path = request.url.path;
      final file = File('$directory/$path');

      if (!file.existsSync()) {
        return Response.notFound('File not found');
      }

      final contentType = _getContentType(path);
      return Response.ok(
        file.openRead(),
        headers: {
          'content-type': contentType,
          'cache-control': 'public, max-age=3600',
        },
      );
    };
  }

  /// Helper to determine content type from file extension
  static String _getContentType(String path) {
    final extension = path.split('.').last.toLowerCase();

    switch (extension) {
      case 'html':
        return 'text/html';
      case 'css':
        return 'text/css';
      case 'js':
        return 'application/javascript';
      case 'json':
        return 'application/json';
      case 'png':
        return 'image/png';
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'gif':
        return 'image/gif';
      case 'svg':
        return 'image/svg+xml';
      case 'ico':
        return 'image/x-icon';
      case 'txt':
        return 'text/plain';
      case 'pdf':
        return 'application/pdf';
      default:
        return 'application/octet-stream';
    }
  }
}

/// Parameter extraction and validation utilities
class RequestParams {
  final Request request;
  final Map<String, String> _routeParams;
  final Map<String, String> _queryParams;

  RequestParams(this.request)
      : _routeParams =
            request.context['shelf_router/params'] as Map<String, String>? ??
                {},
        _queryParams = request.url.queryParameters;

  /// Get a parameter value with optional type conversion
  T? get<T>(String key, {T? defaultValue}) {
    String? value = _routeParams[key] ?? _queryParams[key];

    if (value == null) return defaultValue;

    if (T == String) return value as T;
    if (T == int) return int.tryParse(value) as T?;
    if (T == double) return double.tryParse(value) as T?;
    if (T == bool) {
      final lower = value.toLowerCase();
      if (lower == 'true' || lower == '1') return true as T;
      if (lower == 'false' || lower == '0') return false as T;
      return defaultValue;
    }

    return value as T?;
  }

  /// Get a required parameter (throws if missing)
  T getRequired<T>(String key) {
    final value = get<T>(key);
    if (value == null) {
      throw ArgumentError('Required parameter missing: $key');
    }
    return value;
  }

  /// Get all route parameters
  Map<String, String> get routeParams => Map.unmodifiable(_routeParams);

  /// Get all query parameters
  Map<String, String> get queryParams => Map.unmodifiable(_queryParams);

  /// Check if a parameter exists
  bool has(String key) {
    return _routeParams.containsKey(key) || _queryParams.containsKey(key);
  }
}

/// Simple request body parser utilities
class RequestBody {
  static Future<Map<String, dynamic>> parseJson(Request request) async {
    final body = await request.readAsString();
    if (body.isEmpty) return {};

    try {
      final decoded = jsonDecode(body);
      return decoded is Map<String, dynamic> ? decoded : {'data': decoded};
    } catch (e) {
      throw FormatException('Invalid JSON in request body: $e');
    }
  }

  static Future<Map<String, String>> parseForm(Request request) async {
    final body = await request.readAsString();
    if (body.isEmpty) return {};

    return Uri.splitQueryString(body);
  }

  static Future<String> parseText(Request request) async {
    return await request.readAsString();
  }
}

// Re-export commonly used functions
String jsonEncode(Object? object) => const JsonEncoder().convert(object);
dynamic jsonDecode(String source) => const JsonDecoder().convert(source);
