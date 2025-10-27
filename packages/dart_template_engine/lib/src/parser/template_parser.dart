import 'package:petitparser/petitparser.dart' hide Token;
import 'token.dart';
import 'petit_parser_grammar.dart';
import '../exceptions/template_exception.dart';

/// A high-performance template parser that converts template strings into tokens.
///
/// This parser uses PetitParser for robust parsing with proper error handling
/// and recovery. It supports both basic Mustache syntax and extended function
/// call syntax with full AST generation capabilities.
///
/// ## Performance Features:
/// - PetitParser combinator-based parsing
/// - Rich AST generation for LSP support
/// - Proper error recovery and reporting
/// - Position tracking for debugging
/// - Extensible grammar definition
///
/// ## Supported Syntax:
/// - Variables: `{{variable}}`, `{{object.property}}`
/// - Functions: `{{@helper(args)}}`, `{{object.method(args)}}`
/// - Sections: `{{#section}}...{{/section}}`
/// - Inverted sections: `{{^section}}...{{/section}}`
/// - Comments: `{{! comment }}`
/// - Partials: `{{> partial}}`
/// - Unescaped: `{{{variable}}}`
///
/// ## Example:
/// ```dart
/// final parser = TemplateParser();
/// final tokens = parser.parse('Hello {{@uppercase(name)}}!');
/// ```
class TemplateParser {
  final MustacheTemplateParser _parser = MustacheTemplateParser();

  /// Parses a template string into a list of tokens.
  ///
  /// [template] is the template string to parse.
  ///
  /// Returns a list of tokens representing the parsed template.
  /// Throws [TemplateException] if parsing fails.
  List<Token> parse(String template) {
    try {
      final tokens = _parser.parse(template);
      _validateTokenStructure(tokens);
      return tokens;
    } catch (e) {
      if (e is TemplateException) {
        rethrow;
      }
      throw TemplateException.parsing('Template parsing failed: $e', cause: e);
    }
  }

  /// Validates the token structure for proper nesting and syntax.
  void _validateTokenStructure(List<Token> tokens) {
    final sectionStack = <String>[];

    for (var i = 0; i < tokens.length; i++) {
      final token = tokens[i];

      switch (token.type) {
        case TokenType.sectionStart:
        case TokenType.invertedSection:
          final sectionName = token.metadata?['sectionName'] as String?;
          if (sectionName == null) {
            throw TemplateException.parsing(
              'Section missing name',
              position: token.position,
            );
          }
          sectionStack.add(sectionName);
          break;

        case TokenType.sectionEnd:
          if (sectionStack.isEmpty) {
            throw TemplateException.parsing(
              'Unexpected section end: ${token.content}',
              position: token.position,
            );
          }

          final expectedSection = sectionStack.removeLast();
          if (expectedSection != token.content) {
            throw TemplateException.parsing(
              'Section mismatch: expected $expectedSection, got ${token.content}',
              position: token.position,
            );
          }
          break;

        case TokenType.functionCall:
          _validateFunctionCall(token);
          break;

        default:
          // Other token types don't need validation
          break;
      }
    }

    // Check for unclosed sections
    if (sectionStack.isNotEmpty) {
      throw TemplateException.parsing(
        'Unclosed sections: ${sectionStack.join(', ')}',
      );
    }
  }

  /// Validates a function call token.
  void _validateFunctionCall(Token token) {
    final functionName = token.metadata?['functionName'] as String?;
    final arguments = token.metadata?['arguments'] as List<dynamic>?;

    if (functionName == null) {
      throw TemplateException.parsing(
        'Function call missing name',
        position: token.position,
      );
    }

    if (arguments == null) {
      throw TemplateException.parsing(
        'Function call missing arguments metadata',
        position: token.position,
      );
    }

    // Validate function name format
    if (functionName.isEmpty) {
      throw TemplateException.parsing(
        'Empty function name',
        position: token.position,
      );
    }

    // For helper functions, ensure they start with @
    final isHelper = token.metadata?['isHelper'] as bool? ?? false;
    if (isHelper && !functionName.startsWith('@')) {
      throw TemplateException.parsing(
        'Helper function must start with @: $functionName',
        position: token.position,
      );
    }

    // For method calls, ensure they have at least one dot
    if (!isHelper && !functionName.contains('.')) {
      throw TemplateException.parsing(
        'Method call must contain object reference: $functionName',
        position: token.position,
      );
    }
  }

  /// Parses template and returns statistics about the parsing process.
  ///
  /// This is useful for debugging and performance analysis.
  ParseResult parseWithStats(String template) {
    final stopwatch = Stopwatch()..start();
    final tokens = parse(template);
    stopwatch.stop();

    final stats = ParseStats(
      tokenCount: tokens.length,
      parseTimeMs: stopwatch.elapsedMilliseconds,
      templateLength: template.length,
      textTokens: tokens.where((t) => t.type == TokenType.text).length,
      variableTokens: tokens.where((t) => t.type == TokenType.variable).length,
      functionCallTokens:
          tokens.where((t) => t.type == TokenType.functionCall).length,
      sectionTokens:
          tokens.where((t) => t.type == TokenType.sectionStart).length,
    );

    return ParseResult(tokens, stats);
  }
}

/// Result of parsing with statistics.
class ParseResult {
  final List<Token> tokens;
  final ParseStats stats;

  ParseResult(this.tokens, this.stats);
}

/// Statistics about the parsing process.
class ParseStats {
  final int tokenCount;
  final int parseTimeMs;
  final int templateLength;
  final int textTokens;
  final int variableTokens;
  final int functionCallTokens;
  final int sectionTokens;

  ParseStats({
    required this.tokenCount,
    required this.parseTimeMs,
    required this.templateLength,
    required this.textTokens,
    required this.variableTokens,
    required this.functionCallTokens,
    required this.sectionTokens,
  });

  @override
  String toString() {
    return 'ParseStats(tokens: $tokenCount, time: ${parseTimeMs}ms, '
        'template: ${templateLength}chars, text: $textTokens, '
        'vars: $variableTokens, funcs: $functionCallTokens, '
        'sections: $sectionTokens)';
  }
}
