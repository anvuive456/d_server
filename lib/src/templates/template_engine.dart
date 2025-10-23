import 'dart:io';
import 'package:mustache_template/mustache_template.dart';
import '../core/logger.dart';
import '../core/config.dart';

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
  final DConfig? _config;

  bool _cacheEnabled = true;
  String _defaultLayout = 'application';
  String _templateExtension = '.mustache';

  TemplateEngine(
    this._viewsPath, {
    bool cacheEnabled = true,
    String defaultLayout = 'application',
    String templateExtension = '.mustache',
    DConfig? config,
  })  : _cacheEnabled = cacheEnabled,
        _defaultLayout = defaultLayout,
        _templateExtension = templateExtension,
        _config = config {
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
      // Helper functions that return values directly
      'current_time': DateTime.now().toIso8601String(),

      // Asset helpers - these need to be lambda functions for Mustache
      'asset_path': (LambdaContext ctx) => _assetPath(ctx.renderString()),
      'stylesheet_link_tag': (LambdaContext ctx) =>
          _stylesheetLinkTag(ctx.renderString()),
      'javascript_include_tag': (LambdaContext ctx) =>
          _javascriptIncludeTag(ctx.renderString()),
      'image_tag': (LambdaContext ctx) {
        final parts = ctx.renderString().split(' ');
        final src = parts.isNotEmpty ? parts[0] : '';
        final alt = parts.length > 1 ? parts[1] : '';
        final className = parts.length > 2 ? parts[2] : '';
        final style = parts.length > 3 ? parts[3] : '';
        return _imageTag(src, alt, className.isEmpty ? null : className,
            style.isEmpty ? null : style);
      },
      'favicon_link_tag': (LambdaContext ctx) => _faviconLinkTag(),

      // Link helpers
      'link_to': (LambdaContext ctx) {
        final parts = ctx.renderString().split(' ');
        final text = parts.isNotEmpty ? parts[0] : '';
        final href = parts.length > 1 ? parts[1] : '';
        return _linkTo(text, href);
      },

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

  // Asset Helper Functions

  /// Generate asset path with URL prefix
  String _assetPath(String path) {
    final staticUrlPath = _config?.get<String>('static_files.url_path',
            defaultValue: '/assets') ??
        '/assets';

    // Remove leading slash from path if present
    final cleanPath = path.startsWith('/') ? path.substring(1) : path;

    // Ensure static URL path doesn't end with slash
    final cleanUrlPath = staticUrlPath.endsWith('/')
        ? staticUrlPath.substring(0, staticUrlPath.length - 1)
        : staticUrlPath;

    return '$cleanUrlPath/$cleanPath';
  }

  /// Generate stylesheet link tag
  String _stylesheetLinkTag(String path) {
    final assetPath = _assetPath(path.endsWith('.css') ? path : '$path.css');
    return '<link rel="stylesheet" href="$assetPath">';
  }

  /// Generate JavaScript include tag
  String _javascriptIncludeTag(String path) {
    final assetPath = _assetPath(path.endsWith('.js') ? path : '$path.js');
    return '<script src="$assetPath"></script>';
  }

  /// Generate image tag with optional attributes
  String _imageTag(String src,
      [String alt = '', String? className, String? style]) {
    final assetPath = _assetPath(src);
    final attrs = <String, String>{'src': assetPath, 'alt': alt};

    if (className != null && className.isNotEmpty) {
      attrs['class'] = className;
    }

    if (style != null && style.isNotEmpty) {
      attrs['style'] = style;
    }

    final attrString =
        attrs.entries.map((e) => '${e.key}="${e.value}"').join(' ');

    return '<img $attrString>';
  }

  /// Generate favicon link tag
  String _faviconLinkTag([String? path]) {
    final faviconPath = _assetPath(path ?? 'favicon.ico');
    return '<link rel="icon" href="$faviconPath">';
  }

  /// Generate link tag
  String _linkTo(String text, String href) {
    return '<a href="$href">$text</a>';
  }

  /// Create default templates for a new application
  static Future<void> createDefaultTemplates(String viewsPath) async {
    final logger = DLogger.scoped('TEMPLATES');

    // Create application layout
    final layoutsDir = Directory('$viewsPath/layouts');
    await layoutsDir.create(recursive: true);

    final applicationLayout = File('$viewsPath/layouts/application.mustache');
    if (!applicationLayout.existsSync()) {
      await applicationLayout.writeAsString('''<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>{{#has_title}}{{title}}{{/has_title}}{{^has_title}}D_Server Application{{/has_title}}</title>

    {{! Asset helpers in action }}
    {{#favicon_link_tag}}{{/favicon_link_tag}}
    {{#stylesheet_link_tag}}css/app{{/stylesheet_link_tag}}

    {{! Additional stylesheets can be added per page }}
    {{#stylesheets}}
    {{#stylesheet_link_tag}}{{.}}{{/stylesheet_link_tag}}
    {{/stylesheets}}

    <style>
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
        .flash { padding: 15px; margin: 15px 0; border-radius: 4px; }
        .flash.success { background: #d4edda; color: #155724; border: 1px solid #c3e6cb; }
        .flash.error { background: #f8d7da; color: #721c24; border: 1px solid #f5c6cb; }
        .flash.warning { background: #fff3cd; color: #856404; border: 1px solid #ffeaa7; }
        .navbar { background: #667eea; color: white; padding: 1rem 0; margin: -30px -30px 30px; border-radius: 8px 8px 0 0; }
        .navbar .container { background: none; padding: 0 30px; box-shadow: none; margin: 0; }
        .navbar h1 { margin: 0; }
        .navbar a { color: white; text-decoration: none; margin-right: 20px; }
        .navbar a:hover { text-decoration: underline; }
    </style>
</head>
<body>
    <div class="navbar">
        <div class="container">
            <h1>{{#app_name}}{{app_name}}{{/app_name}}{{^app_name}}D_Server App{{/app_name}}</h1>
            <nav>
                {{#link_to}}Home /{{/link_to}}
                {{#link_to}}About /about{{/link_to}}
            </nav>
        </div>
    </div>

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

    {{! Asset helpers for JavaScript }}
    {{#javascript_include_tag}}js/app{{/javascript_include_tag}}

    {{! Additional scripts can be added per page }}
    {{#javascripts}}
    {{#javascript_include_tag}}{{.}}{{/javascript_include_tag}}
    {{/javascripts}}
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
      await welcomeTemplate
          .writeAsString('''<div style="text-align: center; margin: 2rem 0;">
    {{#image_tag}}images/d_server_logo.png D_Server_Logo  width:200px;height:auto;{{/image_tag}}
</div>

<h1>🚀 Welcome to D_Server!</h1>
<p>Your Dart web framework is up and running with <strong>asset pipeline</strong> enabled!</p>

<h2>✨ Asset Pipeline Features</h2>
<div class="feature-grid" style="display: grid; grid-template-columns: repeat(auto-fit, minmax(250px, 1fr)); gap: 1rem; margin: 2rem 0;">
    <div style="padding: 1rem; background: #f8f9fa; border-radius: 8px;">
        <h3>🎨 Stylesheets</h3>
        <p>Automatically served from <code>{{#asset_path}}css/{{/asset_path}}</code></p>
        <code>&lt;link rel="stylesheet" href="{{#asset_path}}css/app.css{{/asset_path}}"&gt;</code>
    </div>

    <div style="padding: 1rem; background: #f8f9fa; border-radius: 8px;">
        <h3>⚡ JavaScript</h3>
        <p>Automatically served from <code>{{#asset_path}}js/{{/asset_path}}</code></p>
        <code>&lt;script src="{{#asset_path}}js/app.js{{/asset_path}}"&gt;&lt;/script&gt;</code>
    </div>

    <div style="padding: 1rem; background: #f8f9fa; border-radius: 8px;">
        <h3>🖼️ Images</h3>
        <p>Automatically served from <code>{{#asset_path}}images/{{/asset_path}}</code></p>
        <code>&lt;img src="{{#asset_path}}images/logo.png{{/asset_path}}" alt="Logo"&gt;</code>
    </div>

    <div style="padding: 1rem; background: #f8f9fa; border-radius: 8px;">
        <h3>🔗 Icons</h3>
        <p>Favicon automatically served</p>
        <code>&lt;link rel="icon" href="{{#asset_path}}favicon.ico{{/asset_path}}"&gt;</code>
    </div>
</div>

<h2>🛠️ Getting Started</h2>
<ul>
    <li>Create your models in <code>lib/models/</code></li>
    <li>Create your controllers in <code>lib/controllers/</code></li>
    <li>Create your views in <code>views/</code></li>
    <li>Add your assets in <code>public/</code></li>
    <li>Define your routes in <code>lib/main.dart</code></li>
</ul>

<h2>📂 Asset Structure</h2>
<pre style="background: #f8f9fa; padding: 1rem; border-radius: 4px; overflow-x: auto;">
public/
├── css/
│   └── app.css          → {{#asset_path}}css/app.css{{/asset_path}}
├── js/
│   └── app.js           → {{#asset_path}}js/app.js{{/asset_path}}
├── images/
│   └── logo.png         → {{#asset_path}}images/logo.png{{/asset_path}}
└── favicon.ico          → {{#asset_path}}favicon.ico{{/asset_path}}
</pre>

<h2>🕐 Current Time</h2>
<p>{{current_time}}</p>

<h2>⚙️ Framework Information</h2>
<ul>
    <li><strong>Framework:</strong> D_Server</li>
    <li><strong>Template Engine:</strong> Mustache with Asset Helpers</li>
    <li><strong>Asset Pipeline:</strong> ✅ Enabled</li>
    <li><strong>Static Files:</strong> {{#asset_path}}{{/asset_path}}</li>
    <li><strong>Environment:</strong> {{#environment}}{{environment}}{{/environment}}{{^environment}}development{{/environment}}</li>
</ul>

<div style="margin-top: 3rem; padding: 1rem; background: linear-gradient(45deg, #667eea, #764ba2); color: white; border-radius: 8px; text-align: center;">
    <h3>🎉 Ready to build amazing web applications!</h3>
    <p>Your D_Server framework is configured and ready to go.</p>
</div>
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
