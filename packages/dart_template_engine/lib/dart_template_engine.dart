/// A powerful template engine for Dart with Mustache-like syntax and support for function calls.
///
/// This library provides a file-based template engine that extends Mustache syntax with:
/// - File-based template loading with .html.dt extension
/// - Function calls: `{{@uppercase(name)}}`
/// - Instance method calls: `{{user.getName()}}`
/// - Partial support: `{{> partial_name}}`
/// - Async function support with fallback
/// - Built-in helper functions
/// - Custom function registration
///
/// ## Basic Usage
///
/// ```dart
/// import 'package:dart_template_engine/dart_template_engine.dart';
///
/// final engine = DartTemplateEngine(baseDirectory: '/app/templates');
///
/// // Renders /app/templates/users/show.html.dt
/// final result = engine.render('users/show', {'name': 'World'});
///
/// // Using helper functions in templates
/// // Template content: Hello {{@uppercase(name)}}!
/// final result2 = engine.render('greeting', {'name': 'world'});
/// print(result2); // Hello WORLD!
///
/// // Using partials
/// // main.html.dt: Welcome {{> _header}}
/// // _header.html.dt: <h1>{{title}}</h1>
/// final result3 = engine.render('main', {'title': 'Homepage'});
/// print(result3); // Welcome <h1>Homepage</h1>
/// ```
///
/// ## Advanced Features
///
/// ```dart
/// // Register custom functions
/// engine.registerFunction('double', (args) => (args[0] as num) * 2);
///
/// // Register async functions
/// engine.registerAsyncFunction('loadUser', (args) async {
///   return await userService.getUser(args[0]);
/// });
///
/// // Async rendering
/// final result = await engine.renderAsync('user_profile', {'userId': 123});
/// ```
library dart_template_engine;

export 'src/dart_template_engine.dart';
export 'src/exceptions/template_exception.dart';
export 'src/functions/function_registry.dart';
export 'src/partials/partial_loader.dart';
export 'src/parser/token.dart';
export 'src/parser/template_parser.dart';
export 'src/parser/lexer.dart';
