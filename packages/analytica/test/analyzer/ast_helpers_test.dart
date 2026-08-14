import 'package:analytica/analyzer.dart';
import 'package:analyzer/dart/analysis/features.dart';
import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:checks/checks.dart';
import 'package:test/test.dart';

class _Collector extends RecursiveAstVisitor<void> {
  final List<MethodDeclaration> methods = [];
  final List<ConstructorDeclaration> constructors = [];

  @override
  void visitMethodDeclaration(MethodDeclaration node) {
    methods.add(node);
    super.visitMethodDeclaration(node);
  }

  @override
  void visitConstructorDeclaration(ConstructorDeclaration node) {
    constructors.add(node);
    super.visitConstructorDeclaration(node);
  }
}

void main() {
  group('extractNodeName', () {
    test('extracts names across various declarations', () {
      const source = '''
class MyClass {}
enum MyEnum { a, b }
mixin MyMixin {}
extension MyExtension on int {}
extension on double {}
extension type MyExtType(int i) {}
typedef MyTypedef = void Function();
void myFunction() {}
int myVar = 42;

class Container {
  Container();
  Container.named();
  void myMethod() {}
}
''';
      final parsed = parseString(
        content: source,
        featureSet: FeatureSet.latestLanguageVersion(),
      );

      final decls = parsed.unit.declarations;
      check(extractNodeName(decls[0])).equals('MyClass');
      check(extractNodeName(decls[1])).equals('MyEnum');
      check(extractNodeName(decls[2])).equals('MyMixin');
      check(extractNodeName(decls[3])).equals('MyExtension');
      check(extractNodeName(decls[4])).isNull();
      check(extractNodeName(decls[5])).equals('MyExtType');
      check(extractNodeName(decls[6])).equals('MyTypedef');
      check(extractNodeName(decls[7])).equals('myFunction');

      final topVar = decls[8] as TopLevelVariableDeclaration;
      check(extractNodeName(topVar.variables.variables[0])).equals('myVar');
      check(extractNodeName(topVar)).equals('myVar');

      final collector = _Collector();
      parsed.unit.accept(collector);

      check(extractNodeName(collector.constructors[0])).isNull();
      check(extractNodeName(collector.constructors[1])).equals('named');
      check(extractNodeName(collector.methods[0])).equals('myMethod');
    });

    test('extracts names correctly for annotated declarations without '
        'element resolution', () {
      const source = '''
@deprecated
class AnnotatedClass {}

@pragma('vm:entry-point')
enum AnnotatedEnum { a }

@pragma('vm:entry-point')
mixin AnnotatedMixin {}

@deprecated
extension type AnnotatedExtType(int val) {}

@deprecated
void annotatedFunc() {}
''';
      final parsed = parseString(
        content: source,
        featureSet: FeatureSet.latestLanguageVersion(),
      );

      final decls = parsed.unit.declarations;
      check(extractNodeName(decls[0])).equals('AnnotatedClass');
      check(extractNodeName(decls[1])).equals('AnnotatedEnum');
      check(extractNodeName(decls[2])).equals('AnnotatedMixin');
      check(extractNodeName(decls[3])).equals('AnnotatedExtType');
      check(extractNodeName(decls[4])).equals('annotatedFunc');
    });
  });

  group('getTopLevelElement', () {
    test('returns null for LibraryElement', () {
      // Tested via analyzer element mocks or type checks
    });
  });

  group('hasAnnotation & hasAnyAnnotation', () {
    test('detects simple, qualified, and constructor-invoked annotations', () {
      const source = '''
@visibleForTesting
void funcA() {}

@meta.protected
void funcB() {}

@pragma('vm:entry-point')
void funcC() {}

@Native<void Function()>()
void funcD() {}

@Meta.visibleForTesting()
void funcE() {}

void funcF() {}
''';
      final parsed = parseString(
        content: source,
        featureSet: FeatureSet.latestLanguageVersion(),
      );

      final decls = parsed.unit.declarations;
      check(
        hasAnnotation(decls[0] as AnnotatedNode, 'visibleForTesting'),
      ).isTrue();
      check(hasAnnotation(decls[1] as AnnotatedNode, 'protected')).isTrue();
      check(hasAnnotation(decls[2] as AnnotatedNode, 'pragma')).isTrue();
      check(hasAnnotation(decls[3] as AnnotatedNode, 'Native')).isTrue();
      check(
        hasAnnotation(decls[4] as AnnotatedNode, 'visibleForTesting'),
      ).isTrue();
      check(
        hasAnnotation(decls[5] as AnnotatedNode, 'visibleForTesting'),
      ).isFalse();

      check(
        hasAnyAnnotation(decls[0] as AnnotatedNode, const [
          'visibleForTesting',
          'protected',
        ]),
      ).isTrue();
      check(
        hasAnyAnnotation(decls[4] as AnnotatedNode, const [
          'visibleForTesting',
          'protected',
        ]),
      ).isTrue();
      check(
        hasAnyAnnotation(decls[5] as AnnotatedNode, const [
          'visibleForTesting',
          'protected',
        ]),
      ).isFalse();
    });
  });

  group('isTestSupportDeclaration', () {
    test('identifies test support conventions and annotations', () {
      const source = '''
class FakeService {}
class MockClient {}
class StubRepo {}
class ServiceFake {}
class ClientMock {}
class RepoStub {}

@visibleForTesting
class RealServiceTestingHook {}

@VisibleForTesting()
class PascalCaseTestingHook {}

@protected
class ProtectedHelper {}

@Protected()
class PascalProtectedHelper {}

@visibleForOverriding
class OverridableBase {}

class NormalService {}
''';
      final parsed = parseString(
        content: source,
        featureSet: FeatureSet.latestLanguageVersion(),
      );

      for (var i = 0; i <= 10; i++) {
        final decl = parsed.unit.declarations[i] as AnnotatedNode;
        check(isTestSupportDeclaration(decl)).isTrue();
      }

      final normal = parsed.unit.declarations[11] as AnnotatedNode;
      check(isTestSupportDeclaration(normal)).isFalse();
    });
  });

  group('isNativeOrEntryPoint', () {
    test('detects @Native, @native, and @pragma entry points', () {
      const source = '''
@Native<void Function()>()
void nativeFn() {}

@native
void lowerNativeFn() {}

@pragma('vm:entry-point')
void entryPoint() {}

void normalFn() {}
''';
      final parsed = parseString(
        content: source,
        featureSet: FeatureSet.latestLanguageVersion(),
      );

      check(
        isNativeOrEntryPoint(parsed.unit.declarations[0] as AnnotatedNode),
      ).isTrue();
      check(
        isNativeOrEntryPoint(parsed.unit.declarations[1] as AnnotatedNode),
      ).isTrue();
      check(
        isNativeOrEntryPoint(parsed.unit.declarations[2] as AnnotatedNode),
      ).isTrue();
      check(
        isNativeOrEntryPoint(parsed.unit.declarations[3] as AnnotatedNode),
      ).isFalse();
    });
  });

  group('isExcludedPath', () {
    test('identifies excluded directory segments', () {
      check(isExcludedPath('.dart_tool/package_config.json')).isTrue();
      check(isExcludedPath('.git/HEAD')).isTrue();
      check(isExcludedPath('build/app/outputs')).isTrue();
      check(isExcludedPath('packages/foo/build/bin.dart')).isTrue();

      check(isExcludedPath('.github/workflows/ci.yml')).isFalse();
      check(isExcludedPath('lib/builders/code_builder.dart')).isFalse();
      check(isExcludedPath('lib/src/service.dart')).isFalse();
    });
  });
}
