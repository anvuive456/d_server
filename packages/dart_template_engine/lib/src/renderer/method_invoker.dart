import 'dart:mirrors';
import '../exceptions/template_exception.dart';

/// Utility class for invoking methods and accessing properties on objects
/// using Dart's reflection capabilities.
///
/// This class provides a safe way to call methods and access properties
/// on arbitrary objects from within templates. It enforces security by
/// only allowing access to public members and provides clear error
/// messages when operations fail.
///
/// ## Security Features:
/// - Only public methods and properties are accessible
/// - Private and protected members are blocked
/// - Clear error messages for debugging
/// - Null-safe operations
///
/// ## Example:
/// ```dart
/// class User {
///   String name;
///   User(this.name);
///   String getName() => name;
///   String getGreeting(String prefix) => '$prefix $name';
/// }
///
/// final user = User('John');
///
/// // Get property
/// final name = MethodInvoker.getProperty(user, 'name'); // 'John'
///
/// // Call method without arguments
/// final name2 = MethodInvoker.invokeMethod(user, 'getName', []); // 'John'
///
/// // Call method with arguments
/// final greeting = MethodInvoker.invokeMethod(user, 'getGreeting', ['Hello']); // 'Hello John'
/// ```
class MethodInvoker {
  /// Invokes a method on an object with the given arguments.
  ///
  /// [object] is the target object to call the method on.
  /// [methodName] is the name of the method to call.
  /// [args] is the list of arguments to pass to the method.
  ///
  /// Returns the result of the method call.
  /// Throws [TemplateException] if the method call fails for any reason.
  static dynamic invokeMethod(
      dynamic object, String methodName, List<dynamic> args) {
    if (object == null) {
      throw TemplateException.methodInvocation(
        methodName,
        'Cannot call method on null object',
      );
    }

    try {
      final instanceMirror = reflect(object);
      final classMirror = instanceMirror.type;

      // Find the method
      final methodSymbol = Symbol(methodName);
      final methodMirror = classMirror.declarations[methodSymbol];

      if (methodMirror == null) {
        throw TemplateException.methodInvocation(
          methodName,
          'Method not found on ${object.runtimeType}',
        );
      }

      // Check if it's actually a method
      if (methodMirror is! MethodMirror) {
        throw TemplateException.methodInvocation(
          methodName,
          'Member is not a method on ${object.runtimeType}',
        );
      }

      // Check if the method is public
      if (methodMirror.isPrivate) {
        throw TemplateException.methodInvocation(
          methodName,
          'Method is private and cannot be accessed',
        );
      }

      // Check if it's a regular method (not a getter/setter/constructor)
      if (methodMirror.isGetter ||
          methodMirror.isSetter ||
          methodMirror.isConstructor) {
        throw TemplateException.methodInvocation(
          methodName,
          'Cannot invoke getter, setter, or constructor as method',
        );
      }

      // Validate argument count
      final parameterCount = methodMirror.parameters.length;
      final requiredParameterCount =
          methodMirror.parameters.where((p) => !p.isOptional).length;

      if (args.length < requiredParameterCount ||
          args.length > parameterCount) {
        throw TemplateException.methodInvocation(
          methodName,
          'Invalid number of arguments: expected $requiredParameterCount-$parameterCount, got ${args.length}',
        );
      }

      // Invoke the method
      final result = instanceMirror.invoke(methodSymbol, args);
      return result.reflectee;
    } on TemplateException {
      rethrow;
    } catch (e) {
      throw TemplateException.methodInvocation(
        methodName,
        'Method invocation failed: $e',
        cause: e,
      );
    }
  }

  /// Gets the value of a property on an object.
  ///
  /// [object] is the target object to get the property from.
  /// [propertyName] is the name of the property to get.
  ///
  /// Returns the value of the property.
  /// Throws [TemplateException] if the property access fails.
  static dynamic getProperty(dynamic object, String propertyName) {
    if (object == null) {
      throw TemplateException.methodInvocation(
        propertyName,
        'Cannot access property on null object',
      );
    }

    try {
      final instanceMirror = reflect(object);
      final classMirror = instanceMirror.type;

      // Try to find the property as a field or getter
      final propertySymbol = Symbol(propertyName);
      final declaration = classMirror.declarations[propertySymbol];

      if (declaration == null) {
        throw TemplateException.methodInvocation(
          propertyName,
          'Property not found on ${object.runtimeType}',
        );
      }

      // Check if it's private
      if (declaration.isPrivate) {
        throw TemplateException.methodInvocation(
          propertyName,
          'Property is private and cannot be accessed',
        );
      }

      // Handle different types of declarations
      if (declaration is VariableMirror) {
        // It's a field
        final result = instanceMirror.getField(propertySymbol);
        return result.reflectee;
      } else if (declaration is MethodMirror && declaration.isGetter) {
        // It's a getter method
        final result = instanceMirror.getField(propertySymbol);
        return result.reflectee;
      } else {
        throw TemplateException.methodInvocation(
          propertyName,
          'Member is not a readable property on ${object.runtimeType}',
        );
      }
    } on TemplateException {
      rethrow;
    } catch (e) {
      throw TemplateException.methodInvocation(
        propertyName,
        'Property access failed: $e',
        cause: e,
      );
    }
  }

  /// Checks if an object has a public method with the given name.
  ///
  /// [object] is the object to check.
  /// [methodName] is the name of the method to look for.
  ///
  /// Returns true if the object has a public method with the given name.
  static bool hasMethod(dynamic object, String methodName) {
    if (object == null) {
      return false;
    }

    try {
      final instanceMirror = reflect(object);
      final classMirror = instanceMirror.type;
      final methodSymbol = Symbol(methodName);
      final methodMirror = classMirror.declarations[methodSymbol];

      return methodMirror != null &&
          methodMirror is MethodMirror &&
          !methodMirror.isPrivate &&
          !methodMirror.isGetter &&
          !methodMirror.isSetter &&
          !methodMirror.isConstructor;
    } catch (e) {
      return false;
    }
  }

  /// Checks if an object has a public property with the given name.
  ///
  /// [object] is the object to check.
  /// [propertyName] is the name of the property to look for.
  ///
  /// Returns true if the object has a public property with the given name.
  static bool hasProperty(dynamic object, String propertyName) {
    if (object == null) {
      return false;
    }

    try {
      final instanceMirror = reflect(object);
      final classMirror = instanceMirror.type;
      final propertySymbol = Symbol(propertyName);
      final declaration = classMirror.declarations[propertySymbol];

      if (declaration == null || declaration.isPrivate) {
        return false;
      }

      return declaration is VariableMirror ||
          (declaration is MethodMirror && declaration.isGetter);
    } catch (e) {
      return false;
    }
  }

  /// Gets a list of all public method names available on an object.
  ///
  /// [object] is the object to inspect.
  ///
  /// Returns a list of method names that can be called safely.
  static List<String> getPublicMethodNames(dynamic object) {
    if (object == null) {
      return [];
    }

    try {
      final instanceMirror = reflect(object);
      final classMirror = instanceMirror.type;
      final methodNames = <String>[];

      for (final declaration in classMirror.declarations.values) {
        if (declaration is MethodMirror &&
            !declaration.isPrivate &&
            !declaration.isGetter &&
            !declaration.isSetter &&
            !declaration.isConstructor) {
          methodNames.add(MirrorSystem.getName(declaration.simpleName));
        }
      }

      return methodNames;
    } catch (e) {
      return [];
    }
  }

  /// Gets a list of all public property names available on an object.
  ///
  /// [object] is the object to inspect.
  ///
  /// Returns a list of property names that can be accessed safely.
  static List<String> getPublicPropertyNames(dynamic object) {
    if (object == null) {
      return [];
    }

    try {
      final instanceMirror = reflect(object);
      final classMirror = instanceMirror.type;
      final propertyNames = <String>[];

      for (final declaration in classMirror.declarations.values) {
        if (!declaration.isPrivate) {
          if (declaration is VariableMirror ||
              (declaration is MethodMirror && declaration.isGetter)) {
            propertyNames.add(MirrorSystem.getName(declaration.simpleName));
          }
        }
      }

      return propertyNames;
    } catch (e) {
      return [];
    }
  }
}
