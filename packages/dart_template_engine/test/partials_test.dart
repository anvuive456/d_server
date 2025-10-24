import 'dart:io';
import 'package:test/test.dart';
import 'package:path/path.dart' as path;
import '../lib/dart_template_engine.dart';

void main() {
  group('Partials Tests', () {
    late Directory tempDir;
    late String templateDir;
    late DartTemplateEngine engine;

    setUp(() {
      // Create temporary directory for test templates
      tempDir =
          Directory.systemTemp.createTempSync('dart_template_engine_test_');
      templateDir = tempDir.path;
      engine = DartTemplateEngine(baseDirectory: templateDir);
    });

    tearDown(() {
      // Clean up temporary directory
      tempDir.deleteSync(recursive: true);
    });

    void createTemplateFile(String relativePath, String content) {
      final filePath = path.join(templateDir, '$relativePath.html.dt');
      final file = File(filePath);
      file.parent.createSync(recursive: true);
      file.writeAsStringSync(content);
    }

    group('Basic Partial Loading', () {
      test('should render simple partial', () {
        createTemplateFile('main', 'Hello {{> greeting}}!');
        createTemplateFile('greeting', 'World');

        final result = engine.render('main', {});
        expect(result, equals('Hello World!'));
      });

      test('should render partial with context', () {
        createTemplateFile('main', 'Hello {{> greeting}}!');
        createTemplateFile('greeting', '{{name}}');

        final result = engine.render('main', {'name': 'Alice'});
        expect(result, equals('Hello Alice!'));
      });

      test('should render partial with variables and functions', () {
        createTemplateFile('main', 'Result: {{> calculation}}');
        createTemplateFile('calculation', '{{@add(a, b)}} = {{result}}');

        final result = engine.render('main', {'a': 5, 'b': 3, 'result': 8});
        expect(result, equals('Result: 8 = 8'));
      });
    });

    group('Nested Partials', () {
      test('should render nested partials', () {
        createTemplateFile(
            'main', 'Page: {{> header}} {{> body}} {{> footer}}');
        createTemplateFile('header', '<h1>{{title}}</h1>');
        createTemplateFile('body', '<p>{{> content}}</p>');
        createTemplateFile('content', '{{message}}');
        createTemplateFile('footer', '<small>{{copyright}}</small>');

        final result = engine.render('main', {
          'title': 'Test Page',
          'message': 'Hello World',
          'copyright': '2024'
        });

        expect(
            result,
            equals(
                'Page: <h1>Test Page</h1> <p>Hello World</p> <small>2024</small>'));
      });

      test('should handle deep nesting', () {
        createTemplateFile('main', '{{> level1}}');
        createTemplateFile('level1', 'L1:{{> level2}}');
        createTemplateFile('level2', 'L2:{{> level3}}');
        createTemplateFile('level3', 'L3:{{value}}');

        final result = engine.render('main', {'value': 'deep'});
        expect(result, equals('L1:L2:L3:deep'));
      });
    });

    group('Directory Structure', () {
      test('should find partial in same directory', () {
        // Create subdirectory structure
        createTemplateFile('users/show', 'User: {{> _user_card}}');
        createTemplateFile('users/_user_card', '{{name}} ({{email}})');

        final result = engine.render(
            'users/show', {'name': 'John Doe', 'email': 'john@example.com'});

        expect(result, equals('User: John Doe (john@example.com)'));
      });

      test('should find partial in subdirectory', () {
        // Create nested structure
        createTemplateFile('pages/home', 'Welcome {{> components/_hero}}');
        createTemplateFile('pages/components/_hero', '<h1>{{title}}</h1>');

        final result = engine.render('pages/home', {'title': 'Homepage'});
        expect(result, equals('Welcome <h1>Homepage</h1>'));
      });

      test('should find partial in nested subdirectory', () {
        createTemplateFile('main', 'Content: {{> shared/_layout}}');
        createTemplateFile('shared/_layout', '<div>{{content}}</div>');

        final result = engine.render('main', {'content': 'Test'});
        expect(result, equals('Content: <div>Test</div>'));
      });
    });

    group('Partial Context Inheritance', () {
      test('should inherit full context from parent', () {
        createTemplateFile('main', '{{> info}}');
        createTemplateFile('info', 'Name: {{user.name}}, Age: {{user.age}}');

        final result = engine.render('main', {
          'user': {'name': 'Alice', 'age': 30}
        });

        expect(result, equals('Name: Alice, Age: 30'));
      });

      test('should inherit sections context', () {
        createTemplateFile('main', '{{#users}}{{> _user_item}}{{/users}}');
        createTemplateFile('_user_item', '- {{name}} ({{role}})\n');

        final result = engine.render('main', {
          'users': [
            {'name': 'Alice', 'role': 'Admin'},
            {'name': 'Bob', 'role': 'User'}
          ]
        });

        expect(result, equals('- Alice (Admin)\n- Bob (User)\n'));
      });

      test('should access parent context in nested partials', () {
        createTemplateFile('main', '{{#items}}{{> _item}}{{/items}}');
        createTemplateFile('_item', '{{name}}: {{> _details}}\n');
        createTemplateFile('_details', '{{description}} (\${{price}})');

        final result = engine.render('main', {
          'items': [
            {'name': 'Item1', 'description': 'First item', 'price': 10},
            {'name': 'Item2', 'description': 'Second item', 'price': 20}
          ]
        });

        expect(result,
            equals('Item1: First item (\$10)\nItem2: Second item (\$20)\n'));
      });
    });

    group('Error Handling', () {
      test('should throw error when partial not found', () {
        createTemplateFile('main', 'Hello {{> missing_partial}}!');

        expect(
            () => engine.render('main', {}),
            throwsA(isA<TemplateException>().having(
                (e) => e.toString(),
                'message',
                contains('Partial not found: missing_partial.html.dt'))));
      });

      test('should throw error when partial file is corrupted', () {
        createTemplateFile('main', 'Hello {{> broken}}!');

        // Create a file with unclosed mustache expression
        final filePath = path.join(templateDir, 'broken.html.dt');
        final file = File(filePath);
        file.writeAsStringSync('{{unclosed');

        // This should throw an error due to unclosed mustache
        expect(
            () => engine.render('main', {}),
            throwsA(isA<TemplateException>().having((e) => e.toString(),
                'message', contains('Unclosed mustache expression'))));
      });

      test('should provide clear error messages for nested partial failures',
          () {
        createTemplateFile('main', '{{> level1}}');
        createTemplateFile('level1', '{{> missing}}');

        expect(
            () => engine.render('main', {}),
            throwsA(isA<TemplateException>().having((e) => e.toString(),
                'message', contains('Partial not found: missing.html.dt'))));
      });
    });

    group('Partial with Functions and Methods', () {
      test('should render partials with helper functions', () {
        createTemplateFile('main', '{{> greeting}}');
        createTemplateFile('greeting', 'Hello {{@uppercase(name)}}!');

        final result = engine.render('main', {'name': 'world'});
        expect(result, equals('Hello WORLD!'));
      });

      test('should render partials with instance methods', () {
        createTemplateFile('main', '{{> user_info}}');
        createTemplateFile('user_info', 'User: {{user.toString()}}');

        final user = TestUser('Alice');
        final result = engine.render('main', {'user': user});
        expect(result, equals('User: TestUser(Alice)'));
      });

      test('should handle async functions in partials', () async {
        engine.registerAsyncFunction('loadData', (args) async {
          await Future.delayed(Duration(milliseconds: 10));
          return 'loaded: ${args[0]}';
        });

        createTemplateFile('main', '{{> data_section}}');
        createTemplateFile('data_section', 'Data: {{@loadData(key)}}');

        final result = await engine.renderAsync('main', {'key': 'test'});
        expect(result, equals('Data: loaded: test'));
      });
    });

    group('Complex Scenarios', () {
      test('should render complex layout with multiple partials', () {
        createTemplateFile('layouts/application', '''<!DOCTYPE html>
<html>
<head>{{> _head}}</head>
<body>{{> _header}}{{content}}{{> _footer}}</body>
</html>''');

        createTemplateFile('layouts/_head', '<title>{{title}}</title>');
        createTemplateFile('layouts/_header', '<nav>{{site_name}}</nav>');
        createTemplateFile('layouts/_footer', '<footer>{{copyright}}</footer>');

        createTemplateFile('pages/home', 'Welcome to {{> _hero}}');
        createTemplateFile('pages/_hero', '<h1>{{hero_title}}</h1>');

        // Simulate layout rendering
        final pageContent =
            engine.render('pages/home', {'hero_title': 'Our Site'});
        final fullPage = engine.render('layouts/application', {
          'title': 'Home Page',
          'site_name': 'Test Site',
          'copyright': '2024 Test Corp',
          'content': pageContent
        });

        expect(fullPage, contains('<title>Home Page</title>'));
        expect(fullPage, contains('<nav>Test Site</nav>'));
        expect(fullPage, contains('Welcome to &lt;h1&gt;Our Site&lt;/h1&gt;'));
        expect(fullPage, contains('<footer>2024 Test Corp</footer>'));
      });

      test('should handle partials with sections and conditionals', () {
        createTemplateFile(
            'main', '''{{#show_header}}{{> _header}}{{/show_header}}
{{#items}}{{> _item}}{{/items}}
{{^items}}{{> _empty}}{{/items}}''');

        createTemplateFile('_header', '<h1>{{title}}</h1>\n');
        createTemplateFile('_item', '- {{name}}\n');
        createTemplateFile('_empty', 'No items found.\n');

        // Test with items
        final result1 = engine.render('main', {
          'show_header': true,
          'title': 'Items List',
          'items': [
            {'name': 'Item 1'},
            {'name': 'Item 2'}
          ]
        });

        expect(
            result1, equals('<h1>Items List</h1>\n\n- Item 1\n- Item 2\n\n'));

        // Test without items
        final result2 =
            engine.render('main', {'show_header': false, 'items': []});

        expect(result2, equals('\n\nNo items found.\n'));
      });
    });

    group('Cache Behavior', () {
      test('should cache and clear partial content', () {
        createTemplateFile('main', '{{> cached_partial}}');
        createTemplateFile('cached_partial', 'Cached content');

        // First render to populate cache
        final result1 = engine.render('main', {});
        expect(result1, equals('Cached content'));

        // Verify cache has content
        final statsBefore = engine.getPartialCacheStats();
        expect(statsBefore['cached_partials'], greaterThan(0));

        // Clear cache
        engine.clearPartialCache();

        // Verify cache is cleared
        final statsAfter = engine.getPartialCacheStats();
        expect(statsAfter['cached_partials'], equals(0));

        // Should still render correctly after cache clear
        final result2 = engine.render('main', {});
        expect(result2, equals('Cached content'));
      });

      test('should provide cache statistics', () {
        createTemplateFile('main', '{{> partial1}} {{> partial2}}');
        createTemplateFile('partial1', 'P1');
        createTemplateFile('partial2', 'P2');

        engine.render('main', {});

        final stats = engine.getPartialCacheStats();
        expect(stats['cached_partials'], equals(2));
        expect(stats['cached_items'], hasLength(2));
      });
    });
  });
}

/// Test helper class for method invocation tests
class TestUser {
  final String name;

  TestUser(this.name);

  @override
  String toString() => 'TestUser($name)';

  String getName() => name;
  String getGreeting(String prefix) => '$prefix $name';
}
