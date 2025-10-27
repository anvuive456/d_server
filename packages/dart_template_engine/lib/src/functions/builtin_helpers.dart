import 'package:intl/intl.dart';
import 'function_registry.dart';

/// Built-in helper functions for the template engine.
///
/// This class provides a collection of commonly used helper functions
/// that are automatically registered when a DartTemplateEngine is created.
///
/// ## Available Functions:
///
/// ### String Helpers:
/// - `uppercase(text)` - Converts text to uppercase
/// - `lowercase(text)` - Converts text to lowercase
/// - `capitalize(text)` - Capitalizes the first letter
/// - `truncate(text, length)` - Truncates text to specified length
/// - `trim(text)` - Removes leading and trailing whitespace
///
/// ### Date Helpers:
/// - `formatDate(date, format)` - Formats a DateTime using intl patterns
/// - `now()` - Returns current DateTime
/// - `addDays(date, days)` - Adds days to a date
///
/// ### Math Helpers:
/// - `add(a, b)` - Adds two numbers
/// - `subtract(a, b)` - Subtracts b from a
/// - `multiply(a, b)` - Multiplies two numbers
/// - `divide(a, b)` - Divides a by b
/// - `round(number)` - Rounds a number to nearest integer
/// - `abs(number)` - Returns absolute value
///
/// ### Collection Helpers:
/// - `length(collection)` - Returns length of string or collection
/// - `join(collection, separator)` - Joins collection with separator
/// - `first(collection)` - Returns first element
/// - `last(collection)` - Returns last element
///
/// ### Utility Helpers:
/// - `default(value, fallback)` - Returns fallback if value is null/empty
/// - `isEmpty(value)` - Checks if value is null or empty
/// - `isNotEmpty(value)` - Checks if value is not null and not empty
class BuiltinHelpers {
  /// Registers all built-in helper functions with the given registry.
  ///
  /// This method is called automatically when creating a DartTemplateEngine.
  /// All functions registered here are marked as built-in and won't be
  /// removed when clearing custom functions.
  static void registerAll(FunctionRegistry registry) {
    // String helpers
    registry.registerBuiltinFunction('uppercase', _uppercase);
    registry.registerBuiltinFunction('lowercase', _lowercase);
    registry.registerBuiltinFunction('capitalize', _capitalize);
    registry.registerBuiltinFunction('truncate', _truncate);
    registry.registerBuiltinFunction('trim', _trim);
    registry.registerBuiltinFunction('text', _text);

    // Date helpers
    registry.registerBuiltinFunction('formatDate', _formatDate);
    registry.registerBuiltinFunction('now', _now);
    registry.registerBuiltinFunction('addDays', _addDays);

    // Math helpers
    registry.registerBuiltinFunction('add', _add);
    registry.registerBuiltinFunction('subtract', _subtract);
    registry.registerBuiltinFunction('multiply', _multiply);
    registry.registerBuiltinFunction('divide', _divide);
    registry.registerBuiltinFunction('round', _round);
    registry.registerBuiltinFunction('abs', _abs);

    // Collection helpers
    registry.registerBuiltinFunction('length', _length);
    registry.registerBuiltinFunction('join', _join);
    registry.registerBuiltinFunction('first', _first);
    registry.registerBuiltinFunction('last', _last);

    // Utility helpers
    registry.registerBuiltinFunction('default', _default);
    registry.registerBuiltinFunction('isEmpty', _isEmpty);
    registry.registerBuiltinFunction('isNotEmpty', _isNotEmpty);
  }

  static dynamic _text(List<dynamic> args) {
    if (args.isEmpty) return '';
    return args.join('');
  }

  // String helpers implementation
  static dynamic _uppercase(List<dynamic> args) {
    if (args.isEmpty) return '';
    return args[0]?.toString().toUpperCase() ?? '';
  }

  static dynamic _lowercase(List<dynamic> args) {
    if (args.isEmpty) return '';
    return args[0]?.toString().toLowerCase() ?? '';
  }

  static dynamic _capitalize(List<dynamic> args) {
    if (args.isEmpty) return '';
    final str = args[0]?.toString() ?? '';
    if (str.isEmpty) return '';
    return str[0].toUpperCase() + str.substring(1).toLowerCase();
  }

  static dynamic _truncate(List<dynamic> args) {
    if (args.length < 2) {
      return args.isNotEmpty ? args[0]?.toString() ?? '' : '';
    }
    final str = args[0]?.toString() ?? '';
    final length = args[1] as int? ?? 0;
    if (length <= 0) return '';
    if (str.length <= length) return str;
    return '${str.substring(0, length)}...';
  }

  static dynamic _trim(List<dynamic> args) {
    if (args.isEmpty) return '';
    return args[0]?.toString().trim() ?? '';
  }

  // Date helpers implementation
  static dynamic _formatDate(List<dynamic> args) {
    if (args.isEmpty) return '';
    final date = args[0];
    if (date == null) return '';

    DateTime? dateTime;
    if (date is DateTime) {
      dateTime = date;
    } else if (date is String) {
      dateTime = DateTime.tryParse(date);
    }

    if (dateTime == null) return '';

    final format =
        args.length > 1 ? args[1] as String? ?? 'yyyy-MM-dd' : 'yyyy-MM-dd';
    try {
      return DateFormat(format).format(dateTime);
    } catch (e) {
      print('Date format error: $e');
      return dateTime.toString();
    }
  }

  static dynamic _now(List<dynamic> args) {
    return DateTime.now();
  }

  static dynamic _addDays(List<dynamic> args) {
    if (args.length < 2) return null;
    final date = args[0];
    final days = args[1] as int? ?? 0;

    DateTime? dateTime;
    if (date is DateTime) {
      dateTime = date;
    } else if (date is String) {
      dateTime = DateTime.tryParse(date);
    }

    return dateTime?.add(Duration(days: days));
  }

  // Math helpers implementation
  static dynamic _add(List<dynamic> args) {
    if (args.length < 2) return 0;
    final a = args[0];
    final b = args[1];

    if (a is num && b is num) {
      return a + b;
    }
    return 0;
  }

  static dynamic _subtract(List<dynamic> args) {
    if (args.length < 2) return 0;
    final a = args[0];
    final b = args[1];

    if (a is num && b is num) {
      return a - b;
    }
    return 0;
  }

  static dynamic _multiply(List<dynamic> args) {
    if (args.length < 2) return 0;
    final a = args[0];
    final b = args[1];

    if (a is num && b is num) {
      return a * b;
    }
    return 0;
  }

  static dynamic _divide(List<dynamic> args) {
    if (args.length < 2) return 0;
    final a = args[0];
    final b = args[1];

    if (a is num && b is num && b != 0) {
      return a / b;
    }
    return 0;
  }

  static dynamic _round(List<dynamic> args) {
    if (args.isEmpty) return 0;
    final number = args[0];
    if (number is num) {
      return number.round();
    }
    return 0;
  }

  static dynamic _abs(List<dynamic> args) {
    if (args.isEmpty) return 0;
    final number = args[0];
    if (number is num) {
      return number.abs();
    }
    return 0;
  }

  // Collection helpers implementation
  static dynamic _length(List<dynamic> args) {
    if (args.isEmpty) return 0;
    final value = args[0];
    if (value is String) return value.length;
    if (value is List) return value.length;
    if (value is Map) return value.length;
    if (value is Set) return value.length;
    return 0;
  }

  static dynamic _join(List<dynamic> args) {
    if (args.isEmpty) return '';
    final collection = args[0];
    final separator = args.length > 1 ? args[1]?.toString() ?? ',' : ',';

    if (collection is List) {
      return collection.map((e) => e?.toString() ?? '').join(separator);
    }
    return collection?.toString() ?? '';
  }

  static dynamic _first(List<dynamic> args) {
    if (args.isEmpty) return null;
    final collection = args[0];
    if (collection is List && collection.isNotEmpty) {
      return collection.first;
    }
    if (collection is String && collection.isNotEmpty) {
      return collection[0];
    }
    return null;
  }

  static dynamic _last(List<dynamic> args) {
    if (args.isEmpty) return null;
    final collection = args[0];
    if (collection is List && collection.isNotEmpty) {
      return collection.last;
    }
    if (collection is String && collection.isNotEmpty) {
      return collection[collection.length - 1];
    }
    return null;
  }

  // Utility helpers implementation
  static dynamic _default(List<dynamic> args) {
    if (args.length < 2) return null;
    final value = args[0];
    final fallback = args[1];

    if (value == null) return fallback;
    if (value is String && value.isEmpty) return fallback;
    if (value is List && value.isEmpty) return fallback;
    if (value is Map && value.isEmpty) return fallback;

    return value;
  }

  static bool _isEmpty(List<dynamic> args) {
    if (args.isEmpty) return true;
    final value = args[0];

    if (value == null) return true;
    if (value is String) return value.isEmpty;
    if (value is List) return value.isEmpty;
    if (value is Map) return value.isEmpty;
    if (value is Set) return value.isEmpty;

    return false;
  }

  static bool _isNotEmpty(List<dynamic> args) {
    return !(_isEmpty(args));
  }
}
