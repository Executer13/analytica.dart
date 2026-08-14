import 'package:analytica/analytica.dart';
import 'package:checks/checks.dart';
import 'package:test/scaffolding.dart';

void main() {
  group('Analytica Exceptions & Exit Codes', () {
    test('UsageException has exitCode 64 and message', () {
      const e = UsageException('Invalid option: --foo');
      check(e.exitCode).equals(ExitCode.usage.code);
      check(e.message).equals('Invalid option: --foo');
      check(e.toString()).equals('Invalid option: --foo');
    });

    test('MissingInputException has exitCode 66 and formats path', () {
      const e1 = MissingInputException('Target file not found');
      check(e1.exitCode).equals(ExitCode.noInput.code);
      check(e1.toString()).equals('Target file not found');

      const e2 = MissingInputException('Directory missing', path: 'foo/bar');
      check(e2.exitCode).equals(ExitCode.noInput.code);
      check(e2.toString()).equals('Directory missing (foo/bar)');
    });

    test(
      'PackageResolutionException has exitCode 78 and formats packagePath',
      () {
        const e1 = PackageResolutionException('Unresolved dependencies');

        check(e1.exitCode).equals(ExitCode.config.code);
        check(
          e1.toString(),
        ).equals('PackageResolutionException: Unresolved dependencies');

        const e2 = PackageResolutionException(
          'Missing package_config.json',
          '/path/to/pkg',
        );
        check(e2.exitCode).equals(ExitCode.config.code);
        check(e2.toString()).equals(
          'PackageResolutionException: Missing package_config.json (/path/to/pkg)',
        );
      },
    );

    test('SdkDiscoveryException has exitCode 69 and message', () {
      const e = SdkDiscoveryException('Cannot locate SDK');
      check(e.exitCode).equals(ExitCode.unavailable.code);
      check(e.message).equals('Cannot locate SDK');
      check(e.toString()).equals('Cannot locate SDK');
    });

    test('CliException supports custom exit codes', () {
      const e1 = CliException('General error');
      check(e1.exitCode).equals(1);
      check(e1.message).equals('General error');

      const e2 = CliException('Custom code error', exitCode: 42);
      check(e2.exitCode).equals(42);
    });
  });
}
