import 'dart:io';
import 'package:dart_template_engine/dart_template_engine.dart';

void main() {
  print('🚀 Dart Template Engine Performance Benchmark\n');

  // Create temp directory for engine
  final tempDir = Directory.systemTemp.createTempSync('benchmark_');
  final engine = DartTemplateEngine(baseDirectory: tempDir.path);
  final parser = TemplateParser();
  final lexer = Lexer();

  try {
    // Test templates of varying complexity
    runParsingBenchmarks(parser, lexer);
    runRenderingBenchmarks(engine);
    runComparisonBenchmarks(engine);
  } finally {
    // Clean up
    tempDir.deleteSync(recursive: true);
  }
}

void runParsingBenchmarks(TemplateParser parser, Lexer lexer) {
  print('📊 PARSING BENCHMARKS');
  print('=' * 50);

  // Simple template
  final simpleTemplate = 'Hello {{name}}! Welcome to {{site}}.';
  benchmarkParsing('Simple Template', simpleTemplate, parser, lexer);

  // Complex template with functions
  final complexTemplate = '''
  <html>
    <head><title>{{@uppercase(title)}}</title></head>
    <body>
      <h1>{{@capitalize(heading)}}</h1>
      <p>Published on {{@formatDate(date, 'MMM dd, yyyy')}}</p>
      {{#users}}
        <div class="user">
          <h3>{{user.getName()}}</h3>
          <p>{{@lowercase(user.email)}}</p>
          <span>Joined: {{@formatDate(user.createdAt, 'yyyy-MM-dd')}}</span>
        </div>
      {{/users}}
      {{^users}}
        <p>No users found</p>
      {{/users}}
    </body>
  </html>
  ''';
  benchmarkParsing('Complex Template', complexTemplate, parser, lexer);

  // Large template
  final buffer = StringBuffer();
  for (int i = 0; i < 1000; i++) {
    buffer.write(
        'Item {{item$i}}: {{@uppercase(name$i)}} - {{user$i.getName()}} ');
  }
  final largeTemplate = buffer.toString();
  benchmarkParsing(
      'Large Template (1000 expressions)', largeTemplate, parser, lexer);

  print('');
}

void benchmarkParsing(
    String name, String template, TemplateParser parser, Lexer lexer) {
  const iterations = 1000;

  // Warm up
  for (int i = 0; i < 10; i++) {
    parser.parse(template);
    lexer.tokenize(template);
  }

  // Benchmark parser
  final parserStopwatch = Stopwatch()..start();
  for (int i = 0; i < iterations; i++) {
    parser.parse(template);
  }
  parserStopwatch.stop();

  // Benchmark lexer directly
  final lexerStopwatch = Stopwatch()..start();
  for (int i = 0; i < iterations; i++) {
    lexer.tokenize(template);
  }
  lexerStopwatch.stop();

  final parserAvg = parserStopwatch.elapsedMicroseconds / iterations;
  final lexerAvg = lexerStopwatch.elapsedMicroseconds / iterations;
  final templateSize = template.length;
  final tokensPerSec =
      (iterations * 1000000) ~/ parserStopwatch.elapsedMicroseconds;

  print('$name:');
  print('  Template size: ${templateSize} chars');
  print('  Parser avg:    ${parserAvg.toStringAsFixed(2)} μs/parse');
  print('  Lexer avg:     ${lexerAvg.toStringAsFixed(2)} μs/parse');
  print('  Throughput:    $tokensPerSec parses/sec');
  print(
      '  Speed:         ${(templateSize * tokensPerSec / 1024 / 1024).toStringAsFixed(2)} MB/sec');
  print('');
}

void runRenderingBenchmarks(DartTemplateEngine engine) {
  print('🎨 RENDERING BENCHMARKS');
  print('=' * 50);

  // Simple rendering
  final simpleTemplate =
      'Hello {{name}}! You have {{@add(messages, notifications)}} notifications.';
  final simpleContext = {
    'name': 'John Doe',
    'messages': 5,
    'notifications': 3,
  };
  benchmarkRendering('Simple Rendering', simpleTemplate, simpleContext, engine);

  // Complex rendering with objects
  final user = TestUser('Jane Smith', 'jane@example.com');
  final complexTemplate = '''
  <div class="profile">
    <h1>{{@uppercase(user.getName())}}</h1>
    <p>Email: {{@lowercase(user.getEmail())}}</p>
    <p>Joined: {{@formatDate(user.getJoinDate(), 'MMM dd, yyyy')}}</p>
    {{#user.isActive()}}
      <span class="status active">Active</span>
    {{/user.isActive()}}
    {{^user.isActive()}}
      <span class="status inactive">Inactive</span>
    {{/user.isActive()}}
  </div>
  ''';
  final complexContext = {'user': user};
  benchmarkRendering(
      'Complex Rendering', complexTemplate, complexContext, engine);

  // List rendering
  final users = List.generate(
      100,
      (i) => {
            'name': 'User $i',
            'email': 'user$i@example.com',
            'active': i % 2 == 0,
          });
  final listTemplate = '''
  <ul>
    {{#users}}
      <li class="{{^active}}inactive{{/active}}">
        {{@capitalize(name)}} - {{@lowercase(email)}}
      </li>
    {{/users}}
  </ul>
  ''';
  final listContext = {'users': users};
  benchmarkRendering(
      'List Rendering (100 items)', listTemplate, listContext, engine);

  print('');
}

void benchmarkRendering(String name, String template,
    Map<String, dynamic> context, DartTemplateEngine engine) {
  const iterations = 1000;

  // Warm up
  for (int i = 0; i < 10; i++) {
    engine.renderString(template, context);
  }

  // Benchmark
  final stopwatch = Stopwatch()..start();
  for (int i = 0; i < iterations; i++) {
    engine.renderString(template, context);
  }
  stopwatch.stop();

  final avg = stopwatch.elapsedMicroseconds / iterations;
  final rendersPerSec = (iterations * 1000000) ~/ stopwatch.elapsedMicroseconds;
  final result = engine.renderString(template, context);

  print('$name:');
  print('  Template size: ${template.length} chars');
  print('  Output size:   ${result.length} chars');
  print('  Avg time:      ${avg.toStringAsFixed(2)} μs/render');
  print('  Throughput:    $rendersPerSec renders/sec');
  print('');
}

void runComparisonBenchmarks(DartTemplateEngine engine) {
  print('⚡ COMPARISON BENCHMARKS');
  print('=' * 50);

  final template = '''
  <div>
    <h1>{{title}}</h1>
    <p>{{@uppercase(description)}}</p>
    <ul>
      {{#items}}
        <li>{{@capitalize(name)}} - {{@formatDate(date, 'yyyy-MM-dd')}}</li>
      {{/items}}
    </ul>
  </div>
  ''';

  final context = {
    'title': 'My Template',
    'description': 'this is a test template',
    'items': List.generate(
        50,
        (i) => {
              'name': 'item $i',
              'date': DateTime.now().subtract(Duration(days: i)),
            }),
  };

  print('Template complexity test:');
  print('  Functions: @uppercase, @capitalize, @formatDate');
  print('  Sections: #items loop with 50 items');
  print('  Template size: ${template.length} chars');
  print('');

  // Parse-only benchmark
  final parser = TemplateParser();
  const parseIterations = 5000;

  final parseStopwatch = Stopwatch()..start();
  for (int i = 0; i < parseIterations; i++) {
    parser.parse(template);
  }
  parseStopwatch.stop();

  // Full render benchmark
  const renderIterations = 1000;

  final renderStopwatch = Stopwatch()..start();
  for (int i = 0; i < renderIterations; i++) {
    engine.renderString(template, context);
  }
  renderStopwatch.stop();

  final parseTime = parseStopwatch.elapsedMicroseconds / parseIterations;
  final renderTime = renderStopwatch.elapsedMicroseconds / renderIterations;
  final totalTime = parseTime + renderTime;

  print('Performance breakdown:');
  print(
      '  Parse time:    ${parseTime.toStringAsFixed(2)} μs (${(parseTime / totalTime * 100).toStringAsFixed(1)}%)');
  print(
      '  Render time:   ${renderTime.toStringAsFixed(2)} μs (${(renderTime / totalTime * 100).toStringAsFixed(1)}%)');
  print('  Total time:    ${totalTime.toStringAsFixed(2)} μs');
  print('');

  print('Throughput:');
  print(
      '  Parse only:    ${(parseIterations * 1000000 ~/ parseStopwatch.elapsedMicroseconds)} parses/sec');
  print(
      '  Full render:   ${(renderIterations * 1000000 ~/ renderStopwatch.elapsedMicroseconds)} renders/sec');
  print('');

  // Memory usage estimation
  final result = engine.renderString(template, context);
  print('Output:');
  print('  Input size:    ${template.length} chars');
  print('  Output size:   ${result.length} chars');
  print(
      '  Expansion:     ${(result.length / template.length).toStringAsFixed(2)}x');
  print('');

  print('🏁 Benchmark completed!');
}

// Test helper class for benchmarking
class TestUser {
  final String name;
  final String email;
  final DateTime joinDate;
  final bool active;

  TestUser(this.name, this.email, {DateTime? joinDate, this.active = true})
      : joinDate = joinDate ?? DateTime.now();

  String getName() => name;
  String getEmail() => email;
  DateTime getJoinDate() => joinDate;
  bool isActive() => active;
}
