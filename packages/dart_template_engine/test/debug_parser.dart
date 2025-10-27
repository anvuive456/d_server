import 'package:dart_template_engine/src/parser/petit_parser_grammar.dart';

void main() {
  final parser = MustacheTemplateParser();

  print('=== Testing simple text ===');
  try {
    final tokens = parser.parse('Hello World');
    print('Tokens found: ${tokens.length}');
    for (int i = 0; i < tokens.length; i++) {
      final token = tokens[i];
      print(
          'Token $i: ${token.type} - "${token.content}" at position ${token.position}');
    }
  } catch (e, stack) {
    print('Error: $e');
    print('Stack: $stack');
  }

  print('\n=== Testing simple variable ===');
  try {
    // First let's see raw parser output
    final grammar = MustacheGrammarDefinition();
    final rawParser = grammar.build();
    final rawResult = rawParser.parse('{{name}}');
    print('Raw parser result: ${rawResult.value}');
    if (rawResult.value is List) {
      final list = rawResult.value as List;
      for (int i = 0; i < list.length; i++) {
        print('  Raw item $i: ${list[i]} (${list[i].runtimeType})');
        if (list[i] is Map) {
          final map = list[i] as Map;
          print('    Type: ${map['type']}');
          print(
              '    Content: ${map['content']} (${map['content'].runtimeType})');
          if (map['content'] is Map) {
            final innerMap = map['content'] as Map;
            print('      Inner type: ${innerMap['type']}');
            print('      Inner content: ${innerMap['content']}');
            print('      Inner metadata: ${innerMap['metadata']}');
          }
        }
      }
    }

    final tokens = parser.parse('{{name}}');
    print('Tokens found: ${tokens.length}');
    for (int i = 0; i < tokens.length; i++) {
      final token = tokens[i];
      print(
          'Token $i: ${token.type} - "${token.content}" at position ${token.position}');
      if (token.metadata != null) {
        print('  Metadata: ${token.metadata}');
      }
    }
  } catch (e, stack) {
    print('Error: $e');
    print('Stack: $stack');
  }

  print('\n=== Testing mixed content ===');
  try {
    final tokens = parser.parse('Hello {{name}}!');
    print('Tokens found: ${tokens.length}');
    for (int i = 0; i < tokens.length; i++) {
      final token = tokens[i];
      print(
          'Token $i: ${token.type} - "${token.content}" at position ${token.position}');
      if (token.metadata != null) {
        print('  Metadata: ${token.metadata}');
      }
    }
  } catch (e, stack) {
    print('Error: $e');
    print('Stack: $stack');
  }

  print('\n=== Testing section ===');
  try {
    final tokens = parser.parse('{{#items}}Hello{{/items}}');
    print('Tokens found: ${tokens.length}');
    for (int i = 0; i < tokens.length; i++) {
      final token = tokens[i];
      print(
          'Token $i: ${token.type} - "${token.content}" at position ${token.position}');
      if (token.metadata != null) {
        print('  Metadata: ${token.metadata}');
      }
    }
  } catch (e, stack) {
    print('Error: $e');
    print('Stack: $stack');
  }
}
