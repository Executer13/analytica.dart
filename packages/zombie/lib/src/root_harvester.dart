import 'dart:io';
import 'package:path/path.dart' as p;

import 'models.dart';

/// Role and classification of a Dart source file within a package layout.
enum FileRole {
  /// Public API entrypoint/interface (`lib/**` excluding `lib/src/`).
  publicLib,

  /// Internal implementation source (`lib/src/**`).
  internalSrc,

  /// CLI binary entrypoint (`bin/**`).
  executable,

  /// Sample app or documentation demo (`example/**`).
  demonstration,

  /// Utility or auxiliary entrypoint (`tool/**`, `benchmark/**`, `web/**`).
  auxiliary,

  /// Test suite (`test/**`, `integration_test/**`, `test_driver/**`).
  test,

  /// Other files outside standard topologies.
  other;

  /// Whether declarations in this file are candidates for zombie detection.
  bool get isCandidateTarget => switch (this) {
    internalSrc || executable || auxiliary => true,
    _ => false,
  };
}

/// Discovered package topology and file listing.
class PackageTopology {
  final String packagePath;
  final String packageName;
  final List<String> publicLibFiles;
  final List<String> internalSrcFiles;
  final List<String> executableFiles;
  final List<String> demonstrationFiles;
  final List<String> auxiliaryFiles;
  final List<String> testFiles;
  final Set<String> builderFactoryNames;
  final Set<String> pluginClassNames;

  const PackageTopology({
    required this.packagePath,
    required this.packageName,
    required this.publicLibFiles,
    required this.internalSrcFiles,
    required this.executableFiles,
    required this.demonstrationFiles,
    required this.auxiliaryFiles,
    required this.testFiles,
    this.builderFactoryNames = const {},
    this.pluginClassNames = const {},
  });

  /// All scanned Dart files.
  List<String> get allFiles => [
    ...publicLibFiles,
    ...internalSrcFiles,
    ...executableFiles,
    ...demonstrationFiles,
    ...auxiliaryFiles,
    ...testFiles,
  ];

  /// Resolves the role of a given [relativeFilePath].
  FileRole roleOf(String relativeFilePath) {
    final normalized = p.normalize(relativeFilePath);
    if (normalized.startsWith('lib/src/') ||
        normalized.startsWith('lib/src\\')) {
      return FileRole.internalSrc;
    }
    if (normalized.startsWith('lib/') || normalized.startsWith('lib\\')) {
      return FileRole.publicLib;
    }
    if (normalized.startsWith('bin/') || normalized.startsWith('bin\\')) {
      return FileRole.executable;
    }
    if (normalized.startsWith('example/') ||
        normalized.startsWith('example\\')) {
      return FileRole.demonstration;
    }
    if (normalized.startsWith('test/') ||
        normalized.startsWith('test\\') ||
        normalized.startsWith('integration_test/') ||
        normalized.startsWith('integration_test\\') ||
        normalized.startsWith('test_driver/') ||
        normalized.startsWith('test_driver\\')) {
      return FileRole.test;
    }
    if (normalized.startsWith('tool/') ||
        normalized.startsWith('tool\\') ||
        normalized.startsWith('benchmark/') ||
        normalized.startsWith('benchmark\\') ||
        normalized.startsWith('web/') ||
        normalized.startsWith('web\\')) {
      return FileRole.auxiliary;
    }
    return FileRole.other;
  }
}

/// Harvester that discovers package topology, entrypoints, and roots.
class RootHarvester {
  final ZombieOptions options;

  const RootHarvester(this.options);

  /// Discovers the package topology from the filesystem.
  PackageTopology harvestTopology() {
    final rootDir = Directory(options.packagePath);
    if (!rootDir.existsSync()) {
      throw FileSystemException(
        'Target package directory does not exist',
        options.packagePath,
      );
    }

    final pubspecFile = File(p.join(options.packagePath, 'pubspec.yaml'));
    if (!pubspecFile.existsSync()) {
      throw FileSystemException(
        'Missing pubspec.yaml in package root',
        options.packagePath,
      );
    }

    final pubspecContent = pubspecFile.readAsStringSync();
    final packageName = _extractPackageName(pubspecContent);
    final pluginClassNames = _extractPluginClasses(pubspecContent);
    final builderFactoryNames = _extractBuilderFactories(options.packagePath);

    final publicLib = <String>[];
    final internalSrc = <String>[];
    final bin = <String>[];
    final example = <String>[];
    final auxiliary = <String>[];
    final test = <String>[];

    for (final entity in rootDir.listSync(
      recursive: true,
      followLinks: false,
    )) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;

      final relPath = p.relative(entity.path, from: options.packagePath);
      if (_isExcluded(relPath)) continue;

      final normalized = p.normalize(relPath);
      if (normalized.startsWith('lib/src/') ||
          normalized.startsWith('lib/src\\')) {
        internalSrc.add(normalized);
      } else if (normalized.startsWith('lib/') ||
          normalized.startsWith('lib\\')) {
        publicLib.add(normalized);
      } else if (normalized.startsWith('bin/') ||
          normalized.startsWith('bin\\')) {
        bin.add(normalized);
      } else if (normalized.startsWith('example/') ||
          normalized.startsWith('example\\')) {
        if (options.exampleMode != ExampleMode.skip) {
          example.add(normalized);
        }
      } else if (normalized.startsWith('test/') ||
          normalized.startsWith('test\\') ||
          normalized.startsWith('integration_test/') ||
          normalized.startsWith('integration_test\\') ||
          normalized.startsWith('test_driver/') ||
          normalized.startsWith('test_driver\\')) {
        test.add(normalized);
      } else if (normalized.startsWith('tool/') ||
          normalized.startsWith('tool\\') ||
          normalized.startsWith('benchmark/') ||
          normalized.startsWith('benchmark\\') ||
          normalized.startsWith('web/') ||
          normalized.startsWith('web\\')) {
        auxiliary.add(normalized);
      }
    }

    return PackageTopology(
      packagePath: options.packagePath,
      packageName: packageName,
      publicLibFiles: publicLib,
      internalSrcFiles: internalSrc,
      executableFiles: bin,
      demonstrationFiles: example,
      auxiliaryFiles: auxiliary,
      testFiles: test,
      builderFactoryNames: builderFactoryNames,
      pluginClassNames: pluginClassNames,
    );
  }

  bool _isExcluded(String relativePath) {
    final segments = p.split(p.normalize(relativePath));
    if (segments.contains('.dart_tool') ||
        segments.contains('.git') ||
        segments.contains('build')) {
      return true;
    }

    if (!options.includeGenerated) {
      final filename = p.basename(relativePath);
      if (filename.endsWith('.g.dart') ||
          filename.endsWith('.freezed.dart') ||
          filename.endsWith('.mocks.dart')) {
        return true;
      }
    }

    return false;
  }

  String _extractPackageName(String pubspecContent) {
    final match = RegExp(
      r'^name:\s*([a-zA-Z0-9_]+)',
      multiLine: true,
    ).firstMatch(pubspecContent);
    return match?.group(1) ?? 'unknown_package';
  }

  Set<String> _extractPluginClasses(String pubspecContent) {
    final results = <String>{};
    final matches = RegExp(
      r'(?:dartPluginClass|pluginClass):\s*["'
      "'"
      r']?([a-zA-Z0-9_]+)["'
      "'"
      r']?',
    ).allMatches(pubspecContent);
    for (final match in matches) {
      final cls = match.group(1);
      if (cls != null) results.add(cls);
    }
    return results;
  }

  Set<String> _extractBuilderFactories(String packagePath) {
    final buildYaml = File(p.join(packagePath, 'build.yaml'));
    if (!buildYaml.existsSync()) return const {};

    try {
      final content = buildYaml.readAsStringSync();
      final results = <String>{};

      // Match inline syntax: builder_factories: ["foo", "bar"]
      final inlineMatches = RegExp(
        r'builder_factories:\s*\[([^\]]+)\]',
      ).allMatches(content);
      for (final match in inlineMatches) {
        final rawList = match.group(1);
        if (rawList != null) {
          for (final item in rawList.split(',')) {
            final cleaned = item.replaceAll(RegExp(r'''['"\s]'''), '');
            if (cleaned.isNotEmpty) results.add(cleaned);
          }
        }
      }

      // Match multi-line list syntax:
      // builder_factories:
      //   - foo
      //   - bar
      final multiLineBlocks = RegExp(
        r'builder_factories:\s*\n((?:\s*-\s*["'
        "'"
        r']?[a-zA-Z0-9_]+["'
        "'"
        r']?\s*\n?)+)',
      ).allMatches(content);
      for (final block in multiLineBlocks) {
        final blockContent = block.group(1);
        if (blockContent != null) {
          final itemMatches = RegExp(
            r'-\s*["'
            "'"
            r']?([a-zA-Z0-9_]+)["'
            "'"
            r']?',
          ).allMatches(blockContent);
          for (final item in itemMatches) {
            final name = item.group(1);
            if (name != null && name.isNotEmpty) results.add(name);
          }
        }
      }

      return results;
    } catch (_) {
      return const {};
    }
  }
}
