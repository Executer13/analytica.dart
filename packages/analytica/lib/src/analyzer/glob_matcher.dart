/// Zero-dependency wildcard matching supporting `*` and `?` patterns.
class WildcardPattern {
  final String pattern;
  final bool caseSensitive;
  final RegExp _regExp;

  WildcardPattern(this.pattern, {this.caseSensitive = true})
    : _regExp = _compile(pattern, caseSensitive: caseSensitive);

  static RegExp _compile(String pattern, {required bool caseSensitive}) {
    final buffer = StringBuffer('^');
    for (var i = 0; i < pattern.length; i++) {
      final char = pattern[i];
      if (char == '*') {
        buffer.write('.*');
      } else if (char == '?') {
        buffer.write('.');
      } else {
        buffer.write(RegExp.escape(char));
      }
    }
    buffer.write(r'$');
    return RegExp(buffer.toString(), caseSensitive: caseSensitive);
  }

  /// Returns `true` if this pattern matches the complete [input] string.
  bool matches(String input) => _regExp.hasMatch(input);

  /// Returns `true` if any pattern in [patterns] matches the [input] string.
  static bool anyMatch(Iterable<WildcardPattern> patterns, String input) {
    for (final pattern in patterns) {
      if (pattern.matches(input)) {
        return true;
      }
    }
    return false;
  }

  @override
  String toString() => 'WildcardPattern($pattern)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is WildcardPattern &&
          runtimeType == other.runtimeType &&
          pattern == other.pattern &&
          caseSensitive == other.caseSensitive;

  @override
  int get hashCode => Object.hash(pattern, caseSensitive);
}
