# example

A web application built with D_Server framework.

## Getting Started

1. Install dependencies:
   ```bash
   dart pub get
   ```

2. Set up your database:
   ```bash
   d_server db:create
   d_server db:migrate
   ```

3. Start the server:
   ```bash
   dart run lib/main.dart
   ```

The application will be available at http://localhost:3000

## Development Commands

Make sure you have the D_Server CLI installed globally:
```bash
dart pub global activate d_server
```

Then use these commands in your project directory:
- `d_server generate controller <name>` - Generate a controller
- `d_server generate model <name>` - Generate a model
- `d_server generate migration <name>` - Generate a migration
- `d_server db:migrate` - Run migrations
- `d_server db:rollback` - Rollback migrations
- `d_server server` - Start development server (alternative to dart run)

## Project Structure

- `lib/` - Application code
  - `lib/main.dart` - Application entry point
  - `lib/controllers/` - Controllers
  - `lib/models/` - Models
- `views/` - Templates
- `config/` - Configuration files
- `db/migrations/` - Database migrations
- `public/` - Static assets
