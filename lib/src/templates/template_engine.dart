import 'dart:io';
import 'package:dart_template_engine/dart_template_engine.dart' as dte;
import '../core/logger.dart';

/// Template engine wrapper for D_Server framework using dart_template_engine.
///
/// Provides the same API as the original TemplateEngine but uses dart_template_engine
/// internally for better performance and more features.
class TemplateEngine {
  final String _viewsPath;
  final ScopedLogger _logger = DLogger.scoped('TEMPLATES');
  late final dte.DartTemplateEngine _engine;

  bool _cacheEnabled = true;
  String _defaultLayout = 'application';
  String _templateExtension = '.html.dt';

  TemplateEngine(
    this._viewsPath, {
    bool cacheEnabled = true,
    String defaultLayout = 'application',
    String templateExtension = '.html.dt',
    dynamic config,
  })  : _cacheEnabled = cacheEnabled,
        _defaultLayout = defaultLayout,
        _templateExtension = templateExtension {
    _ensureViewsDirectory();
    _initializeEngine();
  }

  /// Initialize the dart_template_engine and register D_Server helpers
  void _initializeEngine() {
    _engine = dte.DartTemplateEngine(baseDirectory: _viewsPath);
    _registerDServerHelpers();
  }

  /// Render a template without layout
  String render(String templateName, [Map<String, dynamic>? context]) {
    final renderContext = _buildContext(context);

    try {
      final stopwatch = Stopwatch()..start();
      final result = _engine.render(templateName, renderContext);
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
    String templateName, [
    Map<String, dynamic> context = const {},
  ]) {
    return renderWithLayout(templateName, _defaultLayout, context);
  }

  /// Check if a template exists
  bool templateExists(String templateName) {
    return _engine.templateExists(templateName);
  }

  /// Clear the template cache
  void clearCache() {
    _engine.clearPartialCache();
    _logger.info('Template cache cleared');
  }

  /// Get template cache statistics
  Map<String, dynamic> getCacheStats() {
    final partialStats = _engine.getPartialCacheStats();
    return {
      'cached_templates': partialStats['cached_partials'] ?? 0,
      'cache_enabled': _cacheEnabled,
    };
  }

  /// Register a partial template
  void registerPartial(String name, String templateContent) {
    // For now, partials are handled automatically by the file system
    // This method is kept for API compatibility
    _logger
        .debug('Note: Partials are now loaded automatically from filesystem');
  }

  /// Build rendering context with helper functions
  Map<String, dynamic> _buildContext(Map<String, dynamic>? userContext) {
    final context = <String, dynamic>{
      // Helper functions that return values directly
      'current_time': DateTime.now().toIso8601String(),
      'has_title': userContext != null && userContext.containsKey('title'),
      ...?userContext,
    };

    return context;
  }

  /// Register all D_Server specific helper functions
  void _registerDServerHelpers() {
    // Asset path helper
    _engine.registerFunction('asset_path', (args) {
      if (args.isEmpty) return '';
      return _assetPath(args[0].toString());
    });

    // Date formatting helper
    _engine.registerFunction('format_date', (args) {
      _logger.info('Formate date: ${args}');

      if (args.isEmpty) return '';
      final dateStr = args[0].toString();
      final format = args.length > 1 ? args[1].toString() : 'yyyy-MM-dd';
      return _formatDate(dateStr, format);
    });

    _logger.info('Registered formatDate ${_engine.hasFunction('formatDate')}');

    // CSS link tag helper
    _engine.registerFunction('stylesheet_link_tag', (args) {
      if (args.isEmpty) return '';
      return _stylesheetLinkTag(args[0].toString());
    });

    // JavaScript include tag helper
    _engine.registerFunction('javascript_include_tag', (args) {
      if (args.isEmpty) return '';
      return _javascriptIncludeTag(args[0].toString());
    });

    // Image tag helper
    _engine.registerFunction('image_tag', (args) {
      if (args.isEmpty) return '';
      final src = args[0].toString();
      final alt = args.length > 1 ? args[1].toString() : '';
      final cssClass = args.length > 2 ? args[2].toString() : '';
      return _imageTag(src, alt: alt, cssClass: cssClass);
    });

    // Favicon link tag helper
    _engine.registerFunction('favicon_link_tag', (args) {
      final href = args.isNotEmpty ? args[0].toString() : 'favicon.ico';
      return _faviconLinkTag(href);
    });

    // Link helper
    _engine.registerFunction('link_to', (args) {
      if (args.length < 2) return '';
      final text = args[0].toString();
      final url = args[1].toString();
      final cssClass = args.length > 2 ? args[2].toString() : '';
      return _linkTo(text, url, cssClass: cssClass);
    });

    // Current time helper function
    _engine.registerFunction('current_time', (args) {
      return DateTime.now().toIso8601String();
    });
  }

  /// Ensure views directory exists
  void _ensureViewsDirectory() {
    final viewsDir = Directory(_viewsPath);
    if (!viewsDir.existsSync()) {
      viewsDir.createSync(recursive: true);
      _logger.info('Created views directory: $_viewsPath');
    }
  }

  /// Format date string
  String _formatDate(String dateStr, String format) {
    try {
      final date = DateTime.parse(dateStr);
      // Simple format implementation - can be extended
      return date.toIso8601String().split('T')[0];
    } catch (e) {
      return dateStr;
    }
  }

  /// Generate asset path
  String _assetPath(String asset) {
    // Simple asset path - can be extended with versioning, CDN, etc.
    return '/assets/$asset';
  }

  /// Generate stylesheet link tag
  String _stylesheetLinkTag(String href) {
    final assetHref = _assetPath('$href.css');
    return '<link rel="stylesheet" href="$assetHref" type="text/css">';
  }

  /// Generate JavaScript include tag
  String _javascriptIncludeTag(String src) {
    final assetSrc = _assetPath('$src.js');
    return '<script src="$assetSrc" type="text/javascript"></script>';
  }

  /// Generate image tag
  String _imageTag(String src, {String alt = '', String cssClass = ''}) {
    final assetSrc = _assetPath(src);
    final classAttr = cssClass.isNotEmpty ? ' class="$cssClass"' : '';
    final altAttr = alt.isNotEmpty ? ' alt="$alt"' : '';
    return '<img src="$assetSrc"$altAttr$classAttr>';
  }

  /// Generate favicon link tag
  String _faviconLinkTag(String href) {
    final assetHref = _assetPath(href);
    return '<link rel="icon" type="image/x-icon" href="$assetHref">';
  }

  /// Generate link tag
  String _linkTo(String text, String url, {String cssClass = ''}) {
    final classAttr = cssClass.isNotEmpty ? ' class="$cssClass"' : '';
    return '<a href="$url"$classAttr>$text</a>';
  }

  /// Create default templates with new syntax
  static Future<void> createDefaultTemplates(String viewsPath) async {
    final logger = DLogger.scoped('TEMPLATES');

    // Create application layout
    final layoutsDir = Directory('$viewsPath/layouts');
    await layoutsDir.create(recursive: true);

    final applicationLayout = File('$viewsPath/layouts/application.html.dt');
    if (!applicationLayout.existsSync()) {
      await applicationLayout.writeAsString('''<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>{{@default(title, "D_Server Application")}}</title>

    {{! Asset helpers with new function syntax }}
    {{{@favicon_link_tag("favicon.ico")}}}
    {{{@stylesheet_link_tag("css/app")}}}

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
            max-width: 1200px;
            margin: 0 auto;
            background: white;
            padding: 30px;
            border-radius: 8px;
            box-shadow: 0 2px 10px rgba(0,0,0,0.1);
        }

        h1, h2, h3 {
            color: #2c3e50;
            margin-top: 0;
        }

        .header {
            border-bottom: 2px solid #3498db;
            padding-bottom: 20px;
            margin-bottom: 30px;
        }

        .header h1 {
            margin: 0;
            color: #3498db;
        }

        .nav {
            margin-top: 15px;
        }

        .nav a {
            color: #3498db;
            text-decoration: none;
            margin-right: 20px;
            padding: 5px 10px;
            border-radius: 4px;
            transition: background-color 0.3s;
        }

        .nav a:hover {
            background-color: #ecf0f1;
        }

        .footer {
            border-top: 1px solid #ecf0f1;
            padding-top: 20px;
            margin-top: 40px;
            text-align: center;
            color: #7f8c8d;
            font-size: 0.9em;
        }

        .alert {
            padding: 12px 20px;
            margin: 20px 0;
            border-radius: 4px;
            border: 1px solid transparent;
        }

        .alert-success {
            color: #155724;
            background-color: #d4edda;
            border-color: #c3e6cb;
        }

        .alert-error {
            color: #721c24;
            background-color: #f8d7da;
            border-color: #f5c6cb;
        }

        .alert-info {
            color: #0c5460;
            background-color: #d1ecf1;
            border-color: #bee5eb;
        }
    </style>
</head>
<body>
    <div class="container">
        <header class="header">
            <h1>{{@default(title, "D_Server Application")}}</h1>
            <nav class="nav">
                {{{@link_to("Home", "/", "nav-link")}}}
                {{{@link_to("About", "/about", "nav-link")}}}
            </nav>
        </header>

        <main>
            {{! Flash messages }}
            {{! Flash messages would be handled by controller logic }}

            {{! Main content }}
            {{{content}}}
        </main>

        <footer class="footer">
            <p>&copy; 2025 D_Server Application. Built with ❤️ using Dart.</p>
            <p><small>Generated at {{@current_time()}}</small></p>
        </footer>
    </div>

    {{! Additional JavaScript }}
    {{{@javascript_include_tag("js/app")}}}
</body>
</html>''');

      logger.info('Created default application layout');
    }

    // Create welcome template
    final welcomeTemplate = File('$viewsPath/welcome.html.dt');
    if (!welcomeTemplate.existsSync()) {
      await welcomeTemplate.writeAsString('''<div class="welcome">
    <h1>🎉 Welcome to D_Server!</h1>

    <p>Your D_Server application is up and running. This is the default welcome page.</p>

    <h2>🚀 Getting Started</h2>
    <ul>
        <li>Create your controllers in <code>lib/controllers/</code></li>
        <li>Define your models in <code>lib/models/</code></li>
        <li>Add your templates in <code>views/</code></li>
        <li>Configure routes in <code>lib/routes.dart</code></li>
    </ul>

    <h2>📚 Documentation</h2>
    <p>Check out the D_Server documentation for more information:</p>
    <ul>
        <li>{{{@link_to("Controllers Guide", "/docs/controllers")}}}</li>
        <li>{{{@link_to("Models & ORM", "/docs/models")}}}</li>
        <li>{{{@link_to("Templates", "/docs/templates")}}}</li>
        <li>{{{@link_to("Routing", "/docs/routing")}}}</li>
    </ul>

    <h2>🔧 Template Features</h2>
    <p>This template demonstrates some D_Server template features:</p>

    <h3>Asset Helpers</h3>
    <p>Generate asset links with proper paths:</p>
    <ul>
        <li><code>{{@asset_path("images/logo.png")}}</code> → {{@asset_path("images/logo.png")}}</li>
        <li><code>{{@stylesheet_link_tag("custom")}}</code> → {{@stylesheet_link_tag("custom")}}</li>
    </ul>

    <h3>Date & Time</h3>
    <p>Current time: <strong>{{@current_time()}}</strong></p>

    <h3>Text Helpers</h3>
    <p>Truncate long text: {{@truncate("This is a very long text that will be truncated for display purposes", 50)}}</p>

    <div style="margin-top: 30px; padding: 20px; background: #f8f9fa; border-radius: 8px;">
        <h3>💡 Quick Tip</h3>
        <p>To customize this page, edit <code>views/welcome.html.dt</code></p>
        <p>To change the layout, edit <code>views/layouts/application.html.dt</code></p>
    </div>
</div>''');

      logger.info('Created default welcome template');
    }

    // Create error templates
    final errorDir = Directory('$viewsPath/errors');
    await errorDir.create(recursive: true);

    // 404 error template
    final error404 = File('$viewsPath/errors/404.html.dt');
    if (!error404.existsSync()) {
      await error404.writeAsString('''<div class="error-page">
    <h1>404 - Page Not Found</h1>
    <p>The page you are looking for does not exist.</p>
    <p>{{{@link_to("← Go Home", "/")}}}</p>
</div>

<style>
.error-page {
    text-align: center;
    padding: 60px 20px;
}
.error-page h1 {
    font-size: 3em;
    color: #e74c3c;
    margin-bottom: 20px;
}
</style>''');

      logger.info('Created 404 error template');
    }

    // 500 error template
    final error500 = File('$viewsPath/errors/500.html.dt');
    if (!error500.existsSync()) {
      await error500.writeAsString('''<div class="error-page">
    <h1>500 - Internal Server Error</h1>
    <p>Something went wrong on our end. Please try again later.</p>
    <p>{{{@link_to("← Go Home", "/")}}}</p>
</div>

<style>
.error-page {
    text-align: center;
    padding: 60px 20px;
}
.error-page h1 {
    font-size: 3em;
    color: #e74c3c;
    margin-bottom: 20px;
}
</style>''');

      logger.info('Created 500 error template');
    }

    logger.info('Default templates created successfully');
  }
}

class TemplateException implements Exception {
  final String message;
  final dynamic cause;

  TemplateException(this.message, [this.cause]);

  @override
  String toString() => 'TemplateException: $message';
}
