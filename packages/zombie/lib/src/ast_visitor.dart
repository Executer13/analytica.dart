import 'package:analytica/analyzer.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:path/path.dart' as p;

export 'package:analytica/analyzer.dart'
    show
        extractNodeName,
        getTopLevelElement,
        isNativeOrEntryPoint,
        isTestSupportDeclaration;

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
  void visitAssignmentExpression(AssignmentExpression node) {
    _checkElement(node.element);
    _checkElement(node.readElement);
    _checkElement(node.writeElement);
    super.visitAssignmentExpression(node);
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
