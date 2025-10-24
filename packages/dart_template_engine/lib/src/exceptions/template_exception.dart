/// Exception thrown when template operations fail.
class TemplateException implements Exception {
  /// The error message describing what went wrong.
  final String message;

  /// Optional context information about where the error occurred.
  final String? context;

  /// The position in the template where the error occurred (if available).
  final int? position;

  /// The original exception that caused this template exception (if any).
  final Object? cause;

  /// Creates a new template exception.
  ///
  /// [message] is a description of what went wrong.
  /// [context] provides additional context about where the error occurred.
  /// [position] indicates the character position in the template where the error occurred.
  /// [cause] is the original exception that caused this template exception.
  const TemplateException(
    this.message, {
    this.context,
    this.position,
    this.cause,
  });

  /// Creates a template exception for parsing errors.
  TemplateException.parsing(
    String message, {
    int? position,
    String? context,
    Object? cause,
  }) : this(
          'Parsing error: $message',
          position: position,
          context: context,
          cause: cause,
        );

  /// Creates a template exception for rendering errors.
  TemplateException.rendering(
    String message, {
    String? context,
    Object? cause,
  }) : this(
          'Rendering error: $message',
          context: context,
          cause: cause,
        );

  /// Creates a template exception for function call errors.
  TemplateException.functionCall(
    String functionName,
    String error, {
    Object? cause,
  }) : this(
          'Function call error in "$functionName": $error',
          cause: cause,
        );

  /// Creates a template exception for method invocation errors.
  TemplateException.methodInvocation(
    String methodName,
    String error, {
    Object? cause,
  }) : this(
          'Method invocation error for "$methodName": $error',
          cause: cause,
        );

  @override
  String toString() {
    final buffer = StringBuffer('TemplateException: $message');

    if (position != null) {
      buffer.write(' at position $position');
    }

    if (context != null) {
      buffer.write('\nContext: $context');
    }

    if (cause != null) {
      buffer.write('\nCaused by: $cause');
    }

    return buffer.toString();
  }
}
