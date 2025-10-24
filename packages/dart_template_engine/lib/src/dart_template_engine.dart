import 'dart:async';
import 'dart:io';
import 'package:path/path.dart' as path;

import 'functions/function_registry.dart';
import 'functions/builtin_helpers.dart';
import 'parser/template_parser.dart';
import 'renderer/sync_renderer.dart';
import 'renderer/async_renderer.dart';
import 'partials/partial_loader.dart';
import 'exceptions/template_exception.dart';

/// The main template engine class that provides both sync and async rendering capabilities.
///
/// This class serves as the primary interface for the dart_template_engine package.
/// It combines all the core components (parser, renderer, function registry) into
/// a single, easy-to-use API with filesystem-based template loading.
///
/// ## Features:
/// - File-based template loading with .html.dt extension
/// - Mustache-like syntax support
/// - Helper function calls: `{{@uppercase(name)}}`
/// - Instance method calls: `{{user.getName()}}`
/// - Partial support: `{{> partial_name}}`
/// - Async function support with fallback
/// - Built-in helper functions
/// - Custom function registration
///
/// ## Example:
/// ```dart
/// final engine = DartTemplateEngine(baseDirectory: '/app/templates');
///
/// // Renders /app/templates/users/show.html.dt
/// final result = engine.render('users/show', {'name': 'World'});
///
/// // With partials (searches current directory and subdirectories)
/// // Template: {{> _user_card}}
/// // Loads: /app/templates/users/_user_card.html.dt
/// ```
class DartTemplateEngine {
  final String _baseDirectory;
  final FunctionRegistry _functionRegistry = FunctionRegistry();
  late final TemplateParser _parser;
  late final SyncRenderer _syncRenderer;
  late final AsyncRenderer _asyncRenderer;
  late final PartialLoader _partialLoader;

  static const String _templateExtension = '.html.dt';

  /// Creates a new template engine instance.
  ///
  /// [baseDirectory] is the root directory where template files are stored.
  /// [fallbacks] is a map of fallback values to use when async functions fail
  /// or are not available.
  DartTemplateEngine({
    required String baseDirectory,
    Map<String, dynamic> fallbacks = const {},
  }) : _baseDirectory = baseDirectory {
    if (!Directory(_baseDirectory).existsSync()) {
      throw ArgumentError('Base directory does not exist: $_baseDirectory');
    }

    _parser = TemplateParser();
    _partialLoader = PartialLoader(_baseDirectory);
    _syncRenderer =
        SyncRenderer(_functionRegistry, partialLoader: _partialLoader);
    _asyncRenderer = AsyncRenderer(_functionRegistry, fallbacks,
        partialLoader: _partialLoader);

    // Register all built-in helper functions
    BuiltinHelpers.registerAll(_functionRegistry);
  }

  /// Renders a template string directly (for backward compatibility).
  ///
  /// [templateContent] is the template content as a string.
  /// [context] is the data context to use for rendering.
  ///
  /// Returns the rendered string.
  ///
  /// Throws [TemplateException] if rendering fails.
  @Deprecated('Use render() with template files instead')
  String renderString(String templateContent, Map<String, dynamic> context) {
    try {
      final tokens = _parser.parse(templateContent);
      return _syncRenderer.render(tokens, context);
    } catch (e) {
      if (e is TemplateException) {
        rethrow;
      }
      throw TemplateException.rendering('Failed to render template string',
          cause: e);
    }
  }

  /// Renders a template file synchronously.
  ///
  /// [templateName] is the path to the template file relative to baseDirectory
  /// (without the .html.dt extension).
  /// [context] is the data context to use for rendering.
  ///
  /// Returns the rendered string.
  ///
  /// Throws [TemplateException] if rendering fails.
  String render(String templateName, Map<String, dynamic> context) {
    try {
      final templateContent = _loadTemplateFile(templateName);
      final tokens = _parser.parse(templateContent);
      final currentDirectory = _getTemplateDirectory(templateName);

      return _syncRenderer.render(tokens, context,
          currentDirectory: currentDirectory);
    } catch (e) {
      if (e is TemplateException) {
        rethrow;
      }
      throw TemplateException.rendering(
          'Failed to render template $templateName',
          cause: e);
    }
  }

  /// Renders a template string asynchronously (for backward compatibility).
  ///
  /// [templateContent] is the template content as a string.
  /// [context] is the data context to use for rendering.
  ///
  /// Returns a Future that completes with the rendered string.
  ///
  /// Throws [TemplateException] if rendering fails.
  @Deprecated('Use renderAsync() with template files instead')
  Future<String> renderStringAsync(
      String templateContent, Map<String, dynamic> context) async {
    try {
      final tokens = _parser.parse(templateContent);
      return await _asyncRenderer.renderAsync(tokens, context);
    } catch (e) {
      if (e is TemplateException) {
        rethrow;
      }
      throw TemplateException.rendering(
          'Failed to render template string asynchronously',
          cause: e);
    }
  }

  /// Renders a template file asynchronously.
  ///
  /// [templateName] is the path to the template file relative to baseDirectory
  /// (without the .html.dt extension).
  /// [context] is the data context to use for rendering.
  ///
  /// Returns a Future that completes with the rendered string.
  ///
  /// Throws [TemplateException] if rendering fails.
  Future<String> renderAsync(
      String templateName, Map<String, dynamic> context) async {
    try {
      final templateContent = _loadTemplateFile(templateName);
      final tokens = _parser.parse(templateContent);
      final currentDirectory = _getTemplateDirectory(templateName);

      return await _asyncRenderer.renderAsync(tokens, context,
          currentDirectory: currentDirectory);
    } catch (e) {
      if (e is TemplateException) {
        rethrow;
      }
      throw TemplateException.rendering(
          'Failed to render template $templateName asynchronously',
          cause: e);
    }
  }

  /// Registers a synchronous function that can be called from templates.
  ///
  /// [name] is the name of the function as it will appear in templates.
  /// [function] is the function implementation.
  ///
  /// Example:
  /// ```dart
  /// engine.registerFunction('double', (args) => (args[0] as num) * 2);
  /// // Usage in template: {{@double(value)}}
  /// ```
  void registerFunction(String name, TemplateFunction function) {
    _functionRegistry.registerFunction(name, function);
  }

  /// Registers an asynchronous function that can be called from templates.
  ///
  /// [name] is the name of the function as it will appear in templates.
  /// [function] is the async function implementation.
  ///
  /// Example:
  /// ```dart
  /// engine.registerAsyncFunction('loadUser', (args) async {
  ///   return await userService.getUser(args[0]);
  /// });
  /// // Usage in template: {{@loadUser(userId)}}
  /// ```
  void registerAsyncFunction(String name, AsyncTemplateFunction function) {
    _functionRegistry.registerAsyncFunction(name, function);
  }

  /// Checks if a function is registered with the given name.
  ///
  /// [name] is the function name to check.
  ///
  /// Returns true if the function exists (either sync or async).
  bool hasFunction(String name) {
    return _functionRegistry.hasFunction(name) ||
        _functionRegistry.hasAsyncFunction(name);
  }

  /// Gets a list of all registered function names.
  ///
  /// Returns a list containing both sync and async function names.
  List<String> getRegisteredFunctions() {
    return [
      ..._functionRegistry.getSyncFunctionNames(),
      ..._functionRegistry.getAsyncFunctionNames(),
    ];
  }

  /// Unregisters a function.
  ///
  /// [name] is the name of the function to unregister.
  ///
  /// Returns true if the function was found and removed.
  bool unregisterFunction(String name) {
    return _functionRegistry.unregisterFunction(name);
  }

  /// Clears all registered functions except built-in helpers.
  ///
  /// This is useful for testing or when you want to start with a clean slate.
  void clearCustomFunctions() {
    _functionRegistry.clearCustomFunctions();
  }

  /// Checks if a template file exists.
  ///
  /// [templateName] is the template name relative to baseDirectory.
  ///
  /// Returns true if the template file exists.
  bool templateExists(String templateName) {
    final templatePath = _getTemplatePath(templateName);
    return File(templatePath).existsSync();
  }

  /// Gets the base directory for templates.
  String get baseDirectory => _baseDirectory;

  /// Clears the partial cache.
  ///
  /// This is useful during development when partial files are modified.
  void clearPartialCache() {
    _partialLoader.clearCache();
  }

  /// Gets cache statistics for partials.
  ///
  /// Returns a map with cache information for debugging purposes.
  Map<String, dynamic> getPartialCacheStats() {
    return _partialLoader.getCacheStats();
  }

  /// Loads template content from file.
  ///
  /// [templateName] is the template name relative to baseDirectory.
  ///
  /// Returns the template file content.
  /// Throws [TemplateException] if the file cannot be loaded.
  String _loadTemplateFile(String templateName) {
    final templatePath = _getTemplatePath(templateName);
    final templateFile = File(templatePath);

    if (!templateFile.existsSync()) {
      throw TemplateException.parsing(
        'Template file not found: $templatePath',
      );
    }

    try {
      return templateFile.readAsStringSync();
    } catch (e) {
      throw TemplateException.parsing(
        'Failed to read template file $templatePath: $e',
        cause: e,
      );
    }
  }

  /// Gets the full path to a template file.
  ///
  /// [templateName] is the template name relative to baseDirectory.
  ///
  /// Returns the full file path.
  String _getTemplatePath(String templateName) {
    return path.join(_baseDirectory, '$templateName$_templateExtension');
  }

  /// Gets the directory containing a template file.
  ///
  /// [templateName] is the template name relative to baseDirectory.
  ///
  /// Returns the directory path for the template.
  String _getTemplateDirectory(String templateName) {
    final templatePath = _getTemplatePath(templateName);
    return path.dirname(templatePath);
  }
}
