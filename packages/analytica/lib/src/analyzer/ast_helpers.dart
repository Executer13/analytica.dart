import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/token.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:path/path.dart' as p;

const _declarationHeaderKeywords = {
  'abstract',
  'augment',
  'base',
  'extension',
  'external',
  'final',
  'interface',
  'late',
  'macro',
  'mixin',
  'sealed',
  'type',
};

/// Extracts a string name from an AST node safely.
///
/// Supports [ClassDeclaration], [FunctionDeclaration], [EnumDeclaration],
/// [MixinDeclaration], [ExtensionDeclaration], [ExtensionTypeDeclaration],
/// [TypeAlias], [VariableDeclaration], [MethodDeclaration],
/// and [ConstructorDeclaration], falling back to recursive identifier token
/// scanning.
String? extractNodeName(AstNode node) {
  if (node is ClassDeclaration) {
    return node.declaredFragment?.element.name ?? _findFirstIdentifier(node);
  }
  if (node is EnumDeclaration) {
    return node.declaredFragment?.element.name ?? _findFirstIdentifier(node);
  }
  if (node is MixinDeclaration) {
    return node.declaredFragment?.element.name ?? node.name.lexeme;
  }
  if (node is ExtensionDeclaration) {
    return node.declaredFragment?.element.name ?? node.name?.lexeme;
  }
  if (node is ExtensionTypeDeclaration) {
    return node.declaredFragment?.element.name ?? _findFirstIdentifier(node);
  }
  if (node is TypeAlias) {
    return node.declaredFragment?.element.name ?? node.name.lexeme;
  }
  if (node is FunctionDeclaration) {
    return node.declaredFragment?.element.name ?? node.name.lexeme;
  }
  if (node is VariableDeclaration) {
    return node.declaredFragment?.element.name ?? node.name.lexeme;
  }
  if (node is MethodDeclaration) {
    return node.declaredFragment?.element.name ?? node.name.lexeme;
  }
  if (node is ConstructorDeclaration) {
    final constName = node.name?.lexeme;
    return node.declaredFragment?.element.name ?? constName;
  }
  if (node is TopLevelVariableDeclaration) {
    if (node.variables.variables.isNotEmpty) {
      return extractNodeName(node.variables.variables.first);
    }
  }
  if (node is FieldDeclaration) {
    if (node.fields.variables.isNotEmpty) {
      return extractNodeName(node.fields.variables.first);
    }
  }
  return _findFirstIdentifier(node);
}

String? _findFirstIdentifier(AstNode node) {
  for (final entity in node.childEntities) {
    if (entity is NodeList<Annotation> || entity is Annotation) {
      continue;
    }
    if (entity is Token &&
        entity.type == TokenType.IDENTIFIER &&
        !_declarationHeaderKeywords.contains(entity.lexeme)) {
      return entity.lexeme;
    }
    if (entity is AstNode) {
      final nested = _findFirstIdentifier(entity);
      if (nested != null) return nested;
    }
  }
  return null;
}

/// Finds the enclosing top-level element for a given element by climbing
/// the enclosing hierarchy until reaching the library element or null.
Element? getTopLevelElement(Element elem) {
  if (elem is LibraryElement) return null;
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

/// Checks if an [AnnotatedNode] contains an annotation with the given
/// [annotationName] (e.g. `'visibleForTesting'`, `'pragma'`, `'Native'`).
///
/// Matches both simple names (e.g. `@visibleForTesting`), prefixed names
/// (e.g. `@meta.visibleForTesting`), and constructor invocations
/// (e.g. `@Meta.visibleForTesting()`).
bool hasAnnotation(AnnotatedNode node, String annotationName) {
  for (final meta in node.metadata) {
    final rawName = meta.name.name;
    final baseName = rawName.contains('.') ? rawName.split('.').last : rawName;
    if (baseName == annotationName) {
      return true;
    }
    final constructorName = meta.constructorName?.name;
    if (constructorName == annotationName) {
      return true;
    }
  }
  return false;
}

/// Checks if an [AnnotatedNode] has any of the given [annotationNames].
bool hasAnyAnnotation(AnnotatedNode node, Iterable<String> annotationNames) {
  final nameSet = annotationNames.toSet();
  for (final meta in node.metadata) {
    final rawName = meta.name.name;
    final baseName = rawName.contains('.') ? rawName.split('.').last : rawName;
    if (nameSet.contains(baseName)) {
      return true;
    }
    final constructorName = meta.constructorName?.name;
    if (constructorName != null && nameSet.contains(constructorName)) {
      return true;
    }
  }
  return false;
}

/// Checks if an element or AST node has test support annotations or
/// conventions.
///
/// Checks for `@visibleForTesting`, `@visibleForOverriding`, `@protected`,
/// or if [name] starts/ends with `Fake`, `Mock`, or `Stub`.
bool isTestSupportDeclaration(AnnotatedNode node, [String? name]) {
  final effectiveName = name ?? extractNodeName(node);
  if (effectiveName != null) {
    if (effectiveName.startsWith('Fake') ||
        effectiveName.startsWith('Mock') ||
        effectiveName.startsWith('Stub') ||
        effectiveName.endsWith('Fake') ||
        effectiveName.endsWith('Mock') ||
        effectiveName.endsWith('Stub')) {
      return true;
    }
  }

  return hasAnyAnnotation(node, const [
    'visibleForTesting',
    'VisibleForTesting',
    'visibleForOverriding',
    'VisibleForOverriding',
    'protected',
    'Protected',
  ]);
}

/// Checks if an AST node has native or runtime entrypoint annotations
/// (`@Native` or `@pragma`).
bool isNativeOrEntryPoint(AnnotatedNode node) {
  return hasAnyAnnotation(node, const ['Native', 'native', 'pragma']);
}

/// Whether [relativePath] sits inside a directory that should never be
/// scanned (`.dart_tool`, `.git`, or `build` output).
///
/// Matches whole path segments, so `.github/` or `builders/` are not
/// mistaken for `.git/` or `build/`.
bool isExcludedPath(String relativePath) {
  final segments = p.split(p.normalize(relativePath));
  return segments.contains('.dart_tool') ||
      segments.contains('.git') ||
      segments.contains('build');
}
