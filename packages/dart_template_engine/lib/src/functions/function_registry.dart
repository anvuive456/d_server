/// Function type definitions for template functions.
typedef TemplateFunction = dynamic Function(List<dynamic> args);
typedef AsyncTemplateFunction = Future<dynamic> Function(List<dynamic> args);

/// Registry for managing template functions (both sync and async).
///
/// This class provides a centralized way to register, manage, and call
/// functions that can be used within templates. It supports both synchronous
/// and asynchronous functions.
///
/// ## Example:
/// ```dart
/// final registry = FunctionRegistry();
///
/// // Register sync function
/// registry.registerFunction('uppercase', (args) => args[0].toString().toUpperCase());
///
/// // Register async function
/// registry.registerAsyncFunction('loadData', (args) async {
///   return await dataService.load(args[0]);
/// });
///
/// // Call functions
/// final result = registry.callFunction('uppercase', ['hello']);
/// final asyncResult = await registry.callAsyncFunction('loadData', [123]);
/// ```
class FunctionRegistry {
  final Map<String, TemplateFunction> _syncFunctions = {};
  final Map<String, AsyncTemplateFunction> _asyncFunctions = {};
  final Set<String> _builtinFunctions = {};

  /// Registers a synchronous function.
  ///
  /// [name] is the function name that will be used in templates.
  /// [function] is the function implementation that takes a list of arguments.
  ///
  /// Throws [ArgumentError] if a function with the same name already exists.
  void registerFunction(String name, TemplateFunction function) {
    if (_syncFunctions.containsKey(name) || _asyncFunctions.containsKey(name)) {
      throw ArgumentError('Function "$name" is already registered');
    }
    _syncFunctions[name] = function;
  }

  /// Registers an asynchronous function.
  ///
  /// [name] is the function name that will be used in templates.
  /// [function] is the async function implementation that takes a list of arguments.
  ///
  /// Throws [ArgumentError] if a function with the same name already exists.
  void registerAsyncFunction(String name, AsyncTemplateFunction function) {
    if (_syncFunctions.containsKey(name) || _asyncFunctions.containsKey(name)) {
      throw ArgumentError('Function "$name" is already registered');
    }
    _asyncFunctions[name] = function;
  }

  /// Registers a built-in function (used internally to track built-ins).
  ///
  /// This is used by the BuiltinHelpers class to mark functions as built-in
  /// so they won't be removed when clearing custom functions.
  void registerBuiltinFunction(String name, TemplateFunction function) {
    registerFunction(name, function);
    _builtinFunctions.add(name);
  }

  /// Checks if a synchronous function is registered.
  ///
  /// [name] is the function name to check.
  /// Returns true if a sync function with this name exists.
  bool hasFunction(String name) => _syncFunctions.containsKey(name);

  /// Checks if an asynchronous function is registered.
  ///
  /// [name] is the function name to check.
  /// Returns true if an async function with this name exists.
  bool hasAsyncFunction(String name) => _asyncFunctions.containsKey(name);

  /// Calls a synchronous function.
  ///
  /// [name] is the function name.
  /// [args] is the list of arguments to pass to the function.
  ///
  /// Returns the result of the function call.
  /// Throws [ArgumentError] if the function doesn't exist.
  dynamic callFunction(String name, List<dynamic> args) {
    final function = _syncFunctions[name];
    if (function == null) {
      throw ArgumentError('Sync function "$name" not found');
    }
    return function(args);
  }

  /// Calls an asynchronous function.
  ///
  /// [name] is the function name.
  /// [args] is the list of arguments to pass to the function.
  ///
  /// Returns a Future with the result of the function call.
  /// Throws [ArgumentError] if the function doesn't exist.
  Future<dynamic> callAsyncFunction(String name, List<dynamic> args) async {
    final function = _asyncFunctions[name];
    if (function == null) {
      throw ArgumentError('Async function "$name" not found');
    }
    return await function(args);
  }

  /// Gets all registered synchronous function names.
  ///
  /// Returns a list of sync function names.
  List<String> getSyncFunctionNames() => _syncFunctions.keys.toList();

  /// Gets all registered asynchronous function names.
  ///
  /// Returns a list of async function names.
  List<String> getAsyncFunctionNames() => _asyncFunctions.keys.toList();

  /// Unregisters a function (both sync and async).
  ///
  /// [name] is the function name to unregister.
  /// Returns true if a function was found and removed.
  bool unregisterFunction(String name) {
    final removedSync = _syncFunctions.remove(name) != null;
    final removedAsync = _asyncFunctions.remove(name) != null;
    _builtinFunctions.remove(name);
    return removedSync || removedAsync;
  }

  /// Clears all custom functions, keeping only built-in functions.
  ///
  /// This removes all functions except those marked as built-in.
  void clearCustomFunctions() {
    final builtinSyncFunctions = <String, TemplateFunction>{};
    final builtinAsyncFunctions = <String, AsyncTemplateFunction>{};

    // Preserve built-in functions
    for (final name in _builtinFunctions) {
      if (_syncFunctions.containsKey(name)) {
        builtinSyncFunctions[name] = _syncFunctions[name]!;
      }
      if (_asyncFunctions.containsKey(name)) {
        builtinAsyncFunctions[name] = _asyncFunctions[name]!;
      }
    }

    // Clear all and restore built-ins
    _syncFunctions.clear();
    _asyncFunctions.clear();
    _syncFunctions.addAll(builtinSyncFunctions);
    _asyncFunctions.addAll(builtinAsyncFunctions);
  }

  /// Gets the total number of registered functions.
  ///
  /// Returns the combined count of sync and async functions.
  int get functionCount => _syncFunctions.length + _asyncFunctions.length;

  /// Checks if the registry is empty.
  ///
  /// Returns true if no functions are registered.
  bool get isEmpty => _syncFunctions.isEmpty && _asyncFunctions.isEmpty;
}
