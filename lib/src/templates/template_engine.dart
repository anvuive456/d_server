import 'dart:io';
import 'package:mustache_template/mustache_template.dart';
import '../core/logger.dart';

/// Template engine for D_Server framework using Mustache templates
///
/// Provides template rendering with layout support, caching, and helper functions.
///
/// ## Usage
///
/// ```dart
/// final engine = TemplateEngine('views');
///
/// // Render a template
/// final html = engine.render('users/index', {
///   'users': [
///     {'name': 'John', 'email': 'john@example.com'},
///     {'name': 'Jane', 'email': 'jane@example.com'},
///   ]
/// });
///
/// // Render with layout
/// final html = engine.renderWithLayout('users/show', 'application', {
///   'user': {'name': 'John', 'email': 'john@example.com'},
///   'title': 'User Profile'
/// });
/// ```
class TemplateEngine {
  final String _viewsPath;
  final Map<String, Template> _templateCache = {};
  final ScopedLogger _logger = DLogger.scoped('TEMPLATES');

  bool _cacheEnabled = true;
  String _defaultLayout = 'application';
  String _templateExtension = '.mustache';

  TemplateEngine(
    this._viewsPath, {
    bool cacheEnabled = true,
    String defaultLayout = 'application',
    String templateExtension = '.mustache',
  })  : _cacheEnabled = cacheEnabled,
        _defaultLayout = defaultLayout,
        _templateExtension = templateExtension {
    _ensureViewsDirectory();
  }

  /// Render a template without layout
  String render(String templateName, [Map<String, dynamic>? context]) {
    final template = _loadTemplate(templateName);
    final renderContext = _buildContext(context);

    try {
      final stopwatch = Stopwatch()..start();
      final result = template.renderString(renderContext);
      stopwatch.stop();

      _logger.debug(
          'Rendered $templateName in ${stopwatch.elapsedMilliseconds}ms');
      return result;
    } catch (e) {
      _logger.error('Failed to render template $templateName: $e');
      throw TemplateException('Template rendering failed: $e');
    }
  }

  /// Render a template with layout
  String renderWithLayout(
    String templateName,
    String layoutName,
    Map<String, dynamic> context,
  ) {
    // First render the main template
    final content = render(templateName, context);

    // Then render the layout with the content
    final layoutContext = Map<String, dynamic>.from(context);
    layoutContext['content'] = content;
    layoutContext['yield'] = content; // alias

    return render('layouts/$layoutName', layoutContext);
  }

  /// Render a template with the default layout
  String renderWithDefaultLayout(
    String templateName,
    Map<String, dynamic> context,
  ) {
    return renderWithLayout(templateName, _defaultLayout, context);
  }

  /// Check if a template exists
  bool templateExists(String templateName) {
    final templatePath = _getTemplatePath(templateName);
    return File(templatePath).existsSync();
  }

  /// Clear the template cache
  void clearCache() {
    _templateCache.clear();
    _logger.info('Template cache cleared');
  }

  /// Get template cache statistics
  Map<String, dynamic> getCacheStats() {
    return {
      'cached_templates': _templateCache.length,
      'cache_enabled': _cacheEnabled,
    };
  }

  /// Register a partial template
  void registerPartial(String name, String templateContent) {
    final template = Template(
      templateContent,
      lenient: true,
    );
    _templateCache['_partial_$name'] = template;
    _logger.debug('Registered partial: $name');
  }

  /// Load and compile a template
  Template _loadTemplate(String templateName) {
    final cacheKey = templateName;

    // Return cached template if available
    if (_cacheEnabled && _templateCache.containsKey(cacheKey)) {
      return _templateCache[cacheKey]!;
    }

    final templatePath = _getTemplatePath(templateName);
    final templateFile = File(templatePath);

    if (!templateFile.existsSync()) {
      throw TemplateException('Template not found: $templatePath');
    }

    try {
      final templateContent = templateFile.readAsStringSync();
      final template = Template(
        templateContent,
        partialResolver: _partialResolver,
        htmlEscapeValues: true,
        lenient: true,
      );

      // Cache the compiled template
      if (_cacheEnabled) {
        _templateCache[cacheKey] = template;
      }

      _logger.debug('Loaded template: $templateName');
      return template;
    } catch (e) {
      throw TemplateException('Failed to load template $templateName: $e');
    }
  }

  /// Build rendering context with helper functions
  Map<String, dynamic> _buildContext(Map<String, dynamic>? userContext) {
    final context = <String, dynamic>{
      // Helper functions
      'current_time': () => DateTime.now().toIso8601String(),
      'format_date': (String dateStr) => _formatDate(dateStr),
      'uppercase': (String text) => text.toUpperCase(),
      'lowercase': (String text) => text.toLowerCase(),
      'truncate': (String text, [int length = 50]) => _truncate(text, length),

      // helpers
      'link_to': (LambdaContext ctx) =>
          '<a href="${ctx.renderString()}">${ctx.renderString()}</a>',
      'image_tag': (String src, [String alt = '']) =>
          '<img src="$src" alt="$alt" />',

      // Conditional helpers
      'if_present': (dynamic value) => value != null && value != '',
      'if_empty': (dynamic value) => value == null || value == '',

      ...?userContext,
    };

    return context;
  }

  /// Resolve partial templates
  Template? _partialResolver(String name) {
    // Check if it's a registered partial
    final partialKey = '_partial_$name';
    if (_templateCache.containsKey(partialKey)) {
      return _templateCache[partialKey];
    }

    // Try to load partial from file system
    final partialPath =
        _getTemplatePath(name); // Partials start with underscore
    final partialFile = File(partialPath);
    if (partialFile.existsSync()) {
      try {
        final content = partialFile.readAsStringSync();
        final template = Template(
          content,
          htmlEscapeValues: true,
          lenient: true,
        );

        if (_cacheEnabled) {
          _templateCache[partialKey] = template;
        }

        return template;
      } catch (e) {
        _logger.warning('Failed to load partial $name: $e');
      }
    }

    return null;
  }

  /// Get the full path to a template file
  String _getTemplatePath(String templateName) {
    // Remove leading slash if present
    final cleanName =
        templateName.startsWith('/') ? templateName.substring(1) : templateName;

    // Add extension if not present
    final nameWithExtension = cleanName.endsWith(_templateExtension)
        ? cleanName
        : '$cleanName$_templateExtension';

    return '$_viewsPath/$nameWithExtension';
  }

  /// Ensure views directory exists
  void _ensureViewsDirectory() {
    final viewsDir = Directory(_viewsPath);
    if (!viewsDir.existsSync()) {
      viewsDir.createSync(recursive: true);
      _logger.info('Created views directory: $_viewsPath');
    }

    // Create layouts directory if it doesn't exist
    final layoutsDir = Directory('$_viewsPath/layouts');
    if (!layoutsDir.existsSync()) {
      layoutsDir.createSync(recursive: true);
      _logger.info('Created layouts directory: $_viewsPath/layouts');
    }
  }

  // Helper Functions

  String _formatDate(String dateStr) {
    try {
      final date = DateTime.parse(dateStr);
      return '${date.day}/${date.month}/${date.year}';
    } catch (e) {
      return dateStr;
    }
  }

  String _truncate(String text, int length) {
    if (text.length <= length) return text;
    return '${text.substring(0, length - 3)}...';
  }

  /// Create default templates for a new application
  static Future<void> createDefaultTemplates(String viewsPath) async {
    final logger = DLogger.scoped('TEMPLATES');

    // Create application layout
    final layoutsDir = Directory('$viewsPath/layouts');
    await layoutsDir.create(recursive: true);

    final applicationLayout = File('$viewsPath/layouts/application.mustache');
    if (!applicationLayout.existsSync()) {
      await applicationLayout.writeAsString('''
        <!DOCTYPE html>
        <html lang="en">
        <head>
            <meta charset="UTF-8">
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
            <title>{{#has_title}}{{title}}{{/has_title}}{{^has_title}}D_Server Application{{/has_title}}</title>
            <style>
                body { font-family: Arial, sans-serif; }
                .container { max-width: 800px; margin: 0 auto; }
                .flash { padding: 10px; margin: 10px 0; border-radius: 4px; }
                .flash.success { background: #d4edda; color: #155724; border: 1px solid #c3e6cb; }
                .flash.error { background: #f8d7da; color: #721c24; border: 1px solid #f5c6cb; }
                .flash.warning { background: #fff3cd; color: #856404; border: 1px solid #ffeaa7; }
            </style>
        </head>
        <body>
            <div class="container">
            {{#flash}}
                {{#success}}
                <div class="flash success">{{flash.success}}</div>
                {{/success}}

                {{#error}}
                <div class="flash error">{{flash.error}}</div>
                {{/error}}

                {{#warning}}
                <div class="flash warning">{{flash.warning}}</div>
                {{/warning}}
            {{/flash}}

                {{{content}}}
            </div>
        </body>
        </html>
''');
      logger.success('Created application layout template');
    }

    // Create error templates
    final errorDir = Directory('$viewsPath/errors');
    await errorDir.create(recursive: true);

    final notFoundTemplate = File('$viewsPath/errors/404.mustache');
    if (!notFoundTemplate.existsSync()) {
      await notFoundTemplate.writeAsString('''<h1>Page Not Found</h1>
<p>The page you are looking for could not be found.</p>
<p><a href="/">Go back to home</a></p>
''');
      logger.success('Created 404 error template');
    }

    final serverErrorTemplate = File('$viewsPath/errors/500.mustache');
    if (!serverErrorTemplate.existsSync()) {
      await serverErrorTemplate.writeAsString('''<h1>Internal Server Error</h1>
<p>Something went wrong on our end. We're working to fix it.</p>
<p><a href="/">Go back to home</a></p>
''');
      logger.success('Created 500 error template');
    }

    // Create welcome template
    final welcomeTemplate = File('$viewsPath/welcome.mustache');
    if (!welcomeTemplate.existsSync()) {
      await welcomeTemplate.writeAsString('''<h1>Welcome to D_Server!</h1>
<p>Your Dart web framework is up and running.</p>

<h2>Getting Started</h2>
<ul>
    <li>Create your models in <code>lib/models/</code></li>
    <li>Create your controllers in <code>lib/controllers/</code></li>
    <li>Create your views in <code>views/</code></li>
    <li>Define your routes in <code>lib/routes.dart</code></li>
</ul>

<h2>Current Time</h2>
<p>{{current_time}}</p>

<h2>Framework Information</h2>
<ul>
    <li><strong>Framework:</strong> D_Server</li>
    <li><strong>Template Engine:</strong> Mustache</li>
    <li><strong>Environment:</strong> {{#environment}}{{environment}}{{/environment}}{{^environment}}development{{/environment}}</li>
</ul>
''');
      logger.success('Created welcome template');
    }
  }
}

/// Exception thrown when template operations fail
class TemplateException implements Exception {
  final String message;

  TemplateException(this.message);

  @override
  String toString() => 'TemplateException: $message';
}
