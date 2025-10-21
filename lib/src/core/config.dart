import 'dart:io';
import 'package:yaml/yaml.dart';

/// Configuration management system for D_Server framework
///
/// Provides centralized configuration loading from YAML files and environment variables.
/// Supports nested configuration access and type conversion.
///
/// ## Usage
///
/// ```dart
/// // Load config from file
/// final config = await DConfig.loadFromFile('config/config.yml');
///
/// // Get configuration values
/// final host = config.get<String>('database.host');
/// final port = config.get<int>('database.port', defaultValue: 5432);
///
/// // Set configuration values
/// config.set('app.name', 'My App');
///
/// // Check if key exists
/// if (config.has('redis.url')) {
///   // Use Redis
/// }
/// ```
class DConfig {
  final Map<String, dynamic> _config = {};
  final Map<String, String> _envOverrides = {};

  DConfig([Map<String, dynamic>? initialConfig]) {
    if (initialConfig != null) {
      _config.addAll(initialConfig);
    }
    _loadEnvironmentOverrides();
  }

  /// Load configuration from a YAML file
  static Future<DConfig> loadFromFile(String filePath) async {
    final file = File(filePath);
    if (!file.existsSync()) {
      throw ConfigException('Configuration file not found: $filePath');
    }

    final content = await file.readAsString();
    final yamlDoc = loadYaml(content);

    if (yamlDoc is! Map) {
      throw ConfigException('Invalid YAML format in: $filePath');
    }

    return DConfig(_flattenYamlMap(yamlDoc));
  }

  /// Load configuration from multiple files with environment-specific overrides
  static Future<DConfig> loadWithEnvironment(
    String basePath, [
    String? environment,
  ]) async {
    environment ??= Platform.environment['DART_ENV'] ?? 'development';

    // Load base configuration
    final baseConfig = await loadFromFile('$basePath/config.yml');

    // Load environment-specific config if it exists
    final envConfigPath = '$basePath/$environment.yml';
    final envFile = File(envConfigPath);

    if (envFile.existsSync()) {
      final envConfig = await loadFromFile(envConfigPath);
      baseConfig.merge(envConfig);
    }

    return baseConfig;
  }

  /// Get a configuration value by key path (e.g., 'database.host')
  T? get<T>(String keyPath, {T? defaultValue}) {
    final value = _getValue(keyPath);

    if (value == null) {
      return defaultValue;
    }

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
        if (lower == 'true' || lower == '1' || lower == 'yes') return true as T;
        if (lower == 'false' || lower == '0' || lower == 'no') {
          return false as T;
        }
      }
      return defaultValue;
    } else if (T == List) {
      if (value is List) return value as T;
      return defaultValue;
    } else if (T == Map) {
      if (value is Map) return value as T;
      return defaultValue;
    }

    return value as T?;
  }

  /// Set a configuration value by key path
  void set<T>(String keyPath, T value) {
    final keys = keyPath.split('.');
    Map<String, dynamic> current = _config;

    for (int i = 0; i < keys.length - 1; i++) {
      final key = keys[i];
      if (!current.containsKey(key) || current[key] is! Map) {
        current[key] = <String, dynamic>{};
      }
      current = current[key] as Map<String, dynamic>;
    }

    current[keys.last] = value;
  }

  /// Check if a configuration key exists
  bool has(String keyPath) {
    return _getValue(keyPath) != null;
  }

  /// Get all configuration as a flat map
  Map<String, dynamic> toMap() {
    return Map<String, dynamic>.from(_config);
  }

  /// Merge another config into this one
  void merge(DConfig other) {
    _deepMerge(_config, other._config);
  }

  /// Get database configuration as a structured map
  Map<String, dynamic> getDatabaseConfig([String? name]) {
    final key = name != null ? 'database.$name' : 'database';
    final dbConfig = {
      'ssl': get<bool>('$key.ssl', defaultValue: false),
      'host': get<String>('$key.host', defaultValue: 'localhost'),
      'port': get<int>('$key.port', defaultValue: 5432),
      'database': get<String>('$key.database', defaultValue: 'd_server_db'),
      'username': get<String>('$key.username', defaultValue: 'user'),
      'password': get<String>('$key.password', defaultValue: 'password'),
    };

    // if (dbConfig == null) {
    // throw ConfigException('Database configuration not found: $key');
    // }

    return Map<String, dynamic>.from(dbConfig);
  }

  /// Get server configuration
  Map<String, dynamic> getServerConfig() {
    return {
      'host': get<String>('server.host', defaultValue: 'localhost'),
      'port': get<int>('server.port', defaultValue: 3000),
      'environment': get<String>(
        'server.environment',
        defaultValue: 'development',
      ),
    };
  }

  /// Get authentication configuration
  Map<String, dynamic> getAuthConfig() {
    return {
      'jwt_secret': get<String>('auth.jwt_secret') ?? _generateSecret(),
      'session_secret': get<String>('auth.session_secret') ?? _generateSecret(),
      'token_expiry': get<int>('auth.token_expiry', defaultValue: 3600),
      'session_expiry': get<int>('auth.session_expiry', defaultValue: 86400),
    };
  }

  dynamic _getValue(String keyPath) {
    // First check environment overrides
    final envKey = keyPath.toUpperCase().replaceAll('.', '_');
    if (_envOverrides.containsKey(envKey)) {
      return _envOverrides[envKey];
    }

    // Then check config map directly for flattened key
    if (_config.containsKey(keyPath)) {
      return _config[keyPath];
    }

    return null;
  }

  void _loadEnvironmentOverrides() {
    Platform.environment.forEach((key, value) {
      if (key.startsWith('DSERVER_')) {
        final configKey = key.substring(8); // Remove DSERVER_ prefix
        _envOverrides[configKey] = value;
      }
    });
  }

  String _generateSecret() {
    // Generate a random secret if none provided
    final random = DateTime.now().millisecondsSinceEpoch.toString();
    return 'generated_secret_$random';
  }

  static Map<String, dynamic> _flattenYamlMap(Map yamlMap) {
    final result = <String, dynamic>{};

    void flatten(Map map, String prefix) {
      map.forEach((key, value) {
        final newKey = prefix.isEmpty ? key.toString() : '$prefix.$key';

        if (value is Map) {
          flatten(value, newKey);
        } else {
          result[newKey] = value;
        }
      });
    }

    flatten(yamlMap, '');
    return result;
  }

  static void _deepMerge(
    Map<String, dynamic> target,
    Map<String, dynamic> source,
  ) {
    source.forEach((key, value) {
      if (target.containsKey(key) && target[key] is Map && value is Map) {
        _deepMerge(
          target[key] as Map<String, dynamic>,
          value as Map<String, dynamic>,
        );
      } else {
        target[key] = value;
      }
    });
  }
}

/// Exception thrown when configuration operations fail
class ConfigException implements Exception {
  final String message;

  ConfigException(this.message);

  @override
  String toString() => 'ConfigException: $message';
}
