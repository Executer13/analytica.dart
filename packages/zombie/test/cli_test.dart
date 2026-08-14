import 'dart:convert';
import 'dart:io';
import 'package:checks/checks.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:test_descriptor/test_descriptor.dart' as d;
import 'package:test_process/test_process.dart';

void main() {
  final binPath = File('bin/zombie.dart').existsSync()
      ? p.normalize(p.absolute('bin/zombie.dart'))
      : p.normalize(p.absolute('packages/zombie/bin/zombie.dart'));

  Future<TestProcess> runZombie(List<String> args, {String? workingDirectory}) {
    return TestProcess.start(Platform.resolvedExecutable, [
      binPath,
      ...args,
    ], workingDirectory: workingDirectory);
  }

  group('Zombie CLI End-to-End', () {
    test('--help displays usage and exits 0', () async {
      final proc = await runZombie(['--help']);
      final stdout = await proc.stdoutStream().join('\n');
      await proc.shouldExit(0);

      check(stdout).contains('Usage: zombie [options] [target_path]');
      check(stdout).contains('--format');
      check(stdout).contains('--example-mode');
      check(stdout).contains('--mode');
      check(stdout).contains('fail-on-zombies');
    });

    test('--version displays version and exits 0', () async {
      final proc = await runZombie(['--version']);
      final stdout = await proc.stdoutStream().join('\n');
      await proc.shouldExit(0);

      check(stdout).contains('zombie version: 0.1.0-dev');
    });

    test('invalid argument exits with code 64 (usage)', () async {
      final proc = await runZombie(['--nonexistent-flag']);
      await proc.shouldExit(64);
    });

    test('nonexistent target directory exits with code 66 (noInput)', () async {
      final proc = await runZombie(['does/not/exist']);
      await proc.shouldExit(66);
    });

    test('runs analysis and outputs JSON with --format=json', () async {
      await d.dir('cli_pkg', [
        d.file('pubspec.yaml', '''
name: cli_pkg
environment:
  sdk: '^3.5.0'
'''),
        d.dir('lib', [
          d.file('cli_pkg.dart', 'export "src/live.dart";'),
          d.dir('src', [
            d.file('live.dart', 'void live() {}'),
            d.file('dead.dart', 'void dead() {}'),
          ]),
        ]),
      ]).create();

      final proc = await runZombie(['--format=json', d.path('cli_pkg')]);

      final stdout = await proc.stdoutStream().join('\n');
      await proc.shouldExit(0);

      final decoded = jsonDecode(stdout) as Map<String, dynamic>;
      check(decoded['package']).equals('cli_pkg');
      final summary = decoded['summary'] as Map<String, dynamic>;
      check(summary['pure_zombies_found']).equals(1);

      final zombies = decoded['zombies'] as List<dynamic>;
      check(zombies.length).equals(1);
      final firstZombie = zombies.first as Map<String, dynamic>;
      check(firstZombie['name']).equals('dead');
    });

    test('runs analysis and outputs Markdown with --format=markdown', () async {
      await d.dir('cli_md_pkg', [
        d.file('pubspec.yaml', '''
name: cli_md_pkg
environment:
  sdk: '^3.5.0'
'''),
        d.dir('lib', [
          d.file('cli_md_pkg.dart', 'export "src/live.dart";'),
          d.dir('src', [
            d.file('live.dart', 'void live() {}'),
            d.file('dead.dart', 'void dead() {}'),
          ]),
        ]),
      ]).create();

      final proc = await runZombie(['--format=markdown', d.path('cli_md_pkg')]);

      final stdout = await proc.stdoutStream().join('\n');
      await proc.shouldExit(0);

      check(stdout).contains('# Zombie Code Analysis: `cli_md_pkg`');
      check(stdout).contains('## Pure Zombies (Safe to Delete)');
      check(stdout).contains('`dead`');
    });

    test('runs analysis and outputs Markdown with --format=github', () async {
      await d.dir('cli_github_pkg', [
        d.file('pubspec.yaml', '''
name: cli_github_pkg
environment:
  sdk: '^3.5.0'
'''),
        d.dir('lib', [
          d.file('cli_github_pkg.dart', 'export "src/live.dart";'),
          d.dir('src', [
            d.file('live.dart', 'void live() {}'),
            d.file('dead.dart', 'void dead() {}'),
          ]),
        ]),
      ]).create();

      final proc = await runZombie([
        '--format=github',
        d.path('cli_github_pkg'),
      ]);

      final stdout = await proc.stdoutStream().join('\n');
      await proc.shouldExit(0);

      check(stdout).contains('# Zombie Code Analysis: `cli_github_pkg`');
      check(stdout).contains('## Pure Zombies (Safe to Delete)');
    });

    test(
      '--fail-on-zombies exits with code 1 when zombies are found',
      () async {
        await d.dir('cli_fail_pkg', [
          d.file('pubspec.yaml', '''
name: cli_fail_pkg
environment:
  sdk: '^3.5.0'
'''),
          d.dir('lib', [
            d.file('cli_fail_pkg.dart', 'export "src/live.dart";'),
            d.dir('src', [
              d.file('live.dart', 'void live() {}'),
              d.file('dead.dart', 'void dead() {}'),
            ]),
          ]),
        ]).create();

        final proc = await runZombie([
          '--fail-on-zombies',
          d.path('cli_fail_pkg'),
        ]);

        await proc.shouldExit(1);
      },
    );

    test(
      '--fail-on-zombies exits with code 0 when no zombies are found',
      () async {
        await d.dir('cli_clean_pkg', [
          d.file('pubspec.yaml', '''
name: cli_clean_pkg
environment:
  sdk: '^3.5.0'
'''),
          d.dir('lib', [
            d.file('cli_clean_pkg.dart', 'export "src/live.dart";'),
            d.dir('src', [d.file('live.dart', 'void live() {}')]),
          ]),
        ]).create();

        final proc = await runZombie([
          '--fail-on-zombies',
          d.path('cli_clean_pkg'),
        ]);

        await proc.shouldExit(0);
      },
    );
  });
}
