import 'dart:io';

/// A colorized logging system for D_Server framework
///
/// Provides different log levels with colored output and timestamp formatting.
/// Supports info, warning, error, debug, and success log levels.
///
/// ## Usage
///
/// ```dart
/// DLogger.info('Server started on port 3000');
/// DLogger.error('Database connection failed');
/// DLogger.warning('Deprecated API endpoint used');
/// DLogger.debug('Processing request: /api/users');
/// DLogger.success('Migration completed successfully');
/// ```
class DLogger {
  // ANSI color codes
  static const String _reset = '\x1B[0m';
  static const String _red = '\x1B[31m';
  static const String _green = '\x1B[32m';
  static const String _yellow = '\x1B[33m';
  static const String _blue = '\x1B[34m';
  static const String _magenta = '\x1B[35m';
  static const String _cyan = '\x1B[36m';
  static const String _white = '\x1B[37m';

  // Bright colors
  static const String _brightRed = '\x1B[91m';
  static const String _brightGreen = '\x1B[92m';
  static const String _brightYellow = '\x1B[93m';
  static const String _brightBlue = '\x1B[94m';

  // Background colors
  static const String _bgRed = '\x1B[41m';
  static const String _bgGreen = '\x1B[42m';

  static bool _enableColors = true;
  static bool _enableTimestamp = true;
  static LogLevel _logLevel = LogLevel.info;

  /// Configure logger settings
  static void configure({
    bool? enableColors,
    bool? enableTimestamp,
    LogLevel? logLevel,
  }) {
    if (enableColors != null) _enableColors = enableColors;
    if (enableTimestamp != null) _enableTimestamp = enableTimestamp;
    if (logLevel != null) _logLevel = logLevel;
  }

  /// Log an info message
  static void info(String message, [String? tag]) {
    if (_logLevel.index <= LogLevel.info.index) {
      _log('INFO', message, _brightBlue, tag);
    }
  }

  /// Log a warning message
  static void warning(String message, [String? tag]) {
    if (_logLevel.index <= LogLevel.warning.index) {
      _log('WARN', message, _brightYellow, tag);
    }
  }

  /// Log an error message
  static void error(String message, [String? tag]) {
    if (_logLevel.index <= LogLevel.error.index) {
      _log('ERROR', message, _brightRed, tag);
    }
  }

  /// Log a debug message
  static void debug(String message, [String? tag]) {
    if (_logLevel.index <= LogLevel.debug.index) {
      _log('DEBUG', message, _magenta, tag);
    }
  }

  /// Log a success message
  static void success(String message, [String? tag]) {
    if (_logLevel.index <= LogLevel.info.index) {
      _log('SUCCESS', message, _brightGreen, tag);
    }
  }

  /// Log a critical error message with background color
  static void critical(String message, [String? tag]) {
    if (_logLevel.index <= LogLevel.error.index) {
      _log('CRITICAL', message, '$_bgRed$_white', tag);
    }
  }

  /// Log HTTP request information
  static void request(
    String method,
    String path,
    int statusCode, [
    int? duration,
  ]) {
    final color = _getStatusColor(statusCode);
    final durationStr = duration != null ? ' (${duration}ms)' : '';
    final message = '$method $path - $statusCode$durationStr';
    _log('HTTP', message, color, null);
  }

  /// Log database query information
  // static void query(String sql, [int? duration]) {
  //   final durationStr = duration != null ? ' (${duration}ms)' : '';
  //   _log('SQL', '$sql$durationStr', _cyan, null);
  // }

  /// Log framework events
  static void framework(String event, String message) {
    _log('FRAMEWORK', '$event: $message', _blue, null);
  }

  static void _log(String level, String message, String color, String? tag) {
    final timestamp = _enableTimestamp
        ? DateTime.now().toIso8601String().substring(0, 19).replaceAll('T', ' ')
        : '';

    final tagStr = tag != null ? '[$tag] ' : '';
    final timestampStr = timestamp.isNotEmpty ? '[$timestamp] ' : '';

    final levelStr = _enableColors ? '$color[$level]$_reset' : '[$level]';

    final messageStr =
        _enableColors && color != _reset ? '$color$message$_reset' : message;

    // Use different output streams for different log levels
    if (level == 'ERROR' || level == 'CRITICAL') {
      stderr.writeln('$timestampStr$levelStr $tagStr$messageStr');
    } else {
      stdout.writeln('$timestampStr$levelStr $tagStr$messageStr');
    }
  }

  static String _getStatusColor(int statusCode) {
    if (statusCode >= 200 && statusCode < 300) {
      return _brightGreen;
    } else if (statusCode >= 300 && statusCode < 400) {
      return _brightYellow;
    } else if (statusCode >= 400 && statusCode < 500) {
      return _brightRed;
    } else if (statusCode >= 500) {
      return _bgRed + _white;
    }
    return _white;
  }

  /// Create a scoped logger with a specific tag
  static ScopedLogger scoped(String tag) {
    return ScopedLogger(tag);
  }
}

/// Log levels in order of severity
enum LogLevel { debug, info, warning, error }

/// A scoped logger that automatically includes a tag with all log messages
class ScopedLogger {
  final String tag;

  ScopedLogger(this.tag);

  void info(String message) => DLogger.info(message, tag);
  void warning(String message) => DLogger.warning(message, tag);
  void error(String message) => DLogger.error(message, tag);
  void debug(String message) => DLogger.debug(message, tag);
  void success(String message) => DLogger.success(message, tag);
  void critical(String message) => DLogger.critical(message, tag);
}
