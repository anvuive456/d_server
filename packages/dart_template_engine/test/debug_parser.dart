import 'package:dart_template_engine/dart_template_engine.dart';

void main() {
  final lexer = Lexer();

  // Test case 1: Mixed content
  print('=== Test 1: Mixed content ===');
  final template1 = 'Hello {{name}}! {{#users}}User: {{name}}{{/users}}';
  print('Template: $template1');
  final tokens1 = lexer.tokenize(template1);
  print('Token count: ${tokens1.length}');
  for (int i = 0; i < tokens1.length; i++) {
    print('  $i: ${tokens1[i].type} - "${tokens1[i].content}"');
  }

  // Test case 2: Parse with stats
  print('\n=== Test 2: Parse with stats ===');
  final template2 = 'Hello {{name}}! {{@uppercase(title)}}';
  print('Template: $template2');
  print('Length: ${template2.length}');
  final tokens2 = lexer.tokenize(template2);
  print('Token count: ${tokens2.length}');
  for (int i = 0; i < tokens2.length; i++) {
    print('  $i: ${tokens2[i].type} - "${tokens2[i].content}"');
  }

  // Test case 3: Performance test
  print('\n=== Test 3: Performance test (first 10 items) ===');
  final buffer = StringBuffer();
  for (int i = 0; i < 10; i++) {
    buffer.write('Item {{item$i}} ');
  }
  final template3 = buffer.toString();
  print('Template: $template3');
  print('Length: ${template3.length}');
  final tokens3 = lexer.tokenize(template3);
  print('Token count: ${tokens3.length}');
  for (int i = 0; i < tokens3.length; i++) {
    print('  $i: ${tokens3[i].type} - "${tokens3[i].content}"');
  }
}
