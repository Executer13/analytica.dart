import 'package:io/io.dart';

/// Base exception for all Analytica tooling errors with exit code support.
abstract class AnalyticaException implements Exception {
  String get message;
  int get exitCode;

  const AnalyticaException();

  @override
  String toString() => message;
}

/// Thrown when CLI argument parsing or user input validation fails.
class UsageException extends AnalyticaException {
  @override
  final String message;

  @override
  int get exitCode => ExitCode.usage.code;

  const UsageException(this.message);
}

/// Thrown when a required input file or directory is missing.
class MissingInputException extends AnalyticaException {
  @override
  final String message;
  final String? path;

  @override
  int get exitCode => ExitCode.noInput.code;

  const MissingInputException(this.message, {this.path});

  @override
  String toString() => path != null ? '$message ($path)' : message;
}

/// Thrown when package configuration or dependencies are unresolved.
class PackageResolutionException extends AnalyticaException {
  @override
  final String message;
  final String? packagePath;

  @override
  int get exitCode => ExitCode.config.code;

  const PackageResolutionException(this.message, [this.packagePath]);

  @override
  String toString() => packagePath != null
      ? 'PackageResolutionException: $message ($packagePath)'
      : 'PackageResolutionException: $message';
}

/// Thrown when a usable Dart SDK cannot be located or a provided SDK path
/// is not a valid SDK root.
class SdkDiscoveryException extends AnalyticaException {
  @override
  final String message;

  @override
  int get exitCode => ExitCode.unavailable.code;

  const SdkDiscoveryException(this.message);

  @override
  String toString() => message;
}

/// General CLI exception with an explicit exit code.
class CliException extends AnalyticaException {
  @override
  final String message;

  @override
  final int exitCode;

  const CliException(this.message, {this.exitCode = 1});
}
