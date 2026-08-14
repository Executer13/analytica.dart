import 'package:checks/checks.dart';
import 'package:test/test.dart';
import 'package:test_descriptor/test_descriptor.dart' as d;
import 'package:zombie/zombie.dart';

d.DirectoryDescriptor packageConfig(String pkgName) {
  return d.dir('.dart_tool', [
    d.file('package_config.json', '''
{
  "configVersion": 2,
  "packages": [
    {
      "name": "$pkgName",
      "rootUri": "../",
      "packageUri": "lib/",
      "languageVersion": "3.5"
    }
  ]
}
'''),
  ]);
}

void main() {
  group('ReachabilityEngine', () {
    test('detects unexported top-level function as pure zombie', () async {
      await d.dir('pure_zombie_pkg', [
        packageConfig('pure_zombie_pkg'),
        d.file('pubspec.yaml', '''
name: pure_zombie_pkg
environment:
  sdk: '^3.5.0'
'''),
        d.dir('lib', [
          d.file('pure_zombie_pkg.dart', '''
export 'src/live.dart';
'''),
          d.dir('src', [
            d.file('live.dart', 'void liveFunc() {}'),
            d.file('dead.dart', 'void deadFunc() {}'),
          ]),
        ]),
      ]).create();

      final report = await analyzePackage(d.path('pure_zombie_pkg'));
      check(report.pureZombiesFound).equals(1);
      check(report.testedZombiesFound).equals(0);
      check(report.coInvokedHazardsFound).equals(0);

      final zombie = report.zombies.single;
      check(zombie.name).equals('deadFunc');
      check(zombie.kind).equals(DeclarationKind.function);
      check(zombie.classification).equals(ZombieClassification.pureZombie);
      check(zombie.suggestedAction).equals(SuggestedAction.delete);
    });

    test('detects tested zombie and associates orphan test sites', () async {
      await d.dir('tested_zombie_pkg', [
        packageConfig('tested_zombie_pkg'),
        d.file('pubspec.yaml', '''
name: tested_zombie_pkg
environment:
  sdk: '^3.5.0'
'''),
        d.dir('lib', [
          d.file('tested_zombie_pkg.dart', '''
export 'src/live.dart';
'''),
          d.dir('src', [
            d.file('live.dart', 'class LiveService {}'),
            d.file('old_parser.dart', '''
class OldParser {
  String parse(String s) => s.toLowerCase();
}
'''),
          ]),
        ]),
        d.dir('test', [
          d.file('old_parser_test.dart', '''
import 'package:tested_zombie_pkg/src/old_parser.dart';

void test(String desc, Function body) {}

void main() {
  test('OldParser parses correctly', () {
    final parser = OldParser();
    parser.parse('FOO');
  });
}
'''),
        ]),
      ]).create();

      final report = await analyzePackage(d.path('tested_zombie_pkg'));
      check(report.pureZombiesFound).equals(0);
      check(report.testedZombiesFound).equals(1);
      check(report.coInvokedHazardsFound).equals(0);

      final zombie = report.zombies.single;
      check(zombie.name).equals('OldParser');
      check(zombie.kind).equals(DeclarationKind.classType);
      check(zombie.classification).equals(ZombieClassification.testedZombie);
      check(
        zombie.suggestedAction,
      ).equals(SuggestedAction.deleteWithOrphanTests);

      final orphanTests = zombie.orphanTests!;
      check(orphanTests.length).equals(1);
      check(orphanTests.first.file).equals('test/old_parser_test.dart');
      check(orphanTests.first.description).equals('OldParser parses correctly');
      check(orphanTests.first.coInvokedHazard).isFalse();
    });

    test(
      'detects co-invoked test hazard when test references live and dead code',
      () async {
        await d.dir('co_invoked_pkg', [
          packageConfig('co_invoked_pkg'),
          d.file('pubspec.yaml', '''
name: co_invoked_pkg
environment:
  sdk: '^3.5.0'
'''),
          d.dir('lib', [
            d.file('co_invoked_pkg.dart', '''
export 'src/live.dart';
'''),
            d.dir('src', [
              d.file('live.dart', '''
class LivePipeline {
  void process(String input) {}
}
'''),
              d.file('legacy_helper.dart', '''
class LegacyHelper {
  static String format(String s) => s.trim();
}
'''),
            ]),
          ]),
          d.dir('test', [
            d.file('pipeline_test.dart', '''
import 'package:co_invoked_pkg/src/legacy_helper.dart';
import 'package:co_invoked_pkg/src/live.dart';

void test(String desc, Function body) {}

void main() {
  test('pipeline formats output', () {
    final intermediate = LegacyHelper.format(' input ');
    final pipeline = LivePipeline();
    pipeline.process(intermediate);
  });
}
'''),
          ]),
        ]).create();

        final report = await analyzePackage(d.path('co_invoked_pkg'));
        check(report.pureZombiesFound).equals(0);
        check(report.testedZombiesFound).equals(0);
        check(report.coInvokedHazardsFound).equals(1);

        final hazard = report.zombies.single;
        check(hazard.name).equals('LegacyHelper');
        check(
          hazard.classification,
        ).equals(ZombieClassification.coInvokedHazard);
        check(
          hazard.suggestedAction,
        ).equals(SuggestedAction.manualRefactorHazard);

        final orphanTests = hazard.orphanTests!;
        check(orphanTests.first.coInvokedHazard).isTrue();
      },
    );

    test('preserves direct subtypes of live sealed classes for pattern '
        'exhaustiveness', () async {
      await d.dir('sealed_pkg', [
        packageConfig('sealed_pkg'),
        d.file('pubspec.yaml', '''
name: sealed_pkg
environment:
  sdk: '^3.5.0'
'''),
        d.dir('lib', [
          d.file('sealed_pkg.dart', '''
export 'src/ast.dart';
'''),
          d.dir('src', [
            d.file('ast.dart', '''
sealed class AstNode {}
class LiteralNode extends AstNode {}
class IdentifierNode extends AstNode {}
// Uninstantiated subtype required for switch exhaustiveness:
class UnusedCommentNode extends AstNode {}
'''),
          ]),
        ]),
      ]).create();

      final report = await analyzePackage(d.path('sealed_pkg'));
      check(report.zombies).isEmpty();
      check(report.pureZombiesFound).equals(0);
    });

    test(
      'preserves exported symbols under Open-World Invariant (library mode)',
      () async {
        await d.dir('open_world_pkg', [
          packageConfig('open_world_pkg'),
          d.file('pubspec.yaml', '''
name: open_world_pkg
environment:
  sdk: '^3.5.0'
'''),
          d.dir('lib', [
            d.file('open_world_pkg.dart', '''
export 'src/public_feature.dart';
'''),
            d.dir('src', [
              d.file('public_feature.dart', '''
class PublicClient {
  void connect() {}
}
'''),
              d.file('internal_dead.dart', '''
class InternalDead {}
'''),
            ]),
          ]),
        ]).create();

        final report = await analyzePackage(d.path('open_world_pkg'));
        check(report.zombies.length).equals(1);
        check(report.zombies.single.name).equals('InternalDead');
      },
    );

    test('flags unreferenced exports under closed-app mode', () async {
      await d.dir('closed_app_pkg', [
        packageConfig('closed_app_pkg'),
        d.file('pubspec.yaml', '''
name: closed_app_pkg
environment:
  sdk: '^3.5.0'
'''),
        d.dir('lib', [
          d.file('closed_app_pkg.dart', '''
export 'src/unused_feature.dart';
'''),
          d.dir('src', [
            d.file('unused_feature.dart', '''
class UnusedFeature {}
'''),
          ]),
        ]),
        d.dir('bin', [
          d.file('main.dart', '''
void main() {
  print('App running');
}
'''),
        ]),
      ]).create();

      final report = await analyzePackage(
        d.path('closed_app_pkg'),
        options: ZombieOptions(
          packagePath: d.path('closed_app_pkg'),
          mode: AnalysisMode.closedApp,
        ),
      );

      check(report.zombies.length).equals(1);
      check(report.zombies.single.name).equals('UnusedFeature');
    });

    test('preserves code in example/ under demonstration mode', () async {
      await d.dir('example_demo_pkg', [
        packageConfig('example_demo_pkg'),
        d.file('pubspec.yaml', '''
name: example_demo_pkg
environment:
  sdk: '^3.5.0'
'''),
        d.dir('lib', [
          d.file('example_demo_pkg.dart', 'export "src/live.dart";'),
          d.dir('src', [
            d.file('live.dart', 'class MySdkClient {}'),
            d.file('helper_for_demo.dart', 'class DemoHelper {}'),
          ]),
        ]),
        d.dir('example', [
          d.file('main.dart', '''
import 'package:example_demo_pkg/src/helper_for_demo.dart';

// Illustrative model on pub.dev, not instantiated in main:
class UserExampleModel {
  final String name;
  UserExampleModel(this.name);
}

void main() {
  final helper = DemoHelper();
  print(helper);
}
'''),
        ]),
      ]).create();

      final report = await analyzePackage(d.path('example_demo_pkg'));
      check(report.zombies).isEmpty();
    });

    test('preserves platform-conditional import branches', () async {
      await d.dir('conditional_pkg', [
        packageConfig('conditional_pkg'),
        d.file('pubspec.yaml', '''
name: conditional_pkg
environment:
  sdk: '^3.5.0'
'''),
        d.dir('lib', [
          d.file('conditional_pkg.dart', '''
export 'src/platform_io.dart'
  if (dart.library.js_interop) 'src/platform_web.dart';
'''),
          d.dir('src', [
            d.file('platform_io.dart', 'class PlatformImplementation {}'),
            d.file('platform_web.dart', 'class PlatformWebImplementation {}'),
            d.file('dead_util.dart', 'class DeadUtil {}'),
          ]),
        ]),
      ]).create();

      final report = await analyzePackage(d.path('conditional_pkg'));
      check(report.zombies.length).equals(1);
      check(report.zombies.single.name).equals('DeadUtil');
    });

    test(
      'respects // zombie:ignore and // zombie:ignore_for_file directives',
      () async {
        await d.dir('suppression_pkg', [
          packageConfig('suppression_pkg'),
          d.file('pubspec.yaml', '''
name: suppression_pkg
environment:
  sdk: '^3.5.0'
'''),
          d.dir('lib', [
            d.file('suppression_pkg.dart', 'export "src/live.dart";'),
            d.dir('src', [
              d.file('live.dart', 'void live() {}'),
              d.file('ignored_file.dart', '''
// zombie:ignore_for_file
class IgnoredFileClass {}
void ignoredFileFunc() {}
'''),
              d.file('ignored_decl.dart', '''
// zombie:ignore
class IgnoredClass {}

class DeadUnignoredClass {}
'''),
            ]),
          ]),
        ]).create();

        final report = await analyzePackage(d.path('suppression_pkg'));
        check(report.zombies.length).equals(1);
        check(report.zombies.single.name).equals('DeadUnignoredClass');
      },
    );

    test('preserves test support hooks annotated @visibleForTesting or named '
        'Fake*', () async {
      await d.dir('test_support_pkg', [
        packageConfig('test_support_pkg'),
        d.file('pubspec.yaml', '''
name: test_support_pkg
environment:
  sdk: '^3.5.0'
'''),
        d.dir('lib', [
          d.file('test_support_pkg.dart', 'export "src/live.dart";'),
          d.dir('src', [
            d.file('live.dart', 'class LiveClass {}'),
            d.file('fixtures.dart', '''
import 'package:meta/meta.dart';

@visibleForTesting
void resetInternalTestCache() {}

class FakeBackendService {}
class DeadWithoutHook {}
'''),
          ]),
        ]),
        d.dir('test', [
          d.file('cache_test.dart', '''
import 'package:test_support_pkg/src/fixtures.dart';

void test(String desc, Function body) {}

void main() {
  test('cache resets', () {
    resetInternalTestCache();
    final fake = FakeBackendService();
    print(fake);
  });
}
'''),
        ]),
      ]).create();

      final report = await analyzePackage(d.path('test_support_pkg'));
      check(report.zombies.length).equals(1);
      check(report.zombies.single.name).equals('DeadWithoutHook');
    });

    test('traverses executables (bin/) and auxiliary (tool/) entrypoints to '
        'lib/src/', () async {
      await d.dir('bin_tool_pkg', [
        packageConfig('bin_tool_pkg'),
        d.file('pubspec.yaml', '''
name: bin_tool_pkg
environment:
  sdk: '^3.5.0'
'''),
        d.dir('lib', [
          d.file('bin_tool_pkg.dart', 'void exported() {}'),
          d.dir('src', [
            d.file('bin_helper.dart', 'void binUtil() {}'),
            d.file('tool_helper.dart', 'void toolUtil() {}'),
            d.file('dead_helper.dart', 'void deadUtil() {}'),
          ]),
        ]),
        d.dir('bin', [
          d.file('my_cli.dart', '''
import 'package:bin_tool_pkg/src/bin_helper.dart';

void main() {
  binUtil();
}
'''),
        ]),
        d.dir('tool', [
          d.file('benchmark.dart', '''
import 'package:bin_tool_pkg/src/tool_helper.dart';

void main() {
  toolUtil();
}
'''),
        ]),
      ]).create();

      final report = await analyzePackage(d.path('bin_tool_pkg'));
      check(report.zombies.length).equals(1);
      check(report.zombies.single.name).equals('deadUtil');
    });

    test('scans diverse top-level declarations (enums, mixins, extensions, '
        'getters, setters, vars)', () async {
      await d.dir('decl_types_pkg', [
        packageConfig('decl_types_pkg'),
        d.file('pubspec.yaml', '''
name: decl_types_pkg
environment:
  sdk: '^3.5.0'
'''),
        d.dir('lib', [
          d.file('decl_types_pkg.dart', 'export "src/live.dart";'),
          d.dir('src', [
            d.file('live.dart', '''
import 'dead_decls.dart';

class LiveContainer {
  void use() {
    print(liveTopVar);
    final e = LiveEnum.val;
    print(e);
  }
}
'''),
            d.file('dead_decls.dart', '''
enum LiveEnum { val }
int liveTopVar = 1;

enum DeadEnum { a, b }
mixin DeadMixin {}
extension DeadExtension on String {}
extension type DeadExtType(int value) {}
typedef DeadAlias = int Function();
int deadTopVar = 42;
int get deadGetter => 10;
set deadSetter(int v) {}
'''),
          ]),
        ]),
      ]).create();

      final report = await analyzePackage(d.path('decl_types_pkg'));
      final names = report.zombies.map((z) => z.name).toSet();

      check(names).contains('DeadEnum');
      check(names).contains('DeadMixin');
      check(names).contains('DeadExtension');
      check(names).contains('DeadExtType');
      check(names).contains('DeadAlias');
      check(names).contains('deadTopVar');
      check(names).contains('deadGetter');
      check(names).contains('deadSetter');

      check(names).not((it) => it.contains('LiveEnum'));
      check(names).not((it) => it.contains('liveTopVar'));
    });

    test('correctly distinguishes tested zombie from co-invoked hazard in '
        'multi-test file', () async {
      await d.dir('multi_test_pkg', [
        packageConfig('multi_test_pkg'),
        d.file('pubspec.yaml', '''
name: multi_test_pkg
environment:
  sdk: '^3.5.0'
'''),
        d.dir('lib', [
          d.file('multi_test_pkg.dart', 'export "src/live.dart";'),
          d.dir('src', [
            d.file('live.dart', 'class LiveService { void run() {} }'),
            d.file('dead_parser.dart', 'class DeadParser { void parse() {} }'),
          ]),
        ]),
        d.dir('test', [
          d.file('combined_test.dart', '''
import 'package:multi_test_pkg/src/dead_parser.dart';
import 'package:multi_test_pkg/src/live.dart';

void test(String desc, Function body) {}

void main() {
  test('isolated dead parser test', () {
    final parser = DeadParser();
    parser.parse();
  });

  test('separate live service test', () {
    final service = LiveService();
    service.run();
  });
}
'''),
        ]),
      ]).create();

      final report = await analyzePackage(d.path('multi_test_pkg'));
      check(report.pureZombiesFound).equals(0);
      check(report.testedZombiesFound).equals(1);
      check(report.coInvokedHazardsFound).equals(0);

      final zombie = report.zombies.single;
      check(zombie.name).equals('DeadParser');
      check(zombie.classification).equals(ZombieClassification.testedZombie);
      check(
        zombie.suggestedAction,
      ).equals(SuggestedAction.deleteWithOrphanTests);

      final orphanTests = zombie.orphanTests!;
      check(orphanTests.length).equals(1);
      check(orphanTests.first.description).equals('isolated dead parser test');
      check(orphanTests.first.coInvokedHazard).isFalse();
    });

    test(
      'preserves sealed class direct subtypes via implements, with, and enums',
      () async {
        await d.dir('sealed_hierarchy_pkg', [
          packageConfig('sealed_hierarchy_pkg'),
          d.file('pubspec.yaml', '''
name: sealed_hierarchy_pkg
environment:
  sdk: '^3.5.0'
'''),
          d.dir('lib', [
            d.file('sealed_hierarchy_pkg.dart', 'export "src/union.dart";'),
            d.dir('src', [
              d.file('union.dart', '''
sealed class ResultType {}
class SuccessResult implements ResultType {}
enum ErrorResult implements ResultType { notFound, invalid }
mixin SpecialResult on ResultType {}
'''),
            ]),
          ]),
        ]).create();

        final report = await analyzePackage(d.path('sealed_hierarchy_pkg'));
        check(report.zombies).isEmpty();
      },
    );

    test(
      'preserves foreign/native entrypoints annotated with @pragma or @Native',
      () async {
        await d.dir('native_pkg', [
          packageConfig('native_pkg'),
          d.file('pubspec.yaml', '''
name: native_pkg
environment:
  sdk: '^3.5.0'
'''),
          d.dir('lib', [
            d.file('native_pkg.dart', 'void exported() {}'),
            d.dir('src', [
              d.file('native_callbacks.dart', '''
@pragma('vm:entry-point')
void vmEntryPoint() {}

class DeadInternalClass {}
'''),
            ]),
          ]),
        ]).create();

        final report = await analyzePackage(d.path('native_pkg'));
        check(report.zombies.length).equals(1);
        check(report.zombies.single.name).equals('DeadInternalClass');
      },
    );

    test('preserves test hooks with prefixed annotations like '
        '@meta.visibleForTesting', () async {
      await d.dir('prefixed_meta_pkg', [
        packageConfig('prefixed_meta_pkg'),
        d.file('pubspec.yaml', '''
name: prefixed_meta_pkg
environment:
  sdk: '^3.5.0'
'''),
        d.dir('lib', [
          d.file('prefixed_meta_pkg.dart', 'export "src/live.dart";'),
          d.dir('src', [
            d.file('live.dart', 'class LiveClass {}'),
            d.file('hook.dart', '''
import 'package:meta/meta.dart' as meta;

@meta.visibleForTesting
void internalTestHook() {}
'''),
          ]),
        ]),
        d.dir('test', [
          d.file('hook_test.dart', '''
import 'package:prefixed_meta_pkg/src/hook.dart';

void test(String desc, Function body) {}

void main() {
  test('invokes hook', () {
    internalTestHook();
  });
}
'''),
        ]),
      ]).create();

      final report = await analyzePackage(d.path('prefixed_meta_pkg'));
      check(report.zombies).isEmpty();
    });

    test('reaches extension operator overloads in expressions', () async {
      await d.dir('operator_pkg', [
        packageConfig('operator_pkg'),
        d.file('pubspec.yaml', '''
name: operator_pkg
environment:
  sdk: '^3.5.0'
'''),
        d.dir('lib', [
          d.file('operator_pkg.dart', 'export "src/live.dart";'),
          d.dir('src', [
            d.file('live.dart', '''
import 'operators.dart';

class LiveContainer {
  void calculate() {
    final a = CustomNum(5);
    final b = a + 10;
    print(b);
  }
}
'''),
            d.file('operators.dart', '''
class CustomNum {
  final int val;
  const CustomNum(this.val);
}

extension CustomNumOps on CustomNum {
  CustomNum operator +(int other) => CustomNum(val + other);
}

extension DeadOps on CustomNum {
  CustomNum operator -(int other) => CustomNum(val - other);
}
'''),
          ]),
        ]),
      ]).create();

      final report = await analyzePackage(d.path('operator_pkg'));
      check(report.zombies.length).equals(1);
      check(report.zombies.single.name).equals('DeadOps');
    });

    test(
      'resolves same-package package: URIs in conditional imports',
      () async {
        await d.dir('package_uri_cond_pkg', [
          packageConfig('package_uri_cond_pkg'),
          d.file('pubspec.yaml', '''
name: package_uri_cond_pkg
environment:
  sdk: '^3.5.0'
'''),
          d.dir('lib', [
            d.file('package_uri_cond_pkg.dart', '''
export 'src/platform_io.dart'
  if (dart.library.js_interop)
    'package:package_uri_cond_pkg/src/platform_web.dart';
'''),
            d.dir('src', [
              d.file('platform_io.dart', 'class IoPlatform {}'),
              d.file('platform_web.dart', 'class WebPlatform {}'),
              d.file('dead.dart', 'class UnusedDead {}'),
            ]),
          ]),
        ]).create();

        final report = await analyzePackage(d.path('package_uri_cond_pkg'));
        check(report.zombies.length).equals(1);
        check(report.zombies.single.name).equals('UnusedDead');
      },
    );
  });
}
