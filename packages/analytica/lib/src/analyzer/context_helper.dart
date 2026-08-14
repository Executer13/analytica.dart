import 'dart:io';

import 'package:analyzer/dart/analysis/analysis_context.dart';
import 'package:analyzer/dart/analysis/analysis_context_collection.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:path/path.dart' as p;

import '../exceptions.dart';
import '../sdk_discovery.dart';

/// Helper for initializing analyzer [AnalysisContextCollection] instances
/// and safely resolving compilation units.
class AnalysisContextHelper {
  final AnalysisContextCollection collection;
  final String sdkPath;
  final List<String> includedPaths;

  AnalysisContextHelper._({
    required this.collection,
    required this.sdkPath,
    required this.includedPaths,
  });

  /// Creates an [AnalysisContextHelper] for the specified [includedPaths].
  ///
  /// If [sdkPath] is omitted, it will be discovered automatically via
  /// [findSdkPath]. Throws [SdkDiscoveryException] if no valid SDK is found.
  factory AnalysisContextHelper({
    required List<String> includedPaths,
    String? sdkPath,
  }) {
    if (includedPaths.isEmpty) {
      throw ArgumentError.value(
        includedPaths,
        'includedPaths',
        'Must contain at least one path.',
      );
    }

    final effectiveSdkPath = sdkPath ?? findSdkPath();
    if (effectiveSdkPath == null) {
      throw const SdkDiscoveryException(
        'Cannot locate a Dart SDK for analysis. Pass --sdk-path, set the '
        'DART_SDK environment variable, or ensure a Dart SDK is on PATH.',
      );
    }

    if (!isValidSdk(effectiveSdkPath)) {
      throw SdkDiscoveryException(
        'The provided SDK path "$effectiveSdkPath" does not point to a valid '
        'Dart SDK root (missing lib/_internal).',
      );
    }

    final normalizedIncluded = includedPaths
        .map((path) => p.normalize(p.absolute(path)))
        .toList();

    final collection = AnalysisContextCollection(
      includedPaths: normalizedIncluded,
      sdkPath: effectiveSdkPath,
    );

    return AnalysisContextHelper._(
      collection: collection,
      sdkPath: effectiveSdkPath,
      includedPaths: normalizedIncluded,
    );
  }

  /// Returns the [AnalysisContext] for the given [filePath].
  AnalysisContext contextFor(String filePath) {
    final absPath = p.normalize(p.absolute(filePath));
    return collection.contextFor(absPath);
  }

  /// Safely resolves the unit at [filePath].
  ///
  /// Returns `null` if the result is not a [ResolvedUnitResult], the file
  /// does not exist, or the file is not part of an active analysis context.
  Future<ResolvedUnitResult?> getResolvedUnit(String filePath) async {
    try {
      final absPath = p.normalize(p.absolute(filePath));
      final context = collection.contextFor(absPath);
      final unitResult = await context.currentSession.getResolvedUnit(absPath);
      if (unitResult is ResolvedUnitResult && unitResult.exists) {
        return unitResult;
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Resolves the unit at [filePath], throwing a [StateError] if resolution
  /// fails or the file does not exist.
  Future<ResolvedUnitResult> getRequiredResolvedUnit(String filePath) async {
    final absPath = p.normalize(p.absolute(filePath));
    final unitResult = await getResolvedUnit(absPath);
    if (unitResult == null) {
      throw StateError('Failed to resolve Dart unit for "$filePath"');
    }
    return unitResult;
  }

  /// Convenience method to resolve a single file in a temporary context.
  static Future<ResolvedUnitResult> resolveFile(
    String filePath, {
    String? sdkPath,
  }) async {
    final absPath = p.normalize(p.absolute(filePath));
    final file = File(absPath);
    if (!file.existsSync()) {
      throw FileSystemException('Target file does not exist', filePath);
    }
    final helper = AnalysisContextHelper(
      includedPaths: [absPath],
      sdkPath: sdkPath,
    );
    return helper.getRequiredResolvedUnit(absPath);
  }
}
