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

  /// Create a static file handler with advanced options
  static Handler staticFiles(
    String directory, {
    bool listDirectories = false,
    Duration? maxAge,
  }) {
    return (Request request) async {
      // Get path from route parameters, not from request.url.path
      final params = RequestParams(request);
      final path = params.get<String>('path') ?? '';

      final fullPath = path.isEmpty ? directory : '$directory/$path';
      final file = File(fullPath);
      final dir = Directory(fullPath);

      // Check if it's a directory
      if (dir.existsSync() && listDirectories) {
        return _serveDirectoryListing(dir, path);
      }

      // Check if file exists
      if (!file.existsSync()) {
        return Response.notFound('File not found');
      }

      // Determine content type
      final contentType = _getContentType(path);

      // Build cache control header
      final maxAgeSeconds = maxAge?.inSeconds ?? 3600;
      final cacheControl = 'public, max-age=$maxAgeSeconds';

      return Response.ok(
        file.openRead(),
        headers: {
          'content-type': contentType,
          'cache-control': cacheControl,
          'last-modified': file.lastModifiedSync().toUtc().toIso8601String(),
        },
      );
    };
  }

  /// Serve directory listing (enhanced HTML with better UI)
  static Response _serveDirectoryListing(Directory dir, String path) {
    try {
      _logger.debug('Serving directory listing for: ${dir.path} (path: $path)');

      final entries = dir.listSync()
        ..sort((a, b) {
          // Directories first, then files, both alphabetically
          if (a is Directory && b is File) return -1;
          if (a is File && b is Directory) return 1;
          return a.path.toLowerCase().compareTo(b.path.toLowerCase());
        });

      final displayPath = path.isEmpty ? '/' : path;

      final html = StringBuffer()
        ..writeln('<!DOCTYPE html>')
        ..writeln('<html lang="en">')
        ..writeln('<head>')
        ..writeln('  <meta charset="UTF-8">')
        ..writeln(
            '  <meta name="viewport" content="width=device-width, initial-scale=1.0">')
        ..writeln('  <title>Directory: $displayPath</title>')
        ..writeln('  <style>')
        ..writeln(
            '    body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", system-ui, sans-serif; margin: 0; padding: 20px; background: #f5f5f5; }')
        ..writeln(
            '    .container { max-width: 800px; margin: 0 auto; background: white; border-radius: 8px; box-shadow: 0 2px 10px rgba(0,0,0,0.1); padding: 30px; }')
        ..writeln(
            '    h1 { color: #333; border-bottom: 2px solid #007acc; padding-bottom: 10px; }')
        ..writeln('    .file-list { list-style: none; padding: 0; }')
        ..writeln(
            '    .file-item { padding: 12px; border-bottom: 1px solid #eee; transition: background 0.2s; }')
        ..writeln('    .file-item:hover { background: #f8f9fa; }')
        ..writeln(
            '    .file-item a { text-decoration: none; color: #333; display: flex; align-items: center; }')
        ..writeln('    .file-item a:hover { color: #007acc; }')
        ..writeln('    .icon { margin-right: 10px; font-size: 18px; }')
        ..writeln('    .directory { color: #007acc; }')
        ..writeln('    .file { color: #666; }')
        ..writeln('    .parent { font-weight: bold; color: #007acc; }')
        ..writeln('  </style>')
        ..writeln('</head>')
        ..writeln('<body>')
        ..writeln('  <div class="container">')
        ..writeln('    <h1>📁 Directory: $displayPath</h1>')
        ..writeln('    <ul class="file-list">');

      // Add parent directory link if not at root
      if (path.isNotEmpty && path != '/') {
        html
          ..writeln('      <li class="file-item">')
          ..writeln('        <a href="../" class="parent">')
          ..writeln('          <span class="icon">⬆️</span>')
          ..writeln('          <span>.. (Parent Directory)</span>')
          ..writeln('        </a>')
          ..writeln('      </li>');
      }

      // Add entries
      for (final entry in entries) {
        final name = entry.path.split('/').last;
        final isDir = entry is Directory;
        final icon = isDir ? '📁' : '📄';
        final cssClass = isDir ? 'directory' : 'file';
        final href = isDir ? '$name/' : name;

        html
          ..writeln('      <li class="file-item">')
          ..writeln('        <a href="$href" class="$cssClass">')
          ..writeln('          <span class="icon">$icon</span>')
          ..writeln('          <span>$name${isDir ? '/' : ''}</span>')
          ..writeln('        </a>')
          ..writeln('      </li>');
      }

      html
        ..writeln('    </ul>')
        ..writeln('  </div>')
        ..writeln('</body>')
        ..writeln('</html>');

      _logger.debug(
          'Directory listing generated successfully with ${entries.length} entries');

      return Response.ok(
        html.toString(),
        headers: {'content-type': 'text/html; charset=utf-8'},
      );
    } catch (e) {
      _logger.error('Error serving directory listing: $e');
      return Response.internalServerError(
        body: 'Error loading directory listing: $e',
      );
    }
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
