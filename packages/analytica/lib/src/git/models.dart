import 'package:analyzer/dart/ast/ast.dart';

/// Represents a 1-based inclusive range of lines `[startLine, endLine]`.
class LineRange implements Comparable<LineRange> {
  final int startLine;
  final int endLine;

  const LineRange(this.startLine, this.endLine)
    : assert(startLine >= 1, 'startLine must be >= 1'),
      assert(endLine >= startLine, 'endLine must be >= startLine');

  /// The number of lines in this range.
  int get lineCount => endLine - startLine + 1;

  /// Returns `true` if [lineNumber] is within this range.
  bool contains(int lineNumber) =>
      lineNumber >= startLine && lineNumber <= endLine;

  /// Returns `true` if this range intersects `[start, end]`.
  bool intersects(int start, int end) => start <= endLine && end >= startLine;

  /// Returns `true` if this range intersects [other].
  bool intersectsRange(LineRange other) =>
      intersects(other.startLine, other.endLine);

  @override
  int compareTo(LineRange other) {
    final startComp = startLine.compareTo(other.startLine);
    if (startComp != 0) return startComp;
    return endLine.compareTo(other.endLine);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LineRange &&
          runtimeType == other.runtimeType &&
          startLine == other.startLine &&
          endLine == other.endLine;

  @override
  int get hashCode => Object.hash(startLine, endLine);

  @override
  String toString() => 'L$startLine-L$endLine';

  factory LineRange.fromJson(Map<String, dynamic> json) =>
      LineRange(json['start_line'] as int, json['end_line'] as int);

  Map<String, dynamic> toJson() => {
    'start_line': startLine,
    'end_line': endLine,
  };
}

/// A parsed hunk within a unified diff.
class DiffHunk {
  final int oldStart;
  final int oldCount;
  final int newStart;
  final int newCount;
  final String? sectionHeading;
  final List<String> lines;
  final List<LineRange> addedOrModifiedRanges;

  const DiffHunk({
    required this.oldStart,
    required this.oldCount,
    required this.newStart,
    required this.newCount,
    this.sectionHeading,
    required this.lines,
    required this.addedOrModifiedRanges,
  });

  @override
  String toString() =>
      '@@ -$oldStart,$oldCount +$newStart,$newCount @@'
      '${sectionHeading != null ? " $sectionHeading" : ""} '
      '(${addedOrModifiedRanges.length} changed ranges)';
}

/// Represents the diff for a single file within a unified diff.
class GitFileDiff {
  final String? oldPath;
  final String? newPath;
  final List<DiffHunk> hunks;
  final bool isNew;
  final bool isDeleted;
  final bool isRenamed;

  const GitFileDiff({
    this.oldPath,
    this.newPath,
    required this.hunks,
    this.isNew = false,
    this.isDeleted = false,
    this.isRenamed = false,
  });

  /// The effective relative file path for the file.
  String get path => newPath ?? oldPath ?? '';

  /// All added or modified line ranges across all hunks for this file.
  List<LineRange> get addedOrModifiedLineRanges {
    final allRanges = <LineRange>[];
    for (final hunk in hunks) {
      allRanges.addAll(hunk.addedOrModifiedRanges);
    }
    return _mergeLineRanges(allRanges);
  }

  static List<LineRange> _mergeLineRanges(List<LineRange> ranges) {
    if (ranges.isEmpty) return const [];
    final sorted = List<LineRange>.from(ranges)..sort();
    final merged = <LineRange>[];

    var currentStart = sorted.first.startLine;
    var currentEnd = sorted.first.endLine;

    for (var i = 1; i < sorted.length; i++) {
      final r = sorted[i];
      if (r.startLine <= currentEnd + 1) {
        if (r.endLine > currentEnd) {
          currentEnd = r.endLine;
        }
      } else {
        merged.add(LineRange(currentStart, currentEnd));
        currentStart = r.startLine;
        currentEnd = r.endLine;
      }
    }
    merged.add(LineRange(currentStart, currentEnd));
    return merged;
  }

  @override
  String toString() =>
      'GitFileDiff($path, hunks: ${hunks.length}, '
      'ranges: ${addedOrModifiedLineRanges.length})';
}

/// Represents an AST declaration mapped to diff line ranges.
class MappedDeclaration {
  final AstNode node;
  final String name;
  final int startLine;
  final int endLine;
  final List<LineRange> intersectingRanges;

  const MappedDeclaration({
    required this.node,
    required this.name,
    required this.startLine,
    required this.endLine,
    required this.intersectingRanges,
  });

  @override
  String toString() =>
      '$name (L$startLine-L$endLine, matched: $intersectingRanges)';

  Map<String, dynamic> toJson() => {
    'name': name,
    'start_line': startLine,
    'end_line': endLine,
    'intersecting_ranges': intersectingRanges.map((r) => r.toJson()).toList(),
  };
}
