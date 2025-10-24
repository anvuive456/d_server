/// Token types that can be found in a template.
enum TokenType {
  /// Plain text content that should be rendered as-is.
  text,

  /// A variable reference like {{variable}} or {{object.property}}.
  variable,

  /// A function call like {{@helper(args)}} or {{object.method(args)}}.
  functionCall,

  /// Start of a section like {{#section}}.
  sectionStart,

  /// End of a section like {{/section}}.
  sectionEnd,

  /// An inverted section like {{^section}}.
  invertedSection,

  /// A comment like {{! comment }}.
  comment,

  /// A partial include like {{> partial}}.
  partial,

  /// Unescaped variable like {{{variable}}}.
  unescapedVariable,
}

/// A token represents a parsed piece of a template.
///
/// Tokens are the basic building blocks that the lexer produces
/// from parsing a template string. Each token has a type that
/// determines how it should be processed during rendering.
///
/// ## Example:
/// ```dart
/// final token = Token(
///   TokenType.variable,
///   'user.name',
///   0,
///   {'path': ['user', 'name']}
/// );
/// ```
class Token {
  /// The type of this token.
  final TokenType type;

  /// The raw content of this token (without the mustache braces).
  final String content;

  /// The position in the original template where this token starts.
  final int position;

  /// Optional metadata associated with this token.
  ///
  /// This can contain parsed information specific to the token type,
  /// such as function arguments for function calls or property paths
  /// for variable references.
  final Map<String, dynamic>? metadata;

  /// Creates a new token.
  ///
  /// [type] is the type of token.
  /// [content] is the raw content without mustache braces.
  /// [position] is the character position in the original template.
  /// [metadata] is optional additional data about the token.
  const Token(
    this.type,
    this.content,
    this.position, [
    this.metadata,
  ]);

  /// Creates a text token.
  Token.text(String content, int position)
      : this(TokenType.text, content, position);

  /// Creates a variable token.
  Token.variable(String content, int position, {Map<String, dynamic>? metadata})
      : this(TokenType.variable, content, position, metadata);

  /// Creates a function call token.
  Token.functionCall(String content, int position,
      {Map<String, dynamic>? metadata})
      : this(TokenType.functionCall, content, position, metadata);

  /// Creates a section start token.
  Token.sectionStart(String content, int position,
      {Map<String, dynamic>? metadata})
      : this(TokenType.sectionStart, content, position, metadata);

  /// Creates a section end token.
  Token.sectionEnd(String content, int position)
      : this(TokenType.sectionEnd, content, position);

  /// Creates an inverted section token.
  Token.invertedSection(String content, int position,
      {Map<String, dynamic>? metadata})
      : this(TokenType.invertedSection, content, position, metadata);

  /// Creates a comment token.
  Token.comment(String content, int position)
      : this(TokenType.comment, content, position);

  /// Creates a partial token.
  Token.partial(String content, int position)
      : this(TokenType.partial, content, position);

  /// Creates an unescaped variable token.
  Token.unescapedVariable(String content, int position,
      {Map<String, dynamic>? metadata})
      : this(TokenType.unescapedVariable, content, position, metadata);

  /// Returns true if this token produces output during rendering.
  bool get hasOutput {
    switch (type) {
      case TokenType.text:
      case TokenType.variable:
      case TokenType.functionCall:
      case TokenType.unescapedVariable:
      case TokenType.partial:
        return true;
      case TokenType.sectionStart:
      case TokenType.sectionEnd:
      case TokenType.invertedSection:
      case TokenType.comment:
        return false;
    }
  }

  /// Returns true if this token is a mustache expression (not plain text).
  bool get isMustacheExpression {
    return type != TokenType.text;
  }

  /// Returns true if this token represents a section (start, end, or inverted).
  bool get isSection {
    return type == TokenType.sectionStart ||
        type == TokenType.sectionEnd ||
        type == TokenType.invertedSection;
  }

  @override
  String toString() {
    final buffer = StringBuffer('Token(');
    buffer.write('type: $type, ');
    buffer.write('content: "$content", ');
    buffer.write('position: $position');
    if (metadata != null) {
      buffer.write(', metadata: $metadata');
    }
    buffer.write(')');
    return buffer.toString();
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is Token &&
        other.type == type &&
        other.content == content &&
        other.position == position &&
        _mapEquals(other.metadata, metadata);
  }

  @override
  int get hashCode {
    return Object.hash(
      type,
      content,
      position,
      metadata?.hashCode ?? 0,
    );
  }

  /// Helper method to compare maps for equality.
  static bool _mapEquals(Map<String, dynamic>? a, Map<String, dynamic>? b) {
    if (a == null && b == null) return true;
    if (a == null || b == null) return false;
    if (a.length != b.length) return false;

    for (final key in a.keys) {
      if (!b.containsKey(key) || a[key] != b[key]) {
        return false;
      }
    }
    return true;
  }
}
