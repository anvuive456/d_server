import 'dart:convert';
import 'dart:io';
import 'package:shelf/shelf.dart';

/// Response helper utilities for D_Server controllers
///
/// Provides convenient methods for creating common HTTP responses
/// with proper headers and status codes.
class ResponseHelpers {
  /// Create a JSON response with proper content type
  static Response json(
    Object data, {
    int status = 200,
    Map<String, String>? headers,
  }) {
    final jsonData = const JsonEncoder().convert(data);
    final responseHeaders = <String, String>{
      'content-type': 'application/json; charset=utf-8',
      'cache-control': 'no-cache',
      ...?headers,
    };

    return Response(status, body: jsonData, headers: responseHeaders);
  }

  /// Create a successful JSON response (200 OK)
  static Response ok(Object data, {Map<String, String>? headers}) {
    return json(data, status: 200, headers: headers);
  }

  /// Create a created JSON response (201 Created)
  static Response created(Object data, {Map<String, String>? headers}) {
    return json(data, status: 201, headers: headers);
  }

  /// Create a no content response (204 No Content)
  static Response noContent({Map<String, String>? headers}) {
    return Response(204, headers: headers);
  }

  /// Create a bad request response (400 Bad Request)
  static Response badRequest(
    String message, {
    Object? details,
    Map<String, String>? headers,
  }) {
    final data = <String, dynamic>{
      'error': 'Bad Request',
      'message': message,
    };

    if (details != null) {
      data['details'] = details;
    }

    return json(data, status: 400, headers: headers);
  }

  /// Create an unauthorized response (401 Unauthorized)
  static Response unauthorized(
    String message, {
    Map<String, String>? headers,
  }) {
    return json({
      'error': 'Unauthorized',
      'message': message,
    }, status: 401, headers: headers);
  }

  /// Create a forbidden response (403 Forbidden)
  static Response forbidden(
    String message, {
    Map<String, String>? headers,
  }) {
    return json({
      'error': 'Forbidden',
      'message': message,
    }, status: 403, headers: headers);
  }

  /// Create a not found response (404 Not Found)
  static Response notFound(
    String message, {
    Map<String, String>? headers,
  }) {
    return json({
      'error': 'Not Found',
      'message': message,
    }, status: 404, headers: headers);
  }

  /// Create a method not allowed response (405 Method Not Allowed)
  static Response methodNotAllowed(
    String message, {
    List<String>? allowedMethods,
    Map<String, String>? headers,
  }) {
    final responseHeaders = <String, String>{
      ...?headers,
    };

    if (allowedMethods != null && allowedMethods.isNotEmpty) {
      responseHeaders['allow'] = allowedMethods.join(', ');
    }

    return json({
      'error': 'Method Not Allowed',
      'message': message,
      if (allowedMethods != null) 'allowed_methods': allowedMethods,
    }, status: 405, headers: responseHeaders);
  }

  /// Create a conflict response (409 Conflict)
  static Response conflict(
    String message, {
    Object? details,
    Map<String, String>? headers,
  }) {
    final data = <String, dynamic>{
      'error': 'Conflict',
      'message': message,
    };

    if (details != null) {
      data['details'] = details;
    }

    return json(data, status: 409, headers: headers);
  }

  /// Create an unprocessable entity response (422 Unprocessable Entity)
  static Response unprocessableEntity(
    String message,
    Map<String, dynamic> errors, {
    Map<String, String>? headers,
  }) {
    return json({
      'error': 'Unprocessable Entity',
      'message': message,
      'errors': errors,
    }, status: 422, headers: headers);
  }

  /// Create a too many requests response (429 Too Many Requests)
  static Response tooManyRequests(
    String message, {
    int? retryAfter,
    Map<String, String>? headers,
  }) {
    final responseHeaders = <String, String>{
      ...?headers,
    };

    if (retryAfter != null) {
      responseHeaders['retry-after'] = retryAfter.toString();
    }

    return json({
      'error': 'Too Many Requests',
      'message': message,
      if (retryAfter != null) 'retry_after': retryAfter,
    }, status: 429, headers: responseHeaders);
  }

  /// Create an internal server error response (500 Internal Server Error)
  static Response internalServerError(
    String message, {
    Object? details,
    Map<String, String>? headers,
  }) {
    final data = <String, dynamic>{
      'error': 'Internal Server Error',
      'message': message,
    };

    if (details != null) {
      data['details'] = details;
    }

    return json(data, status: 500, headers: headers);
  }

  /// Create a service unavailable response (503 Service Unavailable)
  static Response serviceUnavailable(
    String message, {
    int? retryAfter,
    Map<String, String>? headers,
  }) {
    final responseHeaders = <String, String>{
      ...?headers,
    };

    if (retryAfter != null) {
      responseHeaders['retry-after'] = retryAfter.toString();
    }

    return json({
      'error': 'Service Unavailable',
      'message': message,
      if (retryAfter != null) 'retry_after': retryAfter,
    }, status: 503, headers: responseHeaders);
  }

  /// Create a plain text response
  static Response text(
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

  /// Create an HTML response
  static Response html(
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

  /// Create a redirect response
  static Response redirect(
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

  /// Create a permanent redirect response (301 Moved Permanently)
  static Response redirectPermanent(
    String location, {
    Map<String, String>? headers,
  }) {
    return redirect(location, status: 301, headers: headers);
  }

  /// Create a file download response
  static Response download(
    File file, {
    String? filename,
    String? contentType,
    bool inline = false,
    Map<String, String>? headers,
  }) {
    final actualFilename = filename ?? file.uri.pathSegments.last;
    final actualContentType = contentType ?? _guessContentType(actualFilename);
    final disposition = inline ? 'inline' : 'attachment';

    final responseHeaders = <String, String>{
      'content-type': actualContentType,
      'content-disposition': '$disposition; filename="$actualFilename"',
      'content-length': file.lengthSync().toString(),
      ...?headers,
    };

    return Response.ok(
      file.openRead(),
      headers: responseHeaders,
    );
  }

  /// Create a streaming response
  static Response stream(
    Stream<List<int>> stream, {
    String? contentType,
    int? contentLength,
    Map<String, String>? headers,
  }) {
    final responseHeaders = <String, String>{
      if (contentType != null) 'content-type': contentType,
      if (contentLength != null) 'content-length': contentLength.toString(),
      ...?headers,
    };

    return Response.ok(stream, headers: responseHeaders);
  }

  /// Create a server-sent events response
  static Response serverSentEvents(
    Stream<String> events, {
    Map<String, String>? headers,
  }) {
    final responseHeaders = <String, String>{
      'content-type': 'text/event-stream',
      'cache-control': 'no-cache',
      'connection': 'keep-alive',
      ...?headers,
    };

    final eventStream =
        events.map((event) => 'data: $event\n\n').transform(utf8.encoder);

    return Response.ok(eventStream, headers: responseHeaders);
  }

  /// Create a paginated JSON response
  static Response paginated(
    List<Object> data, {
    required int page,
    required int perPage,
    required int total,
    Map<String, dynamic>? meta,
    Map<String, String>? headers,
  }) {
    final totalPages = (total / perPage).ceil();
    final hasNext = page < totalPages;
    final hasPrev = page > 1;

    final response = <String, dynamic>{
      'data': data,
      'pagination': {
        'current_page': page,
        'per_page': perPage,
        'total_items': total,
        'total_pages': totalPages,
        'has_next': hasNext,
        'has_previous': hasPrev,
        if (hasNext) 'next_page': page + 1,
        if (hasPrev) 'previous_page': page - 1,
      },
      if (meta != null) 'meta': meta,
    };

    return json(response, headers: headers);
  }

  /// Create a validation error response with field-specific errors
  static Response validationError(
    Map<String, List<String>> fieldErrors, {
    String message = 'Validation failed',
    Map<String, String>? headers,
  }) {
    return json({
      'error': 'Validation Error',
      'message': message,
      'errors': fieldErrors,
    }, status: 422, headers: headers);
  }

  /// Helper to guess content type from file extension
  static String _guessContentType(String filename) {
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
      case 'svg':
        return 'image/svg+xml';
      case 'ico':
        return 'image/x-icon';
      case 'css':
        return 'text/css';
      case 'js':
        return 'application/javascript';
      case 'html':
      case 'htm':
        return 'text/html';
      case 'mp4':
        return 'video/mp4';
      case 'mp3':
        return 'audio/mpeg';
      case 'wav':
        return 'audio/wav';
      case 'webp':
        return 'image/webp';
      case 'woff':
        return 'font/woff';
      case 'woff2':
        return 'font/woff2';
      case 'ttf':
        return 'font/ttf';
      case 'eot':
        return 'application/vnd.ms-fontobject';
      default:
        return 'application/octet-stream';
    }
  }
}

/// Status code constants for better readability
class HttpStatus {
  // Success
  static const int ok = 200;
  static const int created = 201;
  static const int accepted = 202;
  static const int noContent = 204;

  // Redirection
  static const int movedPermanently = 301;
  static const int found = 302;
  static const int notModified = 304;

  // Client Error
  static const int badRequest = 400;
  static const int unauthorized = 401;
  static const int forbidden = 403;
  static const int notFound = 404;
  static const int methodNotAllowed = 405;
  static const int conflict = 409;
  static const int unprocessableEntity = 422;
  static const int tooManyRequests = 429;

  // Server Error
  static const int internalServerError = 500;
  static const int notImplemented = 501;
  static const int serviceUnavailable = 503;
}
