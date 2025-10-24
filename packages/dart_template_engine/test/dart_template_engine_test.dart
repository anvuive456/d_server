import 'dart:io';
import 'package:test/test.dart';
import 'package:dart_template_engine/dart_template_engine.dart';

void main() {
  group('DartTemplateEngine', () {
    late DartTemplateEngine engine;
    late Directory tempDir;

    setUp(() {
      tempDir =
          Directory.systemTemp.createTempSync('dart_template_engine_test_');
      engine = DartTemplateEngine(baseDirectory: tempDir.path);
    });

    tearDown(() {
      tempDir.deleteSync(recursive: true);
    });

    test('should render basic text', () {
      final result = engine.renderString('Hello World!', {});
      expect(result, equals('Hello World!'));
    });

    test('should render simple variable', () {
      final result = engine.renderString('Hello {{name}}!', {'name': 'World'});
      expect(result, equals('Hello World!'));
    });

    test('should handle missing variables', () {
      final result = engine.renderString('Hello {{missing}}!', {});
      expect(result, equals('Hello !'));
    });

    test('should render nested properties', () {
      final result = engine.renderString('{{user.name}}', {
        'user': {'name': 'Alice'}
      });
      expect(result, equals('Alice'));
    });

    test('should call built-in uppercase helper', () {
      final result =
          engine.renderString('{{@uppercase(name)}}', {'name': 'hello'});
      expect(result, equals('HELLO'));
    });

    test('should call built-in lowercase helper', () {
      final result =
          engine.renderString('{{@lowercase(name)}}', {'name': 'WORLD'});
      expect(result, equals('world'));
    });

    test('should call built-in capitalize helper', () {
      final result =
          engine.renderString('{{@capitalize(name)}}', {'name': 'john doe'});
      expect(result, equals('John doe'));
    });

    test('should call built-in add helper', () {
      final result = engine.renderString('{{@add(a, b)}}', {'a': 5, 'b': 3});
      expect(result, equals('8'));
    });

    test('should call built-in default helper', () {
      final result = engine.renderString('{{@default(value, "fallback")}}', {});
      expect(result, equals('fallback'));
    });
    test('should register and call custom function', () {
      engine.registerFunction('double', (args) => (args[0] as num) * 2);
      final result = engine.renderString('{{@double(value)}}', {'value': 5});
      expect(result, equals('10'));
    });

    test('should handle function with multiple arguments', () {
      engine.registerFunction('concat', (args) => '${args[0]}-${args[1]}');
      final result = engine.renderString(
          '{{@concat(first, second)}}', {'first': 'hello', 'second': 'world'});
      expect(result, equals('hello-world'));
    });

    test('should render sections with lists', () {
      final result = engine.renderString('{{#users}}{{name}} {{/users}}', {
        'users': [
          {'name': 'John'},
          {'name': 'Jane'},
        ]
      });
      expect(result, equals('John Jane '));
    });

    test('should render inverted sections', () {
      final result =
          engine.renderString('{{^users}}No users{{/users}}', {'users': []});
      expect(result, equals('No users'));
    });

    test('should handle comments', () {
      final result =
          engine.renderString('Hello{{! this is a comment}} World', {});
      expect(result, equals('Hello World'));
    });

    test('should escape HTML by default', () {
      final result = engine.renderString(
          '{{content}}', {'content': '<script>alert("xss")</script>'});
      expect(result,
          equals('&lt;script&gt;alert(&quot;xss&quot;)&lt;/script&gt;'));
    });

    test('should not escape unescaped variables', () {
      final result = engine.renderString('{{{html}}}', {'html': '<b>bold</b>'});
      expect(result, equals('<b>bold</b>'));
    });
  });

  group('DartTemplateEngine - Async Functions', () {
    late DartTemplateEngine engine;
    late Directory tempDir;

    setUp(() {
      tempDir =
          Directory.systemTemp.createTempSync('dart_template_engine_test_');
      engine = DartTemplateEngine(baseDirectory: tempDir.path);
    });

    tearDown() {
      tempDir.deleteSync(recursive: true);
    }

    test('should render with async functions', () async {
      engine.registerAsyncFunction('loadData', (args) async {
        await Future.delayed(Duration(milliseconds: 10));
        return 'loaded: ${args[0]}';
      });

      final result =
          await engine.renderStringAsync('{{@loadData(key)}}', {'key': 'test'});
      expect(result, equals('loaded: test'));
    });

    test('should use fallback when async function fails', () async {
      final tempDir2 =
          Directory.systemTemp.createTempSync('dart_template_engine_test_');
      final engine = DartTemplateEngine(
          baseDirectory: tempDir2.path,
          fallbacks: {'failingFunction': 'fallback'});

      engine.registerAsyncFunction('failingFunction', (args) async {
        throw Exception('Function failed');
      });

      final result =
          await engine.renderStringAsync('{{@failingFunction()}}', {});
      expect(result, equals('fallback'));

      tempDir2.deleteSync(recursive: true);
    });

    test('should handle mixed sync and async rendering', () async {
      engine.registerAsyncFunction('asyncData', (args) async {
        return 'async-${args[0]}';
      });

      final result = await engine.renderStringAsync(
          '{{@uppercase(name)}} - {{@asyncData(id)}}',
          {'name': 'hello', 'id': 123});
      expect(result, equals('HELLO - async-123'));
    });
  });

  group('DartTemplateEngine - Method Invocation', () {
    late DartTemplateEngine engine;
    late Directory tempDir;

    setUp(() {
      tempDir =
          Directory.systemTemp.createTempSync('dart_template_engine_test_');
      engine = DartTemplateEngine(baseDirectory: tempDir.path);
    });

    tearDown() {
      tempDir.deleteSync(recursive: true);
    }

    test('should call instance methods', () {
      final user = TestUser('John Doe');
      final result = engine.renderString('{{user.getName()}}', {'user': user});
      expect(result, equals('John Doe'));
    });

    test('should call instance methods with arguments', () {
      final user = TestUser('John');
      final result = engine.renderString(
          '{{user.getGreeting(prefix)}}', {'user': user, 'prefix': 'Hello'});
      expect(result, equals('Hello John'));
    });

    test('should access instance properties', () {
      final user = TestUser('Charlie');
      final result = engine.renderString('{{user.name}}', {'user': user});
      expect(result, equals('Charlie'));
    });
  });

  group('DartTemplateEngine - Error Handling', () {
    late DartTemplateEngine engine;
    late Directory tempDir;

    setUp(() {
      tempDir =
          Directory.systemTemp.createTempSync('dart_template_engine_test_');
      engine = DartTemplateEngine(baseDirectory: tempDir.path);
    });

    tearDown() {
      tempDir.deleteSync(recursive: true);
    }

    test('should throw exception for unknown function', () {
      expect(
        () => engine.renderString('{{@unknownFunction()}}', {}),
        throwsA(isA<TemplateException>()),
      );
    });

    test('should throw exception for invalid method call', () {
      expect(
        () => engine.renderString('{{obj.invalidMethod()}}', {'obj': 'string'}),
        throwsA(isA<TemplateException>()),
      );
    });

    test('should throw exception for unclosed section', () {
      expect(
        () => engine.renderString('{{#section}}unclosed', {}),
        throwsA(isA<TemplateException>()),
      );
    });
  });

  group('FunctionRegistry', () {
    late FunctionRegistry registry;

    setUp(() {
      registry = FunctionRegistry();
    });

    test('should register and call sync functions', () {
      registry.registerFunction('test', (args) => 'result');
      expect(registry.hasFunction('test'), isTrue);
      expect(registry.callFunction('test', []), equals('result'));
    });

    test('should register and call async functions', () async {
      registry.registerAsyncFunction(
          'asyncTest', (args) async => 'async result');
      expect(registry.hasAsyncFunction('asyncTest'), isTrue);
      final result = await registry.callAsyncFunction('asyncTest', []);
      expect(result, equals('async result'));
    });

    test('should prevent duplicate function names', () {
      registry.registerFunction('duplicate', (args) => 'first');
      expect(
        () => registry.registerFunction('duplicate', (args) => 'second'),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('should unregister functions', () {
      registry.registerFunction('temp', (args) => 'temp');
      expect(registry.hasFunction('temp'), isTrue);

      final removed = registry.unregisterFunction('temp');
      expect(removed, isTrue);
      expect(registry.hasFunction('temp'), isFalse);
    });
  });
}

// Test helper class
class TestUser {
  final String name;

  TestUser(this.name);

  String getName() => name;

  String getGreeting(String prefix) => '$prefix $name';
}
