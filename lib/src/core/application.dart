import 'dart:io';
import 'package:d_server/src/orm/database_connection.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart';
// import 'package:shelf_cors_headers/shelf_cors_headers.dart';
import '../routing/router.dart';
import '../templates/template_engine.dart';
// import '../orm/database_connection.dart';
import '../controllers/base_controller.dart';
import 'config.dart';
import 'logger.dart';

/// Main application class for D_Server framework
///
/// Ties together all framework components including routing, database,
/// templates, middleware, and server management.
///
/// ## Usage
///
/// ```dart
/// void main() async {
///   final app = DApplication({
///     'database': {
///       'host': 'localhost',
///       'port': 5432,
///       'database': 'myapp',
///       'username': 'user',
///       'password': 'password',
///     },
///     'server': {
///       'host': 'localhost',
///       'port': 3000,
///     },
///     'auth': {
///       'jwt_secret': 'your-secret-key',
///     },
///   });
///
///   // Configure routes
///   app.router.resource('users', UsersController);
///   app.router.get('/', (req) => Response.ok('Hello World!'));
///
///   // Start the server
///   await app.start();
/// }
/// ```
class DApplication {
  final DConfig config;
  final DRouter router = DRouter();
  final ScopedLogger _logger = DLogger.scoped('APPLICATION');

  DatabaseConnection? _database;
  TemplateEngine? _templateEngine;
  HttpServer? _server;
  bool _isStarted = false;

  /// Create a new D_Server application with configuration
  DApplication([Map<String, dynamic>? configMap])
      : config = DConfig(configMap ?? {}) {
    _initializeFramework();
  }

  /// Create application from configuration file
  static Future<DApplication> fromConfigFile(String configPath) async {
    final config = await DConfig.loadFromFile(configPath);
    return DApplication()..config.merge(config);
  }

  /// Create application with environment-specific configuration
  static Future<DApplication> withEnvironment(
    String configPath, [
    String? environment,
  ]) async {
    final config = await DConfig.loadWithEnvironment(configPath, environment);
    return DApplication()..config.merge(config);
  }

  /// Get the database connection
  DatabaseConnection get database {
    if (_database == null) {
      throw StateError(
          'Database not configured. Call connectDatabase() first.');
    }
    return _database!;
  }

  /// Get the template engine
  TemplateEngine get templates {
    if (_templateEngine == null) {
      throw StateError(
          'Template engine not configured. Call setupTemplates() first.');
    }
    return _templateEngine!;
  }

  /// Check if the application is running
  bool get isStarted => _isStarted;

  /// Get server information
  Map<String, dynamic> get serverInfo {
    if (_server == null) {
      return {'status': 'not_started'};
    }

    return {
      'status': 'running',
      'host': _server!.address.address,
      'port': _server!.port,
      'environment':
          config.get<String>('server.environment', defaultValue: 'development'),
    };
  }

  /// Connect to the database
  Future<void> connectDatabase([Map<String, dynamic>? dbConfig]) async {
    try {
      final databaseConfig = dbConfig ?? config.getDatabaseConfig();
      _database = await DatabaseConnection.fromConfig(databaseConfig);

      // Set the database connection for all models
      // This would be handled by the ORM system
      _logger.success('Database connected successfully');
    } catch (e) {
      _logger.error('Failed to connect to database: $e');
      rethrow;
    }
  }

  /// Setup template engine
  void setupTemplates([String? viewsPath, String? defaultLayout]) {
    final actualViewsPath =
        viewsPath ?? config.get<String>('views.path', defaultValue: 'views');
    final actualDefaultLayout = defaultLayout ??
        config.get<String>('views.default_layout', defaultValue: 'application');

    _templateEngine = TemplateEngine(
      actualViewsPath ?? 'views',
      defaultLayout: actualDefaultLayout ?? 'application',
      cacheEnabled:
          config.get<bool>('views.cache_enabled', defaultValue: true) ?? true,
      config: config,
    );

    // Set template engine for all controllers
    DController.setTemplateEngine(_templateEngine!);

    _logger.success('Template engine configured: $actualViewsPath');
  }

  /// Add global middleware
  void use(Middleware middleware, {List<String>? only, List<String>? except}) {
    router.use(middleware, only: only, except: except);
  }

  /// Configure static files serving
  void setupStaticFiles({
    String? directory,
    String? urlPath,
    bool? enabled,
    bool listDirectories = false,
    Duration? maxAge,
  }) {
    // Check if static files are enabled (parameter overrides config)
    final isEnabled = enabled ??
        config.get<bool>('static_files.enabled', defaultValue: true) == true;

    if (!isEnabled) {
      _logger.debug('Static files disabled');
      return;
    }

    // Get configuration values (parameters override config)
    final staticDir = directory ??
        config.get<String>('static_files.directory', defaultValue: 'public') ??
        'public';
    final staticPath = urlPath ??
        config.get<String>('static_files.url_path', defaultValue: '/assets') ??
        '/assets';
    final configListDirectories = config
            .get<bool>('static_files.list_directories', defaultValue: false) ??
        false;
    final configMaxAge = Duration(
        seconds: config.get<int>('static_files.max_age_seconds',
                defaultValue: 3600) ??
            3600);

    // Validate directory exists or create it
    final dir = Directory(staticDir);
    if (!dir.existsSync()) {
      try {
        dir.createSync(recursive: true);
        _logger.info('Created static files directory: $staticDir');
      } catch (e) {
        _logger
            .error('Failed to create static files directory "$staticDir": $e');
        return;
      }
    }

    try {
      // Setup static file serving
      router.serveStatic(
        directory: staticDir,
        urlPath: staticPath,
        listDirectories: listDirectories || configListDirectories,
        maxAge: maxAge ?? configMaxAge,
      );

      _logger.info('Static files enabled: $staticPath -> $staticDir');

      // Log some example URLs in development
      if (config.get<String>('server.environment') == 'development') {
        final host =
            config.get<String>('server.host', defaultValue: 'localhost');
        final port = config.get<int>('server.port', defaultValue: 3000);
        _logger.debug('Example static URLs:');
        _logger.debug('  http://$host:$port$staticPath/css/app.css');
        _logger.debug('  http://$host:$port$staticPath/js/app.js');
        _logger.debug('  http://$host:$port$staticPath/images/logo.png');
      }
    } catch (e) {
      _logger.error('Failed to setup static files: $e');
    }
  }

  /// Configure built-in middleware
  void setupMiddleware() {
    // CORS middleware
    if (config.get<bool>('cors.enabled', defaultValue: true) == true) {
      // Simple CORS middleware implementation
      use((Handler innerHandler) {
        return (Request request) async {
          final response = await innerHandler(request);

          return response.change(headers: {
            'access-control-allow-origin':
                config.get<String>('cors.allow_origin', defaultValue: '*') ??
                    '*',
            'access-control-allow-methods': config.get<String>(
                    'cors.allow_methods',
                    defaultValue: 'GET, POST, PUT, DELETE, OPTIONS') ??
                'GET, POST, PUT, DELETE, OPTIONS',
            'access-control-allow-headers': config.get<String>(
                    'cors.allow_headers',
                    defaultValue: 'Content-Type, Authorization') ??
                'Content-Type, Authorization',
            ...response.headers,
          });
        };
      });
    }

    // Request logging middleware
    if (config.get<bool>('logging.requests', defaultValue: true) == true) {
      use(logRequests(logger: (message, isError) {
        if (isError) {
          _logger.error(message);
        } else {
          _logger.info(message);
        }
      }));
    }

    // Error handling middleware
    use(_errorHandlingMiddleware());

    _logger.debug('Built-in middleware configured');
  }

  /// Start the server
  Future<void> start() async {
    if (_isStarted) {
      _logger.warning('Server is already running');
      return;
    }

    try {
      // Initialize components
      await _initializeComponents();

      // Setup middleware
      setupMiddleware();

      // Create the handler pipeline
      final handler = router.handler;

      // Get server configuration
      final serverConfig = config.getServerConfig();
      final host = serverConfig['host'] as String;
      final port = serverConfig['port'] as int;

      // Start the HTTP server
      _server = await serve(handler, host, port);
      _isStarted = true;

      _logger.success('Server running on http://$host:$port');
      _logger.info('Environment: ${serverConfig['environment']}');

      // Print route information in development
      if (serverConfig['environment'] == 'development') {
        _printRouteInfo();
      }
    } catch (e) {
      _logger.error('Failed to start server: $e');
      rethrow;
    }
  }

  /// Stop the server
  Future<void> stop() async {
    if (!_isStarted || _server == null) {
      return;
    }

    try {
      await _server!.close();
      _isStarted = false;
      _logger.info('Server stopped');

      // Close database connection
      if (_database != null) {
        await _database!.close();
        _logger.info('Database connection closed');
      }
    } catch (e) {
      _logger.error('Error stopping server: $e');
    }
  }

  /// Restart the server
  Future<void> restart() async {
    _logger.info('Restarting server...');
    await stop();
    await start();
  }

  /// Initialize framework components
  void _initializeFramework() {
    // Configure logger
    DLogger.configure(
      enableColors: config.get<bool>('logging.colors', defaultValue: true),
      enableTimestamp:
          config.get<bool>('logging.timestamp', defaultValue: true),
      logLevel: _parseLogLevel(
          config.get<String>('logging.level', defaultValue: 'info') ?? 'info'),
    );

    _logger.debug('Framework initialized');
  }

  /// Initialize all application components
  Future<void> _initializeComponents() async {
    // Connect to database if configured
    if (config.has('database.host') || config.has('database.url')) {
      await connectDatabase();
    }

    // Setup templates
    setupTemplates();

    // Setup static files
    setupStaticFiles();

    _logger.debug('Application components initialized');
  }

  /// Create error handling middleware
  Middleware _errorHandlingMiddleware() {
    return (Handler innerHandler) {
      return (Request request) async {
        try {
          return await innerHandler(request);
        } catch (error, stackTrace) {
          _logger.error('Unhandled error: $error');
          _logger.debug('Stack trace: $stackTrace');

          // In development, return detailed error information
          final isDevelopment =
              config.get<String>('server.environment') == 'development';

          if (isDevelopment) {
            return Response.internalServerError(
              body: '''
              <!DOCTYPE html>
              <html>
              <head><title>Server Error</title></head>
              <body>
                <h1>Internal Server Error</h1>
                <h2>Error:</h2>
                <pre>$error</pre>
                <h2>Stack Trace:</h2>
                <pre>$stackTrace</pre>
              </body>
              </html>
              ''',
              headers: {'content-type': 'text/html'},
            );
          } else {
            return Response.internalServerError(
              body: '{"error": "Internal server error"}',
              headers: {'content-type': 'application/json'},
            );
          }
        }
      };
    };
  }

  /// Parse log level from string
  LogLevel _parseLogLevel(String level) {
    switch (level.toLowerCase()) {
      case 'debug':
        return LogLevel.debug;
      case 'info':
        return LogLevel.info;
      case 'warning':
      case 'warn':
        return LogLevel.warning;
      case 'error':
        return LogLevel.error;
      default:
        return LogLevel.info;
    }
  }

  /// Print route information for debugging
  void _printRouteInfo() {
    final routeInfo = router.getRouteInfo();
    _logger.debug('Route info: $routeInfo');
  }

  /// Create default configuration for new applications
  static Map<String, dynamic> defaultConfig() {
    return {
      'server': {
        'host': 'localhost',
        'port': 3000,
        'environment': 'development',
      },
      'database': {
        'host': 'localhost',
        'port': 5432,
        'database': 'myapp_development',
        'username': 'postgres',
        'password': '',
        'max_connections': 10,
      },
      'views': {
        'path': 'views',
        'default_layout': 'application',
        'cache_enabled': true,
      },
      'static_files': {
        'enabled': true,
        'directory': 'public',
        'url_path': '/assets',
        'list_directories': false,
        'max_age_seconds': 3600,
      },
      'cors': {
        'enabled': true,
        'allow_origin': '*',
        'allow_methods': 'GET, POST, PUT, DELETE, OPTIONS',
        'allow_headers': 'Content-Type, Authorization',
      },
      'logging': {
        'level': 'info',
        'colors': true,
        'timestamp': true,
        'requests': true,
      },
      'auth': {
        'jwt_secret': null,
        'session_secret': null,
        'token_expiry': 3600,
        'session_expiry': 86400,
      },
    };
  }

  /// Get application health status
  Map<String, dynamic> healthCheck() {
    return {
      'status': _isStarted ? 'healthy' : 'stopped',
      'server': serverInfo,
      'database': _database != null ? 'connected' : 'not_configured',
      'templates': _templateEngine != null ? 'configured' : 'not_configured',
      'uptime':
          _isStarted ? DateTime.now().difference(_startTime).inSeconds : 0,
    };
  }

  DateTime _startTime = DateTime.now();
}

/// Application startup helper
class DServer {
  /// Quick start a D_Server application with minimal configuration
  static Future<DApplication> start({
    String host = 'localhost',
    int port = 3000,
    String? configFile,
    void Function(DRouter)? routes,
  }) async {
    DApplication app;

    if (configFile != null) {
      app = await DApplication.fromConfigFile(configFile);
    } else {
      app = DApplication({
        'server': {'host': host, 'port': port},
        ...DApplication.defaultConfig(),
      });
    }

    // Configure routes if provided
    if (routes != null) {
      routes(app.router);
    }

    await app.start();
    return app;
  }

  /// Create a new D_Server project structure
  static Future<void> createProject(String projectName) async {
    final logger = DLogger.scoped('PROJECT_GENERATOR');

    // Create project directories
    final directories = [
      '$projectName/lib',
      '$projectName/lib/controllers',
      '$projectName/lib/models',
      '$projectName/views',
      '$projectName/views/layouts',
      '$projectName/config',
      '$projectName/db',
      '$projectName/db/migrations',
      '$projectName/public',
      '$projectName/test',
    ];

    for (final dir in directories) {
      await Directory(dir).create(recursive: true);
    }

    // Create default configuration
    final configFile = File('$projectName/config/config.yml');
    await configFile.writeAsString('''
server:
  host: localhost
  port: 3000
  environment: development

database:
  host: localhost
  port: 5432
  database: ${projectName}_development
  username: postgres
  password: ""

views:
  path: views
  default_layout: application

# Static files configuration
static_files:
  enabled: true              # Enable/disable static file serving
  directory: public          # Directory containing static assets
  url_path: /assets          # URL path prefix for static files
  list_directories: false    # Allow directory browsing
  max_age_seconds: 3600      # Cache duration in seconds (1 hour)

cors:
  enabled: true
  allow_origin: "*"

logging:
  level: info
  colors: true
  requests: true

hot_reload:
  enabled: true
  debounce_delay: 500
  watch_directories:
    - lib
    - views
  ignore_patterns:
    - "**/*.tmp"
    - "**/.*"
    - "**/.git/**"
''');

    // Create pubspec.yaml
    final pubspecFile = File('$projectName/pubspec.yaml');
    await pubspecFile.writeAsString('''
name: $projectName
description: A D_Server web application
version: 1.0.0
publish_to: "none"

environment:
  sdk: ^3.0.0

dependencies:
  d_server: ^0.1.0

dev_dependencies:
  lints: ^3.0.0
  test: ^1.24.0
''');

    // Create README.md
    final readmeFile = File('$projectName/README.md');
    await readmeFile.writeAsString('''
# $projectName

A web application built with D_Server framework.

## Getting Started

1. Install dependencies:
   ```bash
   dart pub get
   ```

2. Set up your database:
   ```bash
   d_server db:create
   d_server db:migrate
   ```

3. Start the server:
   ```bash
   dart run lib/main.dart
   ```

The application will be available at http://localhost:3000

## Development Commands

Make sure you have the D_Server CLI installed globally:
```bash
dart pub global activate d_server
```

Then use these commands in your project directory:
- `d_server generate controller <name>` - Generate a controller
- `d_server generate model <name>` - Generate a model
- `d_server generate migration <name>` - Generate a migration
- `d_server db:migrate` - Run migrations
- `d_server db:rollback` - Rollback migrations
- `d_server server` - Start development server (alternative to dart run)

## Project Structure

- `lib/` - Application code
  - `lib/main.dart` - Application entry point
  - `lib/controllers/` - Controllers
  - `lib/models/` - Models
- `views/` - Templates
- `config/` - Configuration files
- `db/migrations/` - Database migrations
- `public/` - Static assets
''');

    // Create .gitignore
    final gitignoreFile = File('$projectName/.gitignore');
    await gitignoreFile.writeAsString('''
# Created by https://www.gitignore.io/api/dart

### Dart ###
# See https://www.dartlang.org/guides/libraries/private-files

# Files and directories created by pub
.dart_tool/
.packages
build/
pubspec.lock  # Remove this pattern if you wish to check in your lock file

# Conventional directory for build outputs
build/

# Directory created by dartdoc
doc/api/

# JetBrains IDEs
.idea/
*.iml
*.ipr
*.iws

# VS Code
.vscode/

# OS Files
.DS_Store
Thumbs.db

# Log files
*.log

# Environment files
.env
.env.local
.env.production

# Database files
*.db
*.sqlite

# Temporary files
tmp/
temp/
''');

    // Create analysis_options.yaml
    final analysisFile = File('$projectName/analysis_options.yaml');
    await analysisFile.writeAsString('''
include: package:lints/recommended.yaml

analyzer:
  exclude:
    - build/**
  strong-mode:
    implicit-casts: false
    implicit-dynamic: false

linter:
  rules:
    # Dart Style
    - camel_case_types
    - library_names
    - file_names
    - library_prefixes
    - non_constant_identifier_names
    - constant_identifier_names

    # Documentation
    - public_member_api_docs
    - comment_references

    # Usage
    - implementation_imports
    - prefer_relative_imports
    - avoid_relative_lib_imports

    # Design
    - use_key_in_widget_constructors
    - prefer_const_constructors
    - prefer_const_literals_to_create_immutables
    - avoid_unnecessary_containers
''');

    // Create default templates
    await TemplateEngine.createDefaultTemplates('$projectName/views');

    // Create main application file
    final mainFile = File('$projectName/lib/main.dart');
    await mainFile.writeAsString('''
import 'package:d_server/d_server.dart';

void main() async {
  final app = await DApplication.fromConfigFile('config/config.yml');

  // Define routes
  app.router.get('/', (request) {
    return ResponseHelpers.html(app.templates.renderWithDefaultLayout('welcome'));
  });

  // Start the server
  await app.start();
}
''');

    // Create sample static files
    final cssDir = Directory('$projectName/public/css');
    await cssDir.create(recursive: true);

    final cssFile = File('$projectName/public/css/app.css');
    await cssFile.writeAsString('''
/* D_Server App Styles */
body {
  font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
  margin: 0;
  padding: 20px;
  line-height: 1.6;
  color: #333;
  background-color: #f5f5f5;
}

.container {
  max-width: 800px;
  margin: 0 auto;
  background: white;
  padding: 30px;
  border-radius: 8px;
  box-shadow: 0 2px 10px rgba(0, 0, 0, 0.1);
}

h1 {
  color: #2c3e50;
  border-bottom: 2px solid #3498db;
  padding-bottom: 10px;
}

.btn {
  display: inline-block;
  padding: 10px 20px;
  background: #3498db;
  color: white;
  text-decoration: none;
  border-radius: 4px;
  transition: background 0.3s;
}

.btn:hover {
  background: #2980b9;
}
''');

    final jsDir = Directory('$projectName/public/js');
    await jsDir.create(recursive: true);

    final jsFile = File('$projectName/public/js/app.js');
    await jsFile.writeAsString('''
// D_Server App JavaScript
document.addEventListener('DOMContentLoaded', function() {
  console.log('D_Server app loaded successfully!');

  // Add simple interactivity
  const buttons = document.querySelectorAll('.btn');
  buttons.forEach(button => {
    button.addEventListener('click', function(e) {
      console.log('Button clicked:', this.textContent);
    });
  });
});
''');

    // Create favicon
    final faviconFile = File('$projectName/public/favicon.ico');
    // Create a simple text placeholder for favicon
    await faviconFile.writeAsString('D_Server');

    logger.success('Created D_Server project: $projectName');
    logger.info('Next steps:');
    logger.info('  cd $projectName');
    logger.info('  dart pub get');
    logger.info(
        '  d_server dev                 # Start development server with hot reload');
    logger.info('  dart run lib/main.dart       # Start production server');
    logger.info('');
    logger.info('Development commands (use global d_server CLI):');
    logger.info('  d_server generate controller <name>');
    logger.info('  d_server generate model <name>');
    logger.info('  d_server db:migrate');
    logger.info('  d_server db:rollback');
  }
}
