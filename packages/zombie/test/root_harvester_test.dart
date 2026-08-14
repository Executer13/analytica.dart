import 'package:checks/checks.dart';
import 'package:test/test.dart';
import 'package:test_descriptor/test_descriptor.dart' as d;
import 'package:zombie/src/models.dart';
import 'package:zombie/src/root_harvester.dart';

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
  group('RootHarvester & PackageTopology', () {
    test(
      'throws PackageResolutionException on missing package_config',
      () async {
        await d.dir('unresolved_pkg', [
          d.file('pubspec.yaml', 'name: unresolved_pkg\n'),
          d.dir('lib', [d.file('unresolved_pkg.dart', 'void foo() {}')]),
        ]).create();

        final options = ZombieOptions(packagePath: d.path('unresolved_pkg'));
        final harvester = RootHarvester(options);

        check(
          harvester.harvestTopology,
        ).throws<PackageResolutionException>().which(
          (it) => it
              .has((e) => e.message, 'message')
              .contains('Missing .dart_tool/package_config.json'),
        );
      },
    );

    test('discovers package directory topology correctly', () async {
      await d.dir('sample_pkg', [
        packageConfig('sample_pkg'),
        d.file('pubspec.yaml', '''
name: sample_pkg
version: 1.0.0
flutter:
  plugin:
    platforms:
      android:
        dartPluginClass: SampleAndroidPlugin
'''),
        d.file('build.yaml', '''
targets:
  \$default:
    builders:
      sample_pkg|builder:
        builder_factories: ["sampleBuilderFactory", "secondaryFactory"]
'''),
        d.dir('lib', [
          d.file('sample_pkg.dart', 'export "src/live.dart";'),
          d.dir('src', [
            d.file('live.dart', 'void live() {}'),
            d.file('generated.g.dart', 'void generated() {}'),
          ]),
        ]),
        d.dir('bin', [d.file('sample_cli.dart', 'void main() {}')]),
        d.dir('example', [d.file('sample_example.dart', 'void main() {}')]),
        d.dir('tool', [d.file('generate.dart', 'void main() {}')]),
        d.dir('test', [d.file('sample_test.dart', 'void main() {}')]),
      ]).create();

      final options = ZombieOptions(
        packagePath: d.path('sample_pkg'),
        includeGenerated: false,
      );

      final harvester = RootHarvester(options);
      final topology = harvester.harvestTopology();

      check(topology.packageName).equals('sample_pkg');
      check(topology.pluginClassNames).contains('SampleAndroidPlugin');
      check(topology.builderFactoryNames).contains('sampleBuilderFactory');
      check(topology.builderFactoryNames).contains('secondaryFactory');

      check(topology.publicLibFiles).length.equals(1);
      check(topology.internalSrcFiles).length.equals(1); // .g.dart ignored
      check(topology.executableFiles).length.equals(1);
      check(topology.demonstrationFiles).length.equals(1);
      check(topology.auxiliaryFiles).length.equals(1);
      check(topology.testFiles).length.equals(1);

      check(topology.roleOf('lib/sample_pkg.dart')).equals(FileRole.publicLib);
      check(topology.roleOf('lib/src/live.dart')).equals(FileRole.internalSrc);
      check(topology.roleOf('bin/sample_cli.dart')).equals(FileRole.executable);
      check(
        topology.roleOf('example/sample_example.dart'),
      ).equals(FileRole.demonstration);
      check(topology.roleOf('tool/generate.dart')).equals(FileRole.auxiliary);
      check(topology.roleOf('test/sample_test.dart')).equals(FileRole.test);
    });

    test('respects ExampleMode.skip', () async {
      await d.dir('skip_example_pkg', [
        packageConfig('skip_example_pkg'),
        d.file('pubspec.yaml', 'name: skip_example_pkg\n'),
        d.dir('lib', [d.file('main.dart', 'void foo() {}')]),
        d.dir('example', [d.file('demo.dart', 'void main() {}')]),
      ]).create();

      final options = ZombieOptions(
        packagePath: d.path('skip_example_pkg'),
        exampleMode: ExampleMode.skip,
      );

      final harvester = RootHarvester(options);
      final topology = harvester.harvestTopology();

      check(topology.demonstrationFiles).isEmpty();
    });

    test('identifies Flutter entrypoints correctly', () {
      check(PackageTopology.isFlutterEntrypoint('lib/main.dart')).isTrue();
      check(PackageTopology.isFlutterEntrypoint('lib/main_dev.dart')).isTrue();
      check(
        PackageTopology.isFlutterEntrypoint('lib/main_production.dart'),
      ).isTrue();
      check(PackageTopology.isFlutterEntrypoint(r'lib\main.dart')).isTrue();
      check(
        PackageTopology.isFlutterEntrypoint(r'lib\main_prod.dart'),
      ).isTrue();

      check(PackageTopology.isFlutterEntrypoint('lib/src/main.dart')).isFalse();
      check(PackageTopology.isFlutterEntrypoint('bin/main.dart')).isFalse();
      check(PackageTopology.isFlutterEntrypoint('lib/other.dart')).isFalse();
    });

    test('does not exclude lib/src/build/ source directory', () async {
      await d.dir('nested_build_pkg', [
        packageConfig('nested_build_pkg'),
        d.file('pubspec.yaml', 'name: nested_build_pkg\n'),
        d.dir('lib', [
          d.file('nested_build_pkg.dart', 'export "src/build/builder.dart";'),
          d.dir('src', [
            d.dir('build', [d.file('builder.dart', 'void buildHelper() {}')]),
          ]),
        ]),
        d.dir('build', [d.file('output.dart', 'void shouldBeExcluded() {}')]),
      ]).create();

      final options = ZombieOptions(packagePath: d.path('nested_build_pkg'));
      final harvester = RootHarvester(options);
      final topology = harvester.harvestTopology();

      check(topology.internalSrcFiles).contains('lib/src/build/builder.dart');
      check(topology.allFiles).not((it) => it.contains('build/output.dart'));
    });

    test('extracts multi-line YAML builder_factories correctly', () async {
      await d.dir('multiline_build_pkg', [
        packageConfig('multiline_build_pkg'),
        d.file('pubspec.yaml', 'name: multiline_build_pkg\n'),
        d.file('build.yaml', '''
targets:
  \$default:
    builders:
      multiline_build_pkg|builder:
        builder_factories:
          - customBuilderOne
          - 'customBuilderTwo'
'''),
        d.dir('lib', [d.file('main.dart', 'void foo() {}')]),
      ]).create();

      final options = ZombieOptions(packagePath: d.path('multiline_build_pkg'));

      final harvester = RootHarvester(options);
      final topology = harvester.harvestTopology();

      check(topology.builderFactoryNames).contains('customBuilderOne');
      check(topology.builderFactoryNames).contains('customBuilderTwo');
    });
  });
}
