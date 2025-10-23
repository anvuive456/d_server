# D_Server 🚀

A powerful web framework for Dart that brings convention over configuration, Active Record ORM, and rapid development to server-side Dart applications.

[![Pub Version](https://img.shields.io/pub/v/d_server.svg)](https://pub.dev/packages/d_server)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

## ✨ Features

- **🎯 Active Record ORM** - PostgreSQL integration with intuitive model associations
- **🛣️ RESTful Routing** - Resource-based routing with nested routes and middleware support
- **🎮 Controller Architecture** - Action filters, request handling, and response helpers
- **🔐 Built-in Authentication** - JWT tokens, sessions, password hashing, and user management
- **📄 Template Engine** - Mustache template integration with layouts and partials
- **🔥 Hot Reload** - Development server with automatic reloading
- **🗄️ Database Migrations** - Version-controlled database schema changes
- **📊 Logging System** - Structured logging with different levels and scopes
- **⚡ Middleware Support** - Request/response pipeline with custom middleware
- **🎨 Convention over Configuration** - Sensible defaults with easy customization

## 🔧 Requirements

- Dart SDK 3.0.0 or higher
- PostgreSQL database
- Git (for project generation)

## 📦 Installation

### Step 1: Install CLI Tool globally

First, activate the D_Server CLI tool globally:

```bash
dart pub global activate d_server
```

### Step 2: Create a new project

Once the CLI tool is installed globally, you can create a new project:

```bash
d_server new [project_name]
```

For example:

```bash
d_server new my_awesome_app
```

## 🚀 Quick Start

### 1. Create a new project

After installing the CLI tool globally, create a new project:

```bash
# Create a new D_Server project
d_server new my_awesome_app

# Navigate to your project directory
cd my_awesome_app

# Your project is ready with the following structure:
# lib/main.dart - Main application file
# config/database.yml - Database configuration
# config/app.yml - Application configuration
```

The generated `lib/main.dart` will look like this:

```dart
// lib/main.dart
import 'package:d_server/d_server.dart';

void main() async {
  final app = DApplication({
    'database': {
      'host': 'localhost',
      'port': 5432,
      'database': 'myapp_development',
      'username': 'your_username',
      'password': 'your_password',
    },
    'port': 3000,
    'jwt_secret': 'your-secret-key-here',
    'environment': 'development',
  });

  // Define routes
  app.router.get('/', (request) {
    return Response.ok('Welcome to D_Server! 🎉');
  });

  app.router.resource('users', UsersController);

  await app.start();
  print('🚀 Server running on http://localhost:3000');
}
```

### 2. Create your first model

```dart
// lib/models/user.dart
import 'package:d_server/d_server.dart';

class User extends DModel {
  static String get tableName => 'users';

  String? get name => getAttribute<String>('name');
  set name(String? value) => setAttribute('name', value);

  String? get email => getAttribute<String>('email');
  set email(String? value) => setAttribute('email', value);

  DateTime? get createdAt => getAttribute<DateTime>('created_at');
  DateTime? get updatedAt => getAttribute<DateTime>('updated_at');

  // Validation
  @override
  Map<String, List<String>> get validations => {
    'name': ['required', 'min:2'],
    'email': ['required', 'email', 'unique'],
  };
}
```

### 3. Create a controller

```dart
// lib/controllers/users_controller.dart
import 'package:d_server/d_server.dart';
import '../models/user.dart';

class UsersController extends DController {
  @override
  Future<void> beforeAction() async {
    // Add authentication if needed
    // await requireAuthentication();
  }

  Future<Response> index() async {
    final users = await User.all<User>();
    return json({
      'users': users.map((u) => u.attributes).toList()
    });
  }

  Future<Response> show() async {
    final id = param<int>('id');
    final user = await User.find<User>(id);

    if (user == null) {
      return json({'error': 'User not found'}, status: 404);
    }

    return json({'user': user.attributes});
  }

  Future<Response> create() async {
    final body = await parseBody();
    final user = User();

    user.name = body['name'];
    user.email = body['email'];

    if (await user.save()) {
      return json({'user': user.attributes}, status: 201);
    } else {
      return json({'errors': user.errors}, status: 422);
    }
  }

  Future<Response> update() async {
    final id = param<int>('id');
    final user = await User.find<User>(id);

    if (user == null) {
      return json({'error': 'User not found'}, status: 404);
    }

    final body = await parseBody();
    user.name = body['name'] ?? user.name;
    user.email = body['email'] ?? user.email;

    if (await user.save()) {
      return json({'user': user.attributes});
    } else {
      return json({'errors': user.errors}, status: 422);
    }
  }

  Future<Response> destroy() async {
    final id = param<int>('id');
    final user = await User.find<User>(id);

    if (user == null) {
      return json({'error': 'User not found'}, status: 404);
    }

    await user.destroy();
    return json({'message': 'User deleted successfully'});
  }
}
```

## 🗄️ Active Record ORM

D_Server provides a powerful ORM system with Active Record pattern:

### Model Definition

```dart
class Post extends DModel {
  static String get tableName => 'posts';

  String? get title => getAttribute<String>('title');
  set title(String? value) => setAttribute('title', value);

  String? get content => getAttribute<String>('content');
  set content(String? value) => setAttribute('content', value);

  int? get userId => getAttribute<int>('user_id');
  set userId(int? value) => setAttribute('user_id', value);

  bool get published => getAttribute<bool>('published') ?? false;
  set published(bool value) => setAttribute('published', value);
}
```

### CRUD Operations

```dart
// Create
final post = Post();
post.title = 'Hello World';
post.content = 'This is my first post';
post.userId = 1;
await post.save();

// Read
final posts = await Post.all<Post>();
final post = await Post.find<Post>(1);
final publishedPosts = await Post.where<Post>('published = @published', {'published': true});

// Update
post.title = 'Updated Title';
await post.save();

// Delete
await post.destroy();
```

### Associations (Coming Soon)

```dart
class User extends DModel {
  // Has many posts
  Future<List<Post>> posts() => Post.where<Post>('user_id = @id', {'id': id});
}

class Post extends DModel {
  // Belongs to user
  Future<User?> user() => User.find<User>(userId);
}
```

## 🛣️ Routing System

D_Server provides flexible routing with RESTful resource support:

### Resource Routes

```dart
// Creates all 7 RESTful routes automatically
app.router.resource('posts', PostsController);

// Limit to specific actions
app.router.resource('posts', PostsController, only: ['index', 'show']);
app.router.resource('posts', PostsController, except: ['destroy']);

// Custom path and name
app.router.resource('articles', PostsController, path: '/blog/posts', as: 'blog_posts');
```

### Manual Routes

```dart
app.router.get('/', homeHandler);
app.router.post('/webhook', webhookHandler);
app.router.put('/api/users/:id', updateUserHandler);
app.router.delete('/api/users/:id', deleteUserHandler);
```

### Nested Routes

```dart
app.router.group('/api/v1', (router) {
  router.resource('users', ApiUsersController);
  router.resource('posts', ApiPostsController);

  router.group('/admin', (router) {
    router.resource('users', AdminUsersController);
  });
});
```

### Middleware

```dart
// Global middleware
app.router.use(corsMiddleware);
app.router.use(loggingMiddleware);

// Route-specific middleware
app.router.use(authMiddleware, only: ['/admin', '/api/protected']);
app.router.use(rateLimitMiddleware, except: ['/health']);
```

## 🔐 Authentication System

Comprehensive authentication system with JWT and sessions:

### User Model

```dart
import 'package:d_server/d_server.dart';

// User class extends DModel and includes Authenticatable
class AppUser extends User {
  // Additional user fields
  String? get firstName => getAttribute<String>('first_name');
  set firstName(String? value) => setAttribute('first_name', value);

  String? get lastName => getAttribute<String>('last_name');
  set lastName(String? value) => setAttribute('last_name', value);

  String get fullName => '${firstName ?? ''} ${lastName ?? ''}'.trim();
}
```

### Authentication Controller

```dart
class AuthController extends DController {
  Future<Response> register() async {
    final body = await parseBody();

    final user = AppUser();
    user['email'] = body['email'];
    user['password'] = body['password'];
    user.firstName = body['first_name'];
    user.lastName = body['last_name'];

    if (await user.save()) {
      await user.sendConfirmationEmail();
      return json({'message': 'Registration successful. Please check your email.'});
    } else {
      return json({'errors': user.errors}, status: 422);
    }
  }

  Future<Response> login() async {
    final body = await parseBody();
    final email = body['email'];
    final password = body['password'];

    final user = await AppUser.authenticate(email, password);
    if (user != null) {
      final token = await user.generateJwtToken();
      return json({
        'token': token,
        'user': user.attributes,
      });
    } else {
      return json({'error': 'Invalid credentials'}, status: 401);
    }
  }

  Future<Response> logout() async {
    final user = currentUser;
    if (user != null) {
      await user.invalidateRememberToken();
    }
    return json({'message': 'Logged out successfully'});
  }
}
```

### Protected Routes

```dart
class UsersController extends DController {
  @override
  Future<void> beforeAction() async {
    await requireAuthentication();
  }

  Future<Response> profile() async {
    final user = currentUser!;
    return json({'user': user.attributes});
  }
}
```

## 📄 Template Engine

Mustache template integration with layouts:

### Setup Templates

```dart
final app = DApplication(config);
await app.setupTemplates('views'); // templates directory
```

### Controller Rendering

```dart
class PostsController extends DController {
  Future<Response> show() async {
    final id = param<int>('id');
    final post = await Post.find<Post>(id);

    return render('posts/show', {
      'post': post?.attributes,
      'title': post?.title,
    });
  }
}
```

### Template Files

```html
<!-- views/layouts/application.mustache -->
<!DOCTYPE html>
<html>
  <head>
    <title>{{title}} - My App</title>
  </head>
  <body>
    <nav>
      <a href="/">Home</a>
      <a href="/posts">Posts</a>
    </nav>

    <main>{{{content}}}</main>
  </body>
</html>

<!-- views/posts/show.mustache -->
<article>
  <h1>{{post.title}}</h1>
  <div class="content">{{post.content}}</div>
  <footer>
    <small>Published: {{post.created_at}}</small>
  </footer>
</article>
```

## 🗄️ Database Migrations

Structured database schema management with migrations:

### Creating Migrations

```dart
// db/migrations/001_create_users.dart
import 'package:d_server/d_server.dart';

class CreateUsers extends Migration {
  @override
  Future<void> up() async {
    await createTable('users', (table) {
      table.serial('id').primaryKey().finalize();
      table.string('email').notNull().unique().finalize();
      table.string('password_hash').finalize();
      table.string('first_name').finalize();
      table.string('last_name').finalize();
      table.boolean('email_confirmed').defaultValue('false').finalize();
      table.timestamp('email_confirmed_at').finalize();
      table.timestamps();
    });
  }

  @override
  Future<void> down() async {
    await dropTable('users');
  }
}
```

### Running Migrations

```bash
# Run pending migrations
d_server db:migrate

# Rollback last migration
d_server db:rollback

# Reset database
d_server db:reset
```

## 🔥 Hot Reload Development

Automatic server reloading during development:

```yaml
hot_reload:
  enabled: true
  debounce_delay: 500
  watch_directories:
    - lib
    - views
  ignore_patterns:
    - "**/*.tmp"
    - "**/.*"
    - "**/.git/**"
```

```dart
void main() async {
  final app = DApplication.fromConfigFile('config/development.yaml');

  // Start the server
  // With hot reload enabled in config
  await app.start();
}
```

## 📁 Project Structure

```
my_app/
├── lib/
│   ├── main.dart                 # Application entry point
│   ├── controllers/              # Controllers
│   │   ├── application_controller.dart
│   │   ├── users_controller.dart
│   │   └── posts_controller.dart
│   └── models/                   # Models
│       ├── user.dart
│       └── post.dart
├── views/                        # Templates
│   ├── layouts/
│   │   └── application.mustache
│   ├── users/
│   │   ├── index.mustache
│   │   └── show.mustache
│   └── posts/
│       ├── index.mustache
│       └── show.mustache
├── config/                       # Configuration
│   └── config.yml
│
├── db/
|   ├── migrations/            # Migrations index
│   └── migrate/               # Database migrations
├── public/                       # Static assets
├── test/                         # Tests
└── pubspec.yaml
```

## ⚙️ Configuration

### YAML Configuration

```yaml
# config/config.yml
server:
  host: localhost
  port: 3000
  environment: development

database:
  ssl: false
  host: localhost
  port: 5432
  database: example_development
  username: postgres_username
  password: postgres_password

views:
  path: views
  default_layout: application

cors:
  enabled: true
  allow_origin: "*"

logging:
  level: info
  colors: true
  requests: true

hot_reload:
  enabled: true
  debounce_delay: 500
  watch_directories:
    - lib
    - views
  ignore_patterns:
    - "**/*.tmp"
    - "**/.*"
    - "**/.git/**"
```

### Environment Variables

```bash
# .env
DATABASE_URL=postgresql://user:password@localhost:5432/myapp
JWT_SECRET=your-secret-key
PORT=3000
ENVIRONMENT=development
```

## 🛠️ CLI Commands

```bash
# Create new project
d_server new my_app

# Generate files
d_server generate controller Users
d_server generate model Post title:string content:text
d_server generate migration AddIndexToUsers email:index

# Database commands
d_server db:create
d_server db:migrate
d_server db:rollback
d_server db:reset
d_server db:seed

# Development server
d_server server
d_server server --port 4000

# Testing
d_server test
d_server test --coverage
```

## 🧪 Testing

Built-in testing support with request helpers:

```dart
import 'package:test/test.dart';
import 'package:d_server/d_server.dart';

void main() {
  group('UsersController', () {
    late DApplication app;

    setUp(() async {
      app = DApplication.forTesting();
      await app.connectDatabase();
    });

    tearDown(() async {
      await app.stop();
    });

    test('GET /users returns list of users', () async {
      // Create test user
      final user = User();
      user.name = 'Test User';
      user.email = 'test@example.com';
      await user.save();

      final response = await app.get('/users');

      expect(response.statusCode, equals(200));
      final body = jsonDecode(await response.readAsString());
      expect(body['users'], hasLength(1));
      expect(body['users'][0]['name'], equals('Test User'));
    });
  });
}
```

## 📚 Documentation

- **[API Documentation](https://pub.dev/documentation/d_server)**
- **[Guides & Tutorials](https://github.com/your-username/d_server/wiki)**
- **[Examples](https://github.com/your-username/d_server/tree/main/example)**

## 🤝 Contributing

We welcome contributions! Please see our [Contributing Guide](CONTRIBUTING.md) for details.

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## 🐛 Issues & Support

- **[Report bugs](https://github.com/your-username/d_server/issues)**
- **[Request features](https://github.com/your-username/d_server/issues)**
- **[Ask questions](https://github.com/your-username/d_server/discussions)**

## 📄 License

This project is licensed under the Apache License 2.0 - see the [LICENSE](LICENSE) file for details.

Copyright 2024 D_Server Contributors

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.

## 🙏 Acknowledgments

- Modern web framework architecture
- Built on top of the excellent [Shelf](https://pub.dev/packages/shelf) package
- PostgreSQL integration via [postgres](https://pub.dev/packages/postgres)
- Template rendering with [mustache_template](https://pub.dev/packages/mustache_template)

---

**Made with ❤️ for the Dart community**

_D_Server aims to bring joy and productivity to Dart server-side development._
