import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/token.dart';

/// Helper for parsing custom `// zombie:ignore` and `// zombie:ignore_for_file`
/// comment suppression directives.
abstract final class CommentParser {
  static final RegExp ignoreForFilePattern = RegExp(
    r'//\s*zombie:ignore_for_file\b',
  );
  static final RegExp ignoreDeclarationPattern = RegExp(
    r'//\s*zombie:ignore\b',
  );

  /// Returns `true` if [unit] contains a file-level suppression directive
  /// (`// zombie:ignore_for_file`) in its comments.
  static bool hasIgnoreForFile(CompilationUnit unit, [String? sourceCode]) {
    var token = unit.beginToken;
    while (!token.isEof) {
      Token? comment = token.precedingComments;
      while (comment != null) {
        if (ignoreForFilePattern.hasMatch(comment.lexeme)) {
          return true;
        }
        comment = comment.next;
      }
      final nextToken = token.next;
      if (nextToken == null) break;
      token = nextToken;
    }
    return false;
  }

  /// Returns `true` if [node] is preceded by a `// zombie:ignore` directive.
  static bool isDeclarationIgnored(AstNode node) {
    // Check comments preceding the beginToken.
    if (_commentsContainIgnore(node.beginToken.precedingComments)) {
      return true;
    }

    // If node is an annotated node, also check comments on each metadata token
    // and the first token after metadata.
    if (node is AnnotatedNode) {
      for (final meta in node.metadata) {
        if (_commentsContainIgnore(meta.beginToken.precedingComments)) {
          return true;
        }
      }
      final firstToken = node.firstTokenAfterCommentAndMetadata;
      if (_commentsContainIgnore(firstToken.precedingComments)) {
        return true;
      }
    }

    return false;
  }

  static bool _commentsContainIgnore(Token? commentToken) {
    var current = commentToken;
    while (current != null) {
      if (ignoreDeclarationPattern.hasMatch(current.lexeme)) {
        return true;
      }
      current = current.next;
    }
    return false;
  }
}
