import 'token.dart';
import '../exceptions/template_exception.dart';

/// A fast lexer that tokenizes template strings in a single pass.
///
/// This lexer is optimized for speed using pre-compiled regular expressions
/// and minimal string allocations. It processes templates character by character
/// with efficient lookahead for mustache expressions.
///
/// ## Performance Features:
/// - Single-pass parsing
/// - Pre-compiled regex patterns
/// - Minimal string allocations
/// - Efficient character-by-character processing
/// - Fast mustache expression detection
///
/// ## Example:
/// ```dart
/// final lexer = Lexer();
/// final tokens = lexer.tokenize('Hello {{@uppercase(name)}}!');
/// ```
class Lexer {
  // Pre-compiled regex patterns for maximum performance
  static final RegExp _sectionStartPattern = RegExp(r'^#\s*(.+)$');
  static final RegExp _sectionEndPattern = RegExp(r'^/\s*(.+)$');
  static final RegExp _invertedSectionPattern = RegExp(r'^\^\s*(.+)$');
  static final RegExp _commentPattern = RegExp(r'^!\s*(.*)$');
  static final RegExp _partialPattern = RegExp(r'^>\s*(.+)$');
  static final RegExp _functionCallPattern = RegExp(
    r'^(@?\w+(?:\.\w+)*)\s*\(',
  );
  // Argument parsing patterns
  static final RegExp _stringPattern = RegExp(r"^'([^']*)'|^" '"([^"]*)"');
  static final RegExp _numberPattern = RegExp(r'^-?\d+(?:\.\d+)?');
  static final RegExp _booleanPattern = RegExp(r'^(true|false)');
  static final RegExp _variablePattern =
      RegExp(r'^[a-zA-Z_]\w*(?:\.[a-zA-Z_]\w*)*');

  /// Tokenizes a template string into a list of tokens.
  ///
  /// [template] is the template string to tokenize.
  ///
  /// Returns a list of tokens representing the parsed template.
  /// Throws [TemplateException] if tokenization fails.
  List<Token> tokenize(String template) {
    final tokens = <Token>[];
    final length = template.length;
    var position = 0;

    while (position < length) {
      // Look for mustache expressions
      final mustacheStart = template.indexOf('{{', position);

      if (mustacheStart == -1) {
        // No more mustache expressions, add remaining text
        if (position < length) {
          final textContent = template.substring(position);
          if (textContent.isNotEmpty) {
            tokens.add(Token.text(textContent, position));
          }
        }
        break;
      }

      // Add text content before mustache expression
      if (mustacheStart > position) {
        final textContent = template.substring(position, mustacheStart);
        tokens.add(Token.text(textContent, position));
      }

      // Parse mustache expression
      final mustacheResult = _parseMustacheExpression(template, mustacheStart);
      tokens.add(mustacheResult.token);
      position = mustacheResult.nextPosition;
    }

    return tokens;
  }

  /// Parses a mustache expression starting at the given position.
  _MustacheParseResult _parseMustacheExpression(String template, int startPos) {
    final length = template.length;

    // Check for triple mustache {{{...}}}
    if (startPos + 2 < length &&
        template.substring(startPos, startPos + 3) == '{{{') {
      final endPos = template.indexOf('}}}', startPos + 3);
      if (endPos == -1) {
        throw TemplateException.parsing(
          'Unclosed triple mustache expression',
          position: startPos,
        );
      }

      final content = template.substring(startPos + 3, endPos).trim();
      final token = _parseUnescapedVariable(content, startPos);
      return _MustacheParseResult(token, endPos + 3);
    }

    // Check for double mustache {{...}}
    if (startPos + 1 < length &&
        template.substring(startPos, startPos + 2) == '{{') {
      final endPos = template.indexOf('}}', startPos + 2);
      if (endPos == -1) {
        throw TemplateException.parsing(
          'Unclosed mustache expression',
          position: startPos,
        );
      }

      final content = template.substring(startPos + 2, endPos).trim();
      final token = _parseMustacheContent(content, startPos);
      return _MustacheParseResult(token, endPos + 2);
    }

    throw TemplateException.parsing(
      'Invalid mustache expression',
      position: startPos,
    );
  }

  /// Parses the content inside mustache braces.
  Token _parseMustacheContent(String content, int position) {
    if (content.isEmpty) {
      throw TemplateException.parsing(
        'Empty mustache expression',
        position: position,
      );
    }

    // Check for section start: #section
    final sectionStartMatch = _sectionStartPattern.firstMatch(content);
    if (sectionStartMatch != null) {
      final sectionName = sectionStartMatch.group(1)!.trim();
      return Token.sectionStart(sectionName, position, metadata: {
        'sectionName': sectionName,
      });
    }

    // Check for section end: /section
    final sectionEndMatch = _sectionEndPattern.firstMatch(content);
    if (sectionEndMatch != null) {
      final sectionName = sectionEndMatch.group(1)!.trim();
      return Token.sectionEnd(sectionName, position);
    }

    // Check for inverted section: ^section
    final invertedSectionMatch = _invertedSectionPattern.firstMatch(content);
    if (invertedSectionMatch != null) {
      final sectionName = invertedSectionMatch.group(1)!.trim();
      return Token.invertedSection(sectionName, position, metadata: {
        'sectionName': sectionName,
      });
    }

    // Check for comment: ! comment
    final commentMatch = _commentPattern.firstMatch(content);
    if (commentMatch != null) {
      final commentText = commentMatch.group(1) ?? '';
      return Token.comment(commentText, position);
    }

    // Check for partial: > partial
    final partialMatch = _partialPattern.firstMatch(content);
    if (partialMatch != null) {
      final partialName = partialMatch.group(1)!.trim();
      return Token.partial(partialName, position);
    }

    // Check for function call: @helper(args) or object.method(args)
    final functionCallMatch = _functionCallPattern.firstMatch(content);
    if (functionCallMatch != null) {
      final functionName = functionCallMatch.group(1)!;
      final isHelper = content.startsWith('@');

      // Find the matching closing parenthesis
      final openParenIndex = content.indexOf('(');
      if (openParenIndex != -1) {
        final argsString = _extractBalancedParentheses(content, openParenIndex);
        if (argsString != null) {
          return Token.functionCall(content, position, metadata: {
            'functionName': functionName,
            'arguments': _parseArguments(argsString),
            'isHelper': isHelper,
          });
        }
      }
    }

    // Default to variable
    return Token.variable(content, position, metadata: {
      'path': _parseVariablePath(content),
    });
  }

  /// Parses an unescaped variable or function call.
  Token _parseUnescapedVariable(String content, int position) {
    if (content.isEmpty) {
      throw TemplateException.parsing(
        'Empty unescaped expression',
        position: position,
      );
    }

    // Check for comment: ! comment
    if (content.startsWith('!')) {
      return Token.comment(content.substring(1).trim(), position);
    }

    // Check for partial: > partial_name
    if (content.startsWith('>')) {
      final partialName = content.substring(1).trim();
      return Token.partial(partialName, position);
    }

    // Check for function call: @function() or object.method()
    final functionMatch = _functionCallPattern.firstMatch(content);
    if (functionMatch != null) {
      final isHelper = content.startsWith('@');
      final functionName = functionMatch.group(1)!;

      // Find the matching closing parenthesis
      final openParenIndex = content.indexOf('(');
      if (openParenIndex != -1) {
        final argsString = _extractBalancedParentheses(content, openParenIndex);
        if (argsString != null) {
          return Token.functionCall(content, position, metadata: {
            'functionName': functionName,
            'arguments': _parseArguments(argsString),
            'isHelper': isHelper,
            'unescaped': true, // Mark as unescaped function call
          });
        }
      }
    }

    // Otherwise, it's an unescaped variable
    return Token.unescapedVariable(content, position, metadata: {
      'path': _parseVariablePath(content),
    });
  }

  /// Parses a variable path like "user.name.first" into a list of parts.
  List<String> _parseVariablePath(String path) {
    return path
        .split('.')
        .map((part) => part.trim())
        .where((part) => part.isNotEmpty)
        .toList();
  }

  /// Parses function arguments from a string efficiently.
  List<dynamic> _parseArguments(String argsString) {
    if (argsString.trim().isEmpty) {
      return [];
    }

    final args = <dynamic>[];
    final trimmed = argsString.trim();
    var position = 0;

    while (position < trimmed.length) {
      // Skip whitespace and commas
      while (position < trimmed.length &&
          (trimmed[position] == ' ' ||
              trimmed[position] == ',' ||
              trimmed[position] == '\t')) {
        position++;
      }

      if (position >= trimmed.length) break;

      // Try to parse different argument types
      final remaining = trimmed.substring(position);

      // String literals
      final stringMatch = _stringPattern.firstMatch(remaining);
      if (stringMatch != null) {
        final stringValue = stringMatch.group(1) ?? stringMatch.group(2) ?? '';
        args.add(stringValue);
        position += stringMatch.group(0)!.length;
        continue;
      }

      // Numbers
      final numberMatch = _numberPattern.firstMatch(remaining);
      if (numberMatch != null) {
        final numberStr = numberMatch.group(0)!;
        if (numberStr.contains('.')) {
          args.add(double.parse(numberStr));
        } else {
          args.add(int.parse(numberStr));
        }
        position += numberStr.length;
        continue;
      }

      // Booleans
      final booleanMatch = _booleanPattern.firstMatch(remaining);
      if (booleanMatch != null) {
        final boolStr = booleanMatch.group(1)!;
        args.add(boolStr == 'true');
        position += boolStr.length;
        continue;
      }

      // Function calls (nested functions)
      final functionMatch = _functionCallPattern.firstMatch(remaining);
      if (functionMatch != null) {
        final isHelper = remaining.startsWith('@');
        final functionName = functionMatch.group(1)!;

        // Find the matching closing parenthesis
        final openParenIndex = remaining.indexOf('(');
        if (openParenIndex != -1) {
          final argsString =
              _extractBalancedParentheses(remaining, openParenIndex);
          if (argsString != null) {
            final matchedLength = openParenIndex +
                1 +
                argsString.length +
                1; // function( + args + )

            args.add({
              'type': 'function',
              'functionName': functionName,
              'arguments': _parseArguments(argsString),
              'isHelper': isHelper,
            });
            position += matchedLength;
            continue;
          }
        }
      }

      // Variable references
      final variableMatch = _variablePattern.firstMatch(remaining);
      if (variableMatch != null) {
        final variablePath = variableMatch.group(0)!;
        args.add({
          'type': 'variable',
          'path': variablePath.split('.'),
        });
        position += variablePath.length;
        continue;
      }

      // If we get here, we couldn't parse the argument
      final previewLength = remaining.length > 10 ? 10 : remaining.length;
      throw TemplateException.parsing(
        'Invalid argument syntax: ${remaining.substring(0, previewLength)}...',
        position: position,
      );
    }

    return args;
  }

  /// Extracts content between balanced parentheses starting at the given index.
  /// Returns the content inside the parentheses or null if parentheses are not balanced.
  String? _extractBalancedParentheses(String text, int startIndex) {
    if (startIndex >= text.length || text[startIndex] != '(') {
      return null;
    }

    var depth = 0;
    var endIndex = startIndex;

    for (var i = startIndex; i < text.length; i++) {
      final char = text[i];
      if (char == '(') {
        depth++;
      } else if (char == ')') {
        depth--;
        if (depth == 0) {
          endIndex = i;
          break;
        }
      }
    }

    if (depth != 0) {
      // Unbalanced parentheses
      return null;
    }

    // Return content between parentheses (excluding the parentheses themselves)
    return text.substring(startIndex + 1, endIndex);
  }
}

/// Result of parsing a mustache expression.
class _MustacheParseResult {
  final Token token;
  final int nextPosition;

  _MustacheParseResult(this.token, this.nextPosition);
}
