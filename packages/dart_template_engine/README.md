# Dart Template Engine

A powerful template engine for Dart with Mustache-like syntax and support for function calls and method invocation.

## Features

- **Mustache-compatible syntax** - Supports standard Mustache templates
- **Function calls** - Call helper functions with `{{@helper(args)}}`
- **Method invocation** - Call object methods with `{{object.method(args)}}`
- **Async support** - Async functions with fallback handling
- **Built-in helpers** - String, date, math, and collection helpers
- **Custom functions** - Register your own sync and async functions
- **HTML escaping** - Automatic HTML escaping (configurable)
- **Fast parsing** - Optimized single-pass parser
- **Type safety** - Runtime type checking with reflection

## Installation

Add this to your package's `pubspec.yaml` file:

```yaml
dependencies:
  dart_template_engine: ^1.0.0
```

Or if using as a local package:

```yaml
dependencies:
  dart_template_engine:
    path: packages/dart_template_engine
```

## Quick Start

### Basic Usage

```dart
import 'package:dart_template_engine/dart_template_engine.dart';

final engine = DartTemplateEngine();

// Simple variable interpolation
final result = engine.render('Hello {{name}}!', {'name': 'World'});
print(result); // Hello World!

// Using built-in helpers
final upper = engine.render('{{@uppercase(name)}}', {'name': 'hello'});
print(upper); // HELLO

// Object property access
final user = {'name': 'John', 'age': 30};
final greeting = engine.render('Hello {{user.name}}, you are {{user.age}}!', {'user': user});
print(greeting); // Hello John, you are 30!
```

### Method Calls

```dart
class User {
  final String firstName;
  final String lastName;

  User(this.firstName, this.lastName);

  String getFullName() => '$firstName $lastName';
  String getGreeting(String prefix) => '$prefix $firstName';
}

final user = User('John', 'Doe');
final result = engine.render('{{user.getFullName()}} says {{user.getGreeting("Hello")}}', {
  'user': user
});
print(result); // John Doe says Hello John
```

### Custom Functions

```dart
// Register sync function
engine.registerFunction('double', (args) => (args[0] as num) * 2);

// Register async function
engine.registerAsyncFunction('loadUser', (args) async {
  final userId = args[0];
  return await userService.getUser(userId);
});

// Use in templates
final result1 = engine.render('{{@double(value)}}', {'value': 5});
print(result1); // 10

final result2 = await engine.renderAsync('{{@loadUser(userId)}}', {'userId': 123});
print(result2); // User data from async call
```

## Syntax Reference

### Variables

```mustache
{{variable}}           <!-- Simple variable -->
{{object.property}}    <!-- Object property -->
{{{unescaped}}}       <!-- Unescaped HTML -->
```

### Sections

```mustache
{{#users}}             <!-- Loop over array -->
  {{name}}
{{/users}}

{{^empty}}             <!-- Inverted section -->
  Has content
{{/empty}}
```

### Functions

```mustache
{{@helper(arg1, arg2)}}           <!-- Helper function -->
{{object.method(arg1, arg2)}}     <!-- Method call -->
```

### Comments

```mustache
{{! This is a comment }}
```

## Built-in Helpers

### String Helpers

- `{{@uppercase(text)}}` - Convert to uppercase
- `{{@lowercase(text)}}` - Convert to lowercase
- `{{@capitalize(text)}}` - Capitalize first letter
- `{{@truncate(text, length)}}` - Truncate to length
- `{{@trim(text)}}` - Remove whitespace

### Date Helpers

- `{{@formatDate(date, format)}}` - Format date with pattern
- `{{@now()}}` - Current DateTime
- `{{@addDays(date, days)}}` - Add days to date

### Math Helpers

- `{{@add(a, b)}}` - Addition
- `{{@subtract(a, b)}}` - Subtraction
- `{{@multiply(a, b)}}` - Multiplication
- `{{@divide(a, b)}}` - Division
- `{{@round(number)}}` - Round number
- `{{@abs(number)}}` - Absolute value

### Collection Helpers

- `{{@length(collection)}}` - Get length
- `{{@join(array, separator)}}` - Join array elements
- `{{@first(collection)}}` - Get first element
- `{{@last(collection)}}` - Get last element

### Utility Helpers

- `{{@default(value, fallback)}}` - Use fallback if empty
- `{{@isEmpty(value)}}` - Check if empty
- `{{@isNotEmpty(value)}}` - Check if not empty

## Advanced Usage

### Async Functions with Fallbacks

```dart
final engine = DartTemplateEngine(fallbacks: {
  'loadUserData': 'Loading...',
  'fetchWeather': 'Weather unavailable'
});

engine.registerAsyncFunction('loadUserData', (args) async {
  // This might fail or be slow
  return await expensiveApiCall(args[0]);
});

// If async function fails, fallback value is used
final result = await engine.renderAsync('User: {{@loadUserData(userId)}}', {
  'userId': 123
});
```

### Error Handling

```dart
try {
  final result = engine.render('{{@unknownFunction()}}', {});
} on TemplateException catch (e) {
  print('Template error: ${e.message}');
  if (e.position != null) {
    print('At position: ${e.position}');
  }
}
```

### Function Management

```dart
// Check if function exists
if (engine.hasFunction('myFunction')) {
  // Function is available
}

// Get all registered functions
final functions = engine.getRegisteredFunctions();
print('Available functions: $functions');

// Unregister a function
engine.unregisterFunction('oldFunction');

// Clear all custom functions (keeps built-ins)
engine.clearCustomFunctions();
```

## Performance Tips

1. **Reuse engine instances** - Template engines are designed to be reused
2. **Minimal context** - Only pass necessary data in context
3. **Sync when possible** - Use sync rendering when no async functions are needed
4. **Batch operations** - Process multiple templates together when possible

## Security Considerations

- Only **public methods** can be called on objects
- Private and protected members are blocked
- HTML is escaped by default (use `{{{variable}}}` for unescaped)
- Function calls are validated at runtime

## Examples

### Blog Template

```dart
final post = {
  'title': 'My Blog Post',
  'content': 'This is the content...',
  'author': {'name': 'John Doe'},
  'publishedAt': DateTime.now(),
  'tags': ['dart', 'template', 'engine']
};

final template = '''
<article>
  <h1>{{post.title}}</h1>
  <p>By {{post.author.name}} on {{@formatDate(post.publishedAt, 'MMM dd, yyyy')}}</p>
  <div>{{post.content}}</div>
  <footer>
    Tags: {{@join(post.tags, ', ')}}
  </footer>
</article>
''';

final html = engine.render(template, {'post': post});
```

### User List

```dart
final users = [
  {'name': 'John', 'email': 'john@example.com', 'active': true},
  {'name': 'Jane', 'email': 'jane@example.com', 'active': false},
];

final template = '''
{{#users}}
  <div class="user {{^active}}inactive{{/active}}">
    <h3>{{@capitalize(name)}}</h3>
    <p>{{@lowercase(email)}}</p>
  </div>
{{/users}}
{{^users}}
  <p>No users found</p>
{{/users}}
''';

final html = engine.render(template, {'users': users});
```

## Contributing

1. Fork the repository
2. Create a feature branch
3. Add tests for new functionality
4. Ensure all tests pass
5. Submit a pull request

## License

This project is licensed under the MIT License - see the LICENSE file for details.
