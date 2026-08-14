import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/token.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:path/path.dart' as p;

/// Finds the enclosing top-level element for a given element.
Element? getTopLevelElement(Element elem) {
  Element? current = elem;
  while (current != null) {
    final enclosing = current.enclosingElement;
    if (enclosing == null || enclosing is LibraryElement) {
      return current;
    }
    current = enclosing;
  }
  return null;
}

/// Extracts a string name from an AST node safely.
String? extractNodeName(AstNode node) {
  if (node is ClassDeclaration) {
    return node.declaredFragment?.element.name ?? _findFirstIdentifier(node);
  }
  if (node is EnumDeclaration) {
    return node.declaredFragment?.element.name ?? _findFirstIdentifier(node);
  }
  if (node is MixinDeclaration) {
    return node.declaredFragment?.element.name ?? _findFirstIdentifier(node);
  }
  if (node is ExtensionDeclaration) {
    return node.declaredFragment?.element.name ?? _findFirstIdentifier(node);
  }
  if (node is ExtensionTypeDeclaration) {
    return node.declaredFragment?.element.name ?? _findFirstIdentifier(node);
  }
  if (node is TypeAlias) {
    return node.declaredFragment?.element.name ?? _findFirstIdentifier(node);
  }
  if (node is FunctionDeclaration) {
    return node.declaredFragment?.element.name ?? _findFirstIdentifier(node);
  }
  if (node is VariableDeclaration) {
    return node.declaredFragment?.element.name ?? node.name.lexeme;
  }
  return _findFirstIdentifier(node);
}

String? _findFirstIdentifier(AstNode node) {
  for (final entity in node.childEntities) {
    if (entity is Token && entity.type == TokenType.IDENTIFIER) {
      return entity.lexeme;
    }
  }
  return null;
}

/// Checks if an element or AST node has test support annotations / conventions.
bool isTestSupportDeclaration(AnnotatedNode node, String name) {
  if (name.startsWith('Fake') ||
      name.startsWith('Mock') ||
      name.startsWith('Stub') ||
      name.endsWith('Fake') ||
      name.endsWith('Mock') ||
      name.endsWith('Stub')) {
    return true;
  }

  for (final meta in node.metadata) {
    final rawName = meta.name.name;
    final metaName = rawName.contains('.') ? rawName.split('.').last : rawName;
    if (metaName == 'visibleForTesting' ||
        metaName == 'visibleForOverriding' ||
        metaName == 'protected') {
      return true;
    }
  }
  return false;
}

/// Checks if an AST node has native/entrypoint annotations.
bool isNativeOrEntryPoint(AnnotatedNode node) {
  for (final meta in node.metadata) {
    final rawName = meta.name.name;
    final metaName = rawName.contains('.') ? rawName.split('.').last : rawName;
    if (metaName == 'Native' || metaName == 'pragma') {
      return true;
    }
  }
  return false;
}

/// AST Visitor that gathers all references to top-level elements within a
/// declaration or code block, strictly ignoring doc comments and comments.
class ElementReferenceExtractor extends RecursiveAstVisitor<void> {
  final String packageRoot;
  final Set<Element> referencedTopLevelElements = {};

  ElementReferenceExtractor(this.packageRoot);

  @override
  void visitComment(Comment node) {
    // Intentionally skipped: References in doc comments (e.g. `/// [Foo]`)
    // do not count as code reachability edges per PRD Stage 2 (E3).
  }

  void _checkElement(Element? elem) {
    if (elem == null) return;

    // Check if element belongs to target package.
    final sourcePath =
        elem.library?.firstFragment.source.fullName ??
        elem.firstFragment.libraryFragment?.source.fullName;
    if (sourcePath != null && p.isWithin(packageRoot, sourcePath)) {
      final topLevel = getTopLevelElement(elem);
      if (topLevel != null) {
        referencedTopLevelElements.add(topLevel);
      }
    }
  }

  @override
  void visitNamedType(NamedType node) {
    _checkElement(node.element);
    super.visitNamedType(node);
  }

  @override
  void visitSimpleIdentifier(SimpleIdentifier node) {
    // Avoid recording declaration names as reference usages.
    if (!node.inDeclarationContext()) {
      _checkElement(node.element);
    }
    super.visitSimpleIdentifier(node);
  }

  @override
  void visitConstructorName(ConstructorName node) {
    _checkElement(node.element);
    super.visitConstructorName(node);
  }

  @override
  void visitExtensionOverride(ExtensionOverride node) {
    _checkElement(node.element);
    super.visitExtensionOverride(node);
  }

  @override
  void visitBinaryExpression(BinaryExpression node) {
    _checkElement(node.element);
    super.visitBinaryExpression(node);
  }

  @override
  void visitPrefixExpression(PrefixExpression node) {
    _checkElement(node.element);
    super.visitPrefixExpression(node);
  }

  @override
  void visitPostfixExpression(PostfixExpression node) {
    _checkElement(node.element);
    super.visitPostfixExpression(node);
  }

  @override
  void visitIndexExpression(IndexExpression node) {
    _checkElement(node.element);
    super.visitIndexExpression(node);
  }

  @override
  void visitAnnotation(Annotation node) {
    _checkElement(node.element);
    super.visitAnnotation(node);
  }

  @override
  void visitSuperConstructorInvocation(SuperConstructorInvocation node) {
    _checkElement(node.element);
    super.visitSuperConstructorInvocation(node);
  }

  @override
  void visitRedirectingConstructorInvocation(
    RedirectingConstructorInvocation node,
  ) {
    _checkElement(node.element);
    super.visitRedirectingConstructorInvocation(node);
  }

  @override
  void visitRelationalPattern(RelationalPattern node) {
    _checkElement(node.element);
    super.visitRelationalPattern(node);
  }
}
