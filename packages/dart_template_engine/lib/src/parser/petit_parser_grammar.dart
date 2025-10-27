import 'package:petitparser/petitparser.dart' hide Token;
import 'token.dart';

/// Simple and working PetitParser grammar for Mustache templates
class MustacheGrammarDefinition extends GrammarDefinition {
  @override
  Parser start() => ref0(template).end();

  /// Template is a sequence of elements
  Parser template() => ref0(element).star();

  /// An element is either text or a mustache expression
  Parser element() => ref0(mustacheExpr) | ref0(textElement);

  /// Text element - any characters until we hit {{
  Parser textElement() =>
      (string('{{').not() & any()).plus().flatten().map((text) => {
            'type': 'text',
            'content': text,
          });

  /// Mustache expressions
  Parser mustacheExpr() => ref0(tripleMustache) | ref0(doubleMustache);

  /// Triple mustache {{{...}}}
  Parser tripleMustache() => (string('{{{') &
          string('}}}').neg().star().flatten().trim() &
          string('}}}'))
      .map((values) => {
            'type': 'unescaped',
            'content': _parseInnerContent(values[1]),
          });

  /// Double mustache {{...}}
  Parser doubleMustache() =>
      (string('{{') & string('}}').neg().star().flatten().trim() & string('}}'))
          .map((values) => {
                'type': 'escaped',
                'content': _parseInnerContent(values[1]),
              });

  /// Parse inner content from string
  Map<String, dynamic> _parseInnerContent(String content) {
    final trimmed = content.trim();

    // Comment: ! comment
    if (trimmed.startsWith('!')) {
      return {
        'type': 'comment',
        'content': trimmed.substring(1).trim(),
      };
    }

    // Partial: > name
    if (trimmed.startsWith('>')) {
      return {
        'type': 'partial',
        'content': trimmed.substring(1).trim(),
      };
    }

    // Section start: # name
    if (trimmed.startsWith('#')) {
      final name = trimmed.substring(1).trim();
      return {
        'type': 'sectionStart',
        'content': name,
        'metadata': {'sectionName': name},
      };
    }

    // Section end: / name
    if (trimmed.startsWith('/')) {
      return {
        'type': 'sectionEnd',
        'content': trimmed.substring(1).trim(),
      };
    }

    // Inverted section: ^ name
    if (trimmed.startsWith('^')) {
      final name = trimmed.substring(1).trim();
      return {
        'type': 'invertedSection',
        'content': name,
        'metadata': {'sectionName': name},
      };
    }

    // Function call: @helper(...) or object.method(...)
    if (trimmed.contains('(') && trimmed.endsWith(')')) {
      return _parseFunctionCall(trimmed);
    }

    // Variable: name or object.property
    return {
      'type': 'variable',
      'content': trimmed,
      'metadata': {'path': trimmed.split('.')},
    };
  }

  /// Parse function call from string
  Map<String, dynamic> _parseFunctionCall(String content) {
    final parenIndex = content.indexOf('(');
    if (parenIndex == -1) {
      return {
        'type': 'variable',
        'content': content,
        'metadata': {'path': content.split('.')},
      };
    }

    final functionName = content.substring(0, parenIndex).trim();
    final argsString =
        content.substring(parenIndex + 1, content.length - 1).trim();
    final isHelper = functionName.startsWith('@');

    return {
      'type': 'functionCall',
      'functionName': functionName,
      'arguments': _parseSimpleArgs(argsString),
      'isHelper': isHelper,
      'content': content,
    };
  }

  /// Simple argument parsing with nested function call support
  List<dynamic> _parseSimpleArgs(String argsString) {
    if (argsString.isEmpty) return [];

    final args = <dynamic>[];
    final parts = _splitArguments(argsString);

    for (final part in parts) {
      final trimmed = part.trim();

      // String literal
      if ((trimmed.startsWith("'") && trimmed.endsWith("'")) ||
          (trimmed.startsWith('"') && trimmed.endsWith('"'))) {
        args.add(trimmed.substring(1, trimmed.length - 1));
      }
      // Number
      else if (RegExp(r'^-?\d+(\.\d+)?$').hasMatch(trimmed)) {
        args.add(
            trimmed.contains('.') ? double.parse(trimmed) : int.parse(trimmed));
      }
      // Boolean
      else if (trimmed == 'true' || trimmed == 'false') {
        args.add(trimmed == 'true');
      }
      // Function call (nested)
      else if (trimmed.contains('(') && trimmed.endsWith(')')) {
        final funcCall = _parseFunctionCall(trimmed);
        args.add({
          'type': 'function',
          'functionName': funcCall['functionName'],
          'arguments': funcCall['arguments'],
          'isHelper': funcCall['isHelper'],
        });
      }
      // Variable reference
      else {
        args.add({
          'type': 'variable',
          'path': trimmed.split('.'),
        });
      }
    }

    return args;
  }

  /// Split arguments respecting nested parentheses
  List<String> _splitArguments(String argsString) {
    final parts = <String>[];
    var current = '';
    var parenDepth = 0;
    var inString = false;
    var stringChar = '';

    for (int i = 0; i < argsString.length; i++) {
      final char = argsString[i];

      if (!inString) {
        if (char == '"' || char == "'") {
          inString = true;
          stringChar = char;
        } else if (char == '(') {
          parenDepth++;
        } else if (char == ')') {
          parenDepth--;
        } else if (char == ',' && parenDepth == 0) {
          parts.add(current.trim());
          current = '';
          continue;
        }
      } else {
        if (char == stringChar) {
          inString = false;
          stringChar = '';
        }
      }

      current += char;
    }

    if (current.trim().isNotEmpty) {
      parts.add(current.trim());
    }

    return parts;
  }
}

/// Template parser using PetitParser
class MustacheTemplateParser {
  final MustacheGrammarDefinition _grammar = MustacheGrammarDefinition();
  late final Parser _parser;

  MustacheTemplateParser() {
    _parser = _grammar.build();
  }

  /// Parse template and return tokens
  List<Token> parse(String template) {
    final result = _parser.parse(template);

    if (result is Failure) {
      throw Exception('Parse failed: ${result.message} at ${result.position}');
    }

    return _convertToTokens(result.value, template);
  }

  /// Convert AST to tokens
  List<Token> _convertToTokens(List elements, String template) {
    final tokens = <Token>[];
    var pos = 0;

    for (final element in elements) {
      if (element is Map<String, dynamic>) {
        final token = _createToken(element, pos);
        tokens.add(token);
        pos = _nextPosition(pos, element, template);
      }
    }

    return tokens;
  }

  /// Create token from element
  Token _createToken(Map<String, dynamic> element, int pos) {
    final type = element['type'] as String;
    final content = element['content'];

    switch (type) {
      case 'text':
        return Token.text(content as String, pos);
      case 'escaped':
        if (content is Map<String, dynamic>) {
          return _createMustacheToken(content, pos, false);
        }
        return Token.text(content?.toString() ?? '', pos);
      case 'unescaped':
        if (content is Map<String, dynamic>) {
          return _createMustacheToken(content, pos, true);
        }
        return Token.text(content?.toString() ?? '', pos);
      default:
        return Token.text(content?.toString() ?? '', pos);
    }
  }

  /// Create mustache token from inner content
  Token _createMustacheToken(
      Map<String, dynamic> inner, int pos, bool unescaped) {
    final type = inner['type'] as String;
    final content = inner['content'];
    final metadata = inner['metadata'] as Map<String, dynamic>?;

    // Handle content that might be a string or another map
    String contentStr;
    if (content is String) {
      contentStr = content;
    } else if (content is Map<String, dynamic>) {
      contentStr = content['content'] as String? ?? '';
    } else {
      contentStr = content?.toString() ?? '';
    }

    switch (type) {
      case 'variable':
        return unescaped
            ? Token.unescapedVariable(contentStr, pos, metadata: metadata)
            : Token.variable(contentStr, pos, metadata: metadata);
      case 'sectionStart':
        return Token.sectionStart(contentStr, pos, metadata: metadata);
      case 'sectionEnd':
        return Token.sectionEnd(contentStr, pos);
      case 'invertedSection':
        return Token.invertedSection(contentStr, pos, metadata: metadata);
      case 'comment':
        return Token.comment(contentStr, pos);
      case 'partial':
        return Token.partial(contentStr, pos);
      case 'functionCall':
        return Token.functionCall(contentStr, pos,
            metadata: _extractFunctionMetadata(inner, unescaped: unescaped));
      default:
        return Token.text(contentStr, pos);
    }
  }

  /// Extract function metadata
  Map<String, dynamic> _extractFunctionMetadata(Map<String, dynamic> inner,
      {bool unescaped = false}) {
    return {
      'functionName': inner['functionName'],
      'arguments': inner['arguments'] ?? [],
      'isHelper': inner['isHelper'] ?? false,
      'unescaped': unescaped,
    };
  }

  /// Calculate next position
  int _nextPosition(
      int current, Map<String, dynamic> element, String template) {
    final type = element['type'] as String;
    final content = element['content'];

    switch (type) {
      case 'text':
        final textContent = content as String;
        return current + textContent.length;
      case 'escaped':
        if (content is Map<String, dynamic>) {
          final innerContent = content['content'] as String? ?? '';
          return current + innerContent.length + 4; // {{}}
        }
        return current + 4;
      case 'unescaped':
        if (content is Map<String, dynamic>) {
          final innerContent = content['content'] as String? ?? '';
          return current + innerContent.length + 6; // {{{}}}
        }
        return current + 6;
      default:
        return current + 10; // Default safe increment
    }
  }
}
