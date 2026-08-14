import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/token.dart';

/// Generic token-based suppression parser for `// <tool>:ignore` and
/// `// <tool>:ignore_for_file` comment suppression directives.
///
/// Because this parser inspects token stream comments rather than raw string
/// matching, it is completely immune to false positives inside string literals.
class CommentDirectiveParser {
  final String toolName;
  final RegExp ignoreForFilePattern;
  final RegExp ignoreDeclarationPattern;

  CommentDirectiveParser(this.toolName)
    : ignoreForFilePattern = RegExp(
        '//\\s*${RegExp.escape(toolName)}:ignore_for_file\\b',
      ),
      ignoreDeclarationPattern = RegExp(
        '//\\s*${RegExp.escape(toolName)}:ignore\\b',
      );

  /// Returns `true` if [unit] contains a file-level suppression directive
  /// (`// <tool>:ignore_for_file`) in its comments.
  bool hasIgnoreForFile(CompilationUnit unit, [String? sourceCode]) {
    var token = unit.beginToken;
    while (true) {
      Token? comment = token.precedingComments;
      while (comment != null) {
        if (ignoreForFilePattern.hasMatch(comment.lexeme)) {
          return true;
        }
        comment = comment.next;
      }
      if (token.isEof) break;
      final nextToken = token.next;
      if (nextToken == null) break;
      token = nextToken;
    }
    return false;
  }

  /// Returns `true` if [node] is preceded by a `// <tool>:ignore` directive.
  bool isDeclarationIgnored(AstNode node) {
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

    // If node is a VariableDeclaration inside a VariableDeclarationList,
    // also check the enclosing AnnotatedNode (TopLevelVariableDeclaration or
    // FieldDeclaration).
    final parent = node.parent;
    if (parent is VariableDeclarationList) {
      final grandParent = parent.parent;
      if (grandParent is AnnotatedNode && isDeclarationIgnored(grandParent)) {
        return true;
      }
    }

    return false;
  }

  bool _commentsContainIgnore(Token? commentToken) {
    var current = commentToken;
    while (current != null) {
      if (ignoreDeclarationPattern.hasMatch(current.lexeme)) {
        return true;
      }
      current = current.next;
    }
    return false;
  }

  /// Static helper to check file-level suppression for a given [toolName].
  static bool hasIgnoreForFileDirective(
    CompilationUnit unit, {
    required String toolName,
    String? sourceCode,
  }) => CommentDirectiveParser(toolName).hasIgnoreForFile(unit, sourceCode);

  /// Static helper to check declaration-level suppression for a given
  /// [toolName].
  static bool isDeclarationIgnoredFor(
    AstNode node, {
    required String toolName,
  }) => CommentDirectiveParser(toolName).isDeclarationIgnored(node);
}
