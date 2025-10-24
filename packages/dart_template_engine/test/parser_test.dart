import 'package:test/test.dart';
import 'package:dart_template_engine/dart_template_engine.dart';

void main() {
  group('Lexer', () {
    late Lexer lexer;

    setUp(() {
      lexer = Lexer();
    });

    test('should tokenize plain text', () {
      final tokens = lexer.tokenize('Hello World!');
      expect(tokens.length, equals(1));
      expect(tokens[0].type, equals(TokenType.text));
      expect(tokens[0].content, equals('Hello World!'));
    });

    test('should tokenize simple variable', () {
      final tokens = lexer.tokenize('Hello {{name}}!');
      expect(tokens.length, equals(3));
      expect(tokens[0].type, equals(TokenType.text));
      expect(tokens[0].content, equals('Hello '));
      expect(tokens[1].type, equals(TokenType.variable));
      expect(tokens[1].content, equals('name'));
      expect(tokens[2].type, equals(TokenType.text));
      expect(tokens[2].content, equals('!'));
    });

    test('should tokenize nested property access', () {
      final tokens = lexer.tokenize('{{user.name.first}}');
      expect(tokens.length, equals(1));
      expect(tokens[0].type, equals(TokenType.variable));
      expect(tokens[0].content, equals('user.name.first'));
      expect(tokens[0].metadata?['path'], equals(['user', 'name', 'first']));
    });

    test('should tokenize unescaped variable', () {
      final tokens = lexer.tokenize('{{{content}}}');
      expect(tokens.length, equals(1));
      expect(tokens[0].type, equals(TokenType.unescapedVariable));
      expect(tokens[0].content, equals('content'));
    });

    test('should tokenize section start', () {
      final tokens = lexer.tokenize('{{#users}}');
      expect(tokens.length, equals(1));
      expect(tokens[0].type, equals(TokenType.sectionStart));
      expect(tokens[0].content, equals('users'));
      expect(tokens[0].metadata?['sectionName'], equals('users'));
    });

    test('should tokenize section end', () {
      final tokens = lexer.tokenize('{{/users}}');
      expect(tokens.length, equals(1));
      expect(tokens[0].type, equals(TokenType.sectionEnd));
      expect(tokens[0].content, equals('users'));
    });

    test('should tokenize inverted section', () {
      final tokens = lexer.tokenize('{{^empty}}');
      expect(tokens.length, equals(1));
      expect(tokens[0].type, equals(TokenType.invertedSection));
      expect(tokens[0].content, equals('empty'));
      expect(tokens[0].metadata?['sectionName'], equals('empty'));
    });

    test('should tokenize comments', () {
      final tokens = lexer.tokenize('{{! This is a comment }}');
      expect(tokens.length, equals(1));
      expect(tokens[0].type, equals(TokenType.comment));
      expect(tokens[0].content, equals('This is a comment'));
    });

    test('should tokenize partials', () {
      final tokens = lexer.tokenize('{{> header}}');
      expect(tokens.length, equals(1));
      expect(tokens[0].type, equals(TokenType.partial));
      expect(tokens[0].content, equals('header'));
    });

    test('should tokenize helper function call', () {
      final tokens = lexer.tokenize('{{@uppercase(name)}}');
      expect(tokens.length, equals(1));
      expect(tokens[0].type, equals(TokenType.functionCall));
      expect(tokens[0].metadata?['functionName'], equals('@uppercase'));
      expect(tokens[0].metadata?['isHelper'], equals(true));
      expect(tokens[0].metadata?['arguments'], hasLength(1));
      expect(tokens[0].metadata?['arguments'][0]['type'], equals('variable'));
      expect(tokens[0].metadata?['arguments'][0]['path'], equals(['name']));
    });

    test('should tokenize method call', () {
      final tokens = lexer.tokenize('{{user.getName()}}');
      expect(tokens.length, equals(1));
      expect(tokens[0].type, equals(TokenType.functionCall));
      expect(tokens[0].metadata?['functionName'], equals('user.getName'));
      expect(tokens[0].metadata?['isHelper'], equals(false));
      expect(tokens[0].metadata?['arguments'], hasLength(0));
    });

    test('should parse function arguments correctly', () {
      final tokens =
          lexer.tokenize("{{@test('string', 42, true, variable, obj.prop)}}");
      expect(tokens.length, equals(1));

      final args = tokens[0].metadata?['arguments'] as List<dynamic>;
      expect(args, hasLength(5));

      // String argument
      expect(args[0], equals('string'));

      // Number argument
      expect(args[1], equals(42));

      // Boolean argument
      expect(args[2], equals(true));

      // Variable argument
      expect(args[3]['type'], equals('variable'));
      expect(args[3]['path'], equals(['variable']));

      // Object property argument
      expect(args[4]['type'], equals('variable'));
      expect(args[4]['path'], equals(['obj', 'prop']));
    });

    test('should handle mixed content', () {
      final tokens =
          lexer.tokenize('Hello {{name}}! {{#users}}User: {{name}}{{/users}}');
      expect(tokens.length, equals(7));

      expect(tokens[0].type, equals(TokenType.text));
      expect(tokens[0].content, equals('Hello '));

      expect(tokens[1].type, equals(TokenType.variable));
      expect(tokens[1].content, equals('name'));

      expect(tokens[2].type, equals(TokenType.text));
      expect(tokens[2].content, equals('! '));

      expect(tokens[3].type, equals(TokenType.sectionStart));
      expect(tokens[3].content, equals('users'));

      expect(tokens[4].type, equals(TokenType.text));
      expect(tokens[4].content, equals('User: '));

      expect(tokens[5].type, equals(TokenType.variable));
      expect(tokens[5].content, equals('name'));

      expect(tokens[6].type, equals(TokenType.sectionEnd));
      expect(tokens[6].content, equals('users'));
    });

    test('should throw error for unclosed mustache', () {
      expect(
        () => lexer.tokenize('Hello {{name'),
        throwsA(isA<TemplateException>()),
      );
    });

    test('should throw error for unclosed triple mustache', () {
      expect(
        () => lexer.tokenize('Hello {{{content'),
        throwsA(isA<TemplateException>()),
      );
    });

    test('should throw error for empty mustache', () {
      expect(
        () => lexer.tokenize('Hello {{}}'),
        throwsA(isA<TemplateException>()),
      );
    });
  });

  group('TemplateParser', () {
    late TemplateParser parser;

    setUp(() {
      parser = TemplateParser();
    });

    test('should parse simple template', () {
      final tokens = parser.parse('Hello {{name}}!');
      expect(tokens.length, equals(3));
      expect(tokens[1].type, equals(TokenType.variable));
    });

    test('should validate section nesting', () {
      final tokens = parser.parse('{{#section}}content{{/section}}');
      expect(tokens.length, equals(3));
      expect(tokens[0].type, equals(TokenType.sectionStart));
      expect(tokens[2].type, equals(TokenType.sectionEnd));
    });

    test('should throw error for mismatched sections', () {
      expect(
        () => parser.parse('{{#users}}content{{/posts}}'),
        throwsA(isA<TemplateException>()),
      );
    });

    test('should throw error for unclosed section', () {
      expect(
        () => parser.parse('{{#users}}content'),
        throwsA(isA<TemplateException>()),
      );
    });

    test('should throw error for unexpected section end', () {
      expect(
        () => parser.parse('content{{/users}}'),
        throwsA(isA<TemplateException>()),
      );
    });

    test('should validate function calls', () {
      final tokens = parser.parse('{{@uppercase(name)}}');
      expect(tokens.length, equals(1));
      expect(tokens[0].type, equals(TokenType.functionCall));
    });

    test('should throw error for invalid helper function format', () {
      expect(
        () => parser.parse('{{uppercase(name)}}'), // Missing @
        throwsA(isA<TemplateException>()),
      );
    });

    test('should parse with stats', () {
      final result =
          parser.parseWithStats('Hello {{name}}! {{@uppercase(title)}}');

      expect(result.tokens.length, equals(4));
      expect(result.stats.tokenCount, equals(4));
      expect(result.stats.templateLength, equals(37));
      expect(result.stats.textTokens, equals(2));
      expect(result.stats.variableTokens, equals(1));
      expect(result.stats.functionCallTokens, equals(1));
      expect(result.stats.parseTimeMs, greaterThanOrEqualTo(0));
    });

    test('should handle complex nested sections', () {
      final template = '''
      {{#users}}
        <div>{{name}}</div>
        {{#posts}}
          <p>{{title}}</p>
          {{^comments}}
            No comments
          {{/comments}}
        {{/posts}}
      {{/users}}
      ''';

      final tokens = parser.parse(template);

      // Should not throw any validation errors
      expect(tokens.length, greaterThan(0));

      // Check section balance
      final sectionStarts = tokens
          .where((t) =>
              t.type == TokenType.sectionStart ||
              t.type == TokenType.invertedSection)
          .length;
      final sectionEnds =
          tokens.where((t) => t.type == TokenType.sectionEnd).length;

      expect(sectionStarts, equals(sectionEnds));
    });

    test('should handle performance test', () {
      // Create a large template
      final buffer = StringBuffer();
      for (int i = 0; i < 1000; i++) {
        buffer.write('Item {{item$i}} ');
      }
      final largeTemplate = buffer.toString();

      final stopwatch = Stopwatch()..start();
      final tokens = parser.parse(largeTemplate);
      stopwatch.stop();

      expect(tokens.length,
          equals(2001)); // 1000 "Item " + 1000 variables + 1 trailing space
      expect(stopwatch.elapsedMilliseconds, lessThan(100)); // Should be fast
    });
  });

  group('Token', () {
    test('should create text token', () {
      final token = Token.text('Hello', 0);
      expect(token.type, equals(TokenType.text));
      expect(token.content, equals('Hello'));
      expect(token.position, equals(0));
      expect(token.hasOutput, isTrue);
      expect(token.isMustacheExpression, isFalse);
    });

    test('should create variable token', () {
      final token = Token.variable('name', 5, metadata: {
        'path': ['name']
      });
      expect(token.type, equals(TokenType.variable));
      expect(token.content, equals('name'));
      expect(token.position, equals(5));
      expect(token.hasOutput, isTrue);
      expect(token.isMustacheExpression, isTrue);
    });

    test('should create function call token', () {
      final token = Token.functionCall('@test()', 10, metadata: {
        'functionName': '@test',
        'arguments': [],
        'isHelper': true,
      });
      expect(token.type, equals(TokenType.functionCall));
      expect(token.hasOutput, isTrue);
      expect(token.isMustacheExpression, isTrue);
    });

    test('should create section tokens', () {
      final startToken = Token.sectionStart('users', 0);
      final endToken = Token.sectionEnd('users', 20);

      expect(startToken.type, equals(TokenType.sectionStart));
      expect(startToken.isSection, isTrue);
      expect(startToken.hasOutput, isFalse);

      expect(endToken.type, equals(TokenType.sectionEnd));
      expect(endToken.isSection, isTrue);
      expect(endToken.hasOutput, isFalse);
    });

    test('should compare tokens correctly', () {
      final token1 = Token.text('Hello', 0);
      final token2 = Token.text('Hello', 0);
      final token3 = Token.text('World', 0);

      expect(token1, equals(token2));
      expect(token1, isNot(equals(token3)));
    });

    test('should generate correct string representation', () {
      final token = Token.variable('name', 5, metadata: {
        'path': ['name']
      });
      final str = token.toString();

      expect(str, contains('Token('));
      expect(str, contains('type: TokenType.variable'));
      expect(str, contains('content: "name"'));
      expect(str, contains('position: 5'));
      expect(str, contains('metadata: {path: [name]}'));
    });
  });
}
