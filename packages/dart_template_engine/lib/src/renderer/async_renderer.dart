import 'dart:async';
import '../parser/token.dart';
import '../parser/lexer.dart';
import '../functions/function_registry.dart';
import '../renderer/method_invoker.dart';
import '../partials/partial_loader.dart';
import '../exceptions/template_exception.dart';

/// Asynchronous template renderer that handles both sync and async operations.
///
/// This renderer extends the capabilities of the sync renderer by adding
/// support for async function calls with fallback handling. When async
/// functions are not available or fail, it can fall back to sync functions
/// or default values.
///
/// ## Features:
/// - All sync renderer capabilities
/// - Async function call support
/// - Fallback mechanisms for failed async operations
/// - Mixed sync/async rendering
/// - Partial support with filesystem loading
/// - Graceful error handling with fallbacks
///
/// ## Example:
/// ```dart
/// final registry = FunctionRegistry();
/// final fallbacks = {'loadUser': 'Unknown User'};
/// final partialLoader = PartialLoader('/templates');
/// final renderer = AsyncRenderer(registry, fallbacks, partialLoader: partialLoader);
///
/// final tokens = parser.parse('Hello {{@loadUser(userId)}}!');
/// final result = await renderer.renderAsync(tokens, {'userId': 123});
/// ```
class AsyncRenderer {
  final FunctionRegistry _functionRegistry;
  final Map<String, dynamic> _fallbacks;
  final PartialLoader? _partialLoader;
  final bool _escapeHtml;
  String? _currentDirectory;

  /// Creates a new asynchronous renderer.
  ///
  /// [functionRegistry] is used to resolve both sync and async function calls.
  /// [fallbacks] is a map of fallback values to use when async functions fail.
  /// [partialLoader] is used to load partial templates from filesystem.
  /// [escapeHtml] determines whether to escape HTML in output (default: true).
  AsyncRenderer(
    this._functionRegistry,
    this._fallbacks, {
    PartialLoader? partialLoader,
    bool escapeHtml = true,
  })  : _partialLoader = partialLoader,
        _escapeHtml = escapeHtml;

  /// Renders a list of tokens asynchronously with the given context.
  ///
  /// [tokens] are the parsed template tokens.
  /// [context] is the data context for variable resolution.
  /// [currentDirectory] is the directory of the current template (for partials).
  ///
  /// Returns the rendered string.
  /// Throws [TemplateException] if rendering fails.
  Future<String> renderAsync(List<Token> tokens, Map<String, dynamic> context,
      {String? currentDirectory}) async {
    _currentDirectory = currentDirectory;
    final buffer = StringBuffer();
    var i = 0;

    while (i < tokens.length) {
      final token = tokens[i];

      switch (token.type) {
        case TokenType.text:
          buffer.write(token.content);
          break;

        case TokenType.variable:
          final value = _resolveVariable(token, context);
          buffer.write(_formatOutput(value, escape: true));
          break;

        case TokenType.unescapedVariable:
          final value = _resolveVariable(token, context);
          buffer.write(_formatOutput(value, escape: false));
          break;

        case TokenType.functionCall:
          final value = await _callFunctionAsync(token, context);
          // Check if this is an unescaped function call from triple mustache
          final isUnescaped = token.metadata?['unescaped'] == true;
          buffer.write(_formatOutput(value, escape: !isUnescaped));
          break;

        case TokenType.sectionStart:
          final sectionResult = await _renderSectionAsync(tokens, i, context);
          buffer.write(sectionResult.content);
          i = sectionResult.nextIndex - 1; // -1 because loop will increment
          break;

        case TokenType.invertedSection:
          final sectionResult =
              await _renderInvertedSectionAsync(tokens, i, context);
          buffer.write(sectionResult.content);
          i = sectionResult.nextIndex - 1; // -1 because loop will increment
          break;

        case TokenType.partial:
          final partialOutput = await _renderPartialAsync(token, context);
          if (partialOutput != null) {
            buffer.write(partialOutput);
          }
          break;

        case TokenType.comment:
          // Comments produce no output
          break;

        case TokenType.sectionEnd:
          // Section ends are handled by section start processing
          throw TemplateException.parsing(
            'Unexpected section end: ${token.content}',
            position: token.position,
          );
      }

      i++;
    }

    return buffer.toString();
  }

  /// Calls a function (sync or async) from a function call token.
  Future<dynamic> _callFunctionAsync(
      Token token, Map<String, dynamic> context) async {
    final functionName = token.metadata?['functionName'] as String?;
    final isHelper = token.metadata?['isHelper'] as bool? ?? false;
    final argumentDefs = token.metadata?['arguments'] as List<dynamic>? ?? [];

    if (functionName == null) {
      throw TemplateException.functionCall('unknown', 'Missing function name');
    }

    // Resolve arguments
    final args = _resolveArguments(argumentDefs, context);

    if (isHelper) {
      // Helper function call: @functionName(args)
      final cleanName = functionName.startsWith('@')
          ? functionName.substring(1)
          : functionName;

      // Try async function first
      if (_functionRegistry.hasAsyncFunction(cleanName)) {
        try {
          return await _functionRegistry.callAsyncFunction(cleanName, args);
        } catch (e) {
          // Fall back to sync function or default value
          return _handleAsyncFunctionFallback(cleanName, args, e);
        }
      }

      // Try sync function
      if (_functionRegistry.hasFunction(cleanName)) {
        try {
          return _functionRegistry.callFunction(cleanName, args);
        } catch (e) {
          return _handleAsyncFunctionFallback(cleanName, args, e);
        }
      }

      // Function not found, use fallback
      return _handleAsyncFunctionFallback(
          cleanName, args, ArgumentError('Function not found: $cleanName'));
    } else {
      // Method call: object.method(args) - always sync
      return _callMethodSync(functionName, args, context);
    }
  }

  /// Handles fallback when async function calls fail.
  dynamic _handleAsyncFunctionFallback(
      String functionName, List<dynamic> args, dynamic error) {
    // Check if there's a specific fallback for this function
    if (_fallbacks.containsKey(functionName)) {
      return _fallbacks[functionName];
    }

    // Check for generic fallback
    if (_fallbacks.containsKey('*')) {
      return _fallbacks['*'];
    }

    // No fallback available, throw the original error
    throw TemplateException.functionCall(
      functionName,
      'Async function failed and no fallback available: $error',
      cause: error,
    );
  }

  /// Calls a sync method on an object.
  dynamic _callMethodSync(
      String functionName, List<dynamic> args, Map<String, dynamic> context) {
    final parts = functionName.split('.');
    if (parts.length < 2) {
      throw TemplateException.functionCall(
          functionName, 'Invalid method call format');
    }

    final objectPath = parts.sublist(0, parts.length - 1);
    final methodName = parts.last;

    // Resolve the object
    dynamic obj = context;
    for (final segment in objectPath) {
      if (obj == null) {
        throw TemplateException.functionCall(
            functionName, 'Object not found in context');
      }
      if (obj is Map<String, dynamic>) {
        obj = obj[segment];
      } else {
        try {
          obj = MethodInvoker.getProperty(obj, segment);
        } catch (e) {
          throw TemplateException.functionCall(
              functionName, 'Cannot access property $segment: $e');
        }
      }
    }

    if (obj == null) {
      throw TemplateException.functionCall(
          functionName, 'Target object is null');
    }

    // Call the method
    try {
      return MethodInvoker.invokeMethod(obj, methodName, args);
    } catch (e) {
      throw TemplateException.functionCall(
          functionName, 'Method invocation failed: $e');
    }
  }

  /// Resolves a variable token to its value in the context.
  dynamic _resolveVariable(Token token, Map<String, dynamic> context) {
    final path = token.metadata?['path'] as List<String>?;
    if (path == null || path.isEmpty) {
      return null;
    }

    dynamic current = context;
    for (final segment in path) {
      if (current == null) {
        return null;
      }

      if (current is Map<String, dynamic>) {
        current = current[segment];
      } else {
        // Try to access property via reflection
        try {
          current = MethodInvoker.getProperty(current, segment);
        } catch (e) {
          return null;
        }
      }
    }

    return current;
  }

  /// Resolves function arguments from their definitions.
  List<dynamic> _resolveArguments(
      List<dynamic> argumentDefs, Map<String, dynamic> context) {
    final args = <dynamic>[];

    for (final argDef in argumentDefs) {
      if (argDef is Map && argDef['type'] == 'variable') {
        // Variable reference
        final path = argDef['path'] as List<String>;
        dynamic value = context;
        for (final segment in path) {
          if (value is Map<String, dynamic>) {
            value = value[segment];
          } else if (value != null) {
            try {
              value = MethodInvoker.getProperty(value, segment);
            } catch (e) {
              value = null;
              break;
            }
          } else {
            value = null;
            break;
          }
        }
        args.add(value);
      } else {
        // Literal value
        args.add(argDef);
      }
    }

    return args;
  }

  /// Renders a section asynchronously.
  Future<AsyncSectionRenderResult> _renderSectionAsync(
      List<Token> tokens, int startIndex, Map<String, dynamic> context) async {
    final startToken = tokens[startIndex];
    final sectionName = startToken.metadata?['sectionName'] as String?;

    if (sectionName == null) {
      throw TemplateException.parsing('Missing section name',
          position: startToken.position);
    }

    // Find the matching end token (same logic as sync renderer)
    final sectionTokens = <Token>[];
    var nestLevel = 0;
    var endIndex = startIndex + 1;

    while (endIndex < tokens.length) {
      final token = tokens[endIndex];

      if (token.type == TokenType.sectionStart) {
        nestLevel++;
        sectionTokens.add(token);
      } else if (token.type == TokenType.sectionEnd) {
        if (nestLevel == 0 && token.content == sectionName) {
          break; // Found matching end
        } else if (nestLevel > 0) {
          nestLevel--;
          sectionTokens.add(token);
        }
      } else {
        sectionTokens.add(token);
      }

      endIndex++;
    }

    if (endIndex >= tokens.length) {
      throw TemplateException.parsing(
        'Unclosed section: $sectionName',
        position: startToken.position,
      );
    }

    // Resolve the section value
    final sectionValue = _resolveVariable(
      Token.variable(sectionName, startToken.position, metadata: {
        'path': sectionName.split('.'),
      }),
      context,
    );

    final buffer = StringBuffer();

    // Render based on section value type
    if (sectionValue == null || sectionValue == false) {
      // Empty sections render nothing
    } else if (sectionValue is List) {
      // Render for each item in the list
      for (final item in sectionValue) {
        final itemContext = Map<String, dynamic>.from(context);
        if (item is Map<String, dynamic>) {
          itemContext.addAll(item);
        } else {
          itemContext['.'] = item; // Current item accessor
        }
        final rendered = await renderAsync(sectionTokens, itemContext,
            currentDirectory: _currentDirectory);
        buffer.write(rendered);
      }
    } else if (sectionValue is Map<String, dynamic>) {
      // Render with the map as additional context
      final mapContext = Map<String, dynamic>.from(context);
      mapContext.addAll(sectionValue);
      final rendered = await renderAsync(sectionTokens, mapContext,
          currentDirectory: _currentDirectory);
      buffer.write(rendered);
    } else {
      // Truthy value: render once
      final rendered = await renderAsync(sectionTokens, context,
          currentDirectory: _currentDirectory);
      buffer.write(rendered);
    }

    return AsyncSectionRenderResult(buffer.toString(), endIndex + 1);
  }

  /// Renders an inverted section asynchronously.
  Future<AsyncSectionRenderResult> _renderInvertedSectionAsync(
      List<Token> tokens, int startIndex, Map<String, dynamic> context) async {
    final startToken = tokens[startIndex];
    final sectionName = startToken.metadata?['sectionName'] as String?;

    if (sectionName == null) {
      throw TemplateException.parsing('Missing section name',
          position: startToken.position);
    }

    // Find section tokens (same logic as regular section)
    final sectionTokens = <Token>[];
    var nestLevel = 0;
    var endIndex = startIndex + 1;

    while (endIndex < tokens.length) {
      final token = tokens[endIndex];

      if (token.type == TokenType.sectionStart ||
          token.type == TokenType.invertedSection) {
        nestLevel++;
        sectionTokens.add(token);
      } else if (token.type == TokenType.sectionEnd) {
        if (nestLevel == 0 && token.content == sectionName) {
          break;
        } else if (nestLevel > 0) {
          nestLevel--;
          sectionTokens.add(token);
        }
      } else {
        sectionTokens.add(token);
      }

      endIndex++;
    }

    // Resolve the section value
    final sectionValue = _resolveVariable(
      Token.variable(sectionName, startToken.position, metadata: {
        'path': sectionName.split('.'),
      }),
      context,
    );

    String content = '';

    // Render only if value is falsy or empty
    if (sectionValue == null ||
        sectionValue == false ||
        (sectionValue is List && sectionValue.isEmpty) ||
        (sectionValue is Map && sectionValue.isEmpty) ||
        (sectionValue is String && sectionValue.isEmpty)) {
      content = await renderAsync(sectionTokens, context,
          currentDirectory: _currentDirectory);
    }

    return AsyncSectionRenderResult(content, endIndex + 1);
  }

  /// Formats output value for rendering.
  String _formatOutput(dynamic value, {required bool escape}) {
    if (value == null) {
      return '';
    }

    final stringValue = value.toString();

    if (escape) {
      return _escapeHtmlString(stringValue);
    }

    return stringValue;
  }

  /// Renders a partial template asynchronously.
  ///
  /// [token] is the partial token containing the partial name.
  /// [context] is the current rendering context (inherited by partial).
  ///
  /// Returns the rendered partial content, or null if partial cannot be loaded.
  /// Throws [TemplateException] if partial loading fails.
  Future<String?> _renderPartialAsync(
      Token token, Map<String, dynamic> context) async {
    if (_partialLoader == null) {
      throw TemplateException.rendering(
        'Partial loader not configured, cannot render partial: ${token.content}',
      );
    }

    if (_currentDirectory == null) {
      throw TemplateException.rendering(
        'Current directory not set, cannot resolve partial: ${token.content}',
      );
    }

    try {
      // Load the partial content
      final partialContent = _partialLoader!.loadPartial(
        token.content,
        _currentDirectory!,
      );

      // Create a new lexer for the partial
      final lexer = Lexer();
      final partialTokens = lexer.tokenize(partialContent);

      // Recursively render the partial with the same context
      final partialRenderer = AsyncRenderer(
        _functionRegistry,
        _fallbacks,
        partialLoader: _partialLoader,
        escapeHtml: _escapeHtml,
      );

      return await partialRenderer.renderAsync(
        partialTokens,
        context,
        currentDirectory: _currentDirectory,
      );
    } on TemplateException {
      rethrow;
    } catch (e) {
      throw TemplateException.rendering(
        'Failed to render partial ${token.content}: $e',
        cause: e,
      );
    }
  }

  /// Escapes HTML special characters.
  String _escapeHtmlString(String input) {
    return input
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&#x27;');
  }
}

/// Result of rendering an async section.
class AsyncSectionRenderResult {
  /// The rendered content of the section.
  final String content;

  /// The next token index to continue processing from.
  final int nextIndex;

  AsyncSectionRenderResult(this.content, this.nextIndex);
}
