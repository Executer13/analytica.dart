import 'models.dart';

/// Parser for unified diff strings produced by `git diff` or `diff -u`.
class GitDiffParser {
  static final RegExp _hunkHeaderPattern = RegExp(
    r'^@@\s+-(\d+)(?:,(\d+))?\s+\+(\d+)(?:,(\d+))?\s+@@(?:[ \t]+(.*))?$',
  );

  static final RegExp _diffGitQuotedPattern = RegExp(
    r'^diff --git\s+"a/(.+?)"\s+"b/(.+?)"$',
  );
  static final RegExp _diffGitUnquotedPattern = RegExp(
    r'^diff --git\s+a/(.+?)\s+b/(.+?)$',
  );

  static final RegExp _minusFilePattern = RegExp(r'^---\s+(.+)$');
  static final RegExp _plusFilePattern = RegExp(r'^\+\+\+\s+(.+)$');

  static String _cleanPath(String raw) {
    var cleaned = raw.trim();
    if (cleaned.startsWith('"') && cleaned.endsWith('"')) {
      cleaned = cleaned.substring(1, cleaned.length - 1);
    }
    final tabIdx = cleaned.indexOf('\t');
    if (tabIdx != -1) {
      cleaned = cleaned.substring(0, tabIdx).trim();
    }
    if (cleaned.startsWith('a/') || cleaned.startsWith('b/')) {
      cleaned = cleaned.substring(2);
    }
    return cleaned;
  }

  /// Parses a unified diff string into a list of [GitFileDiff] objects.
  static List<GitFileDiff> parse(String unifiedDiff) {
    if (unifiedDiff.trim().isEmpty) return const [];

    final rawLines = unifiedDiff.split('\n');
    final fileDiffs = <GitFileDiff>[];

    String? currentOldPath;
    String? currentNewPath;
    var isNew = false;
    var isDeleted = false;
    var isRenamed = false;
    final currentHunks = <DiffHunk>[];

    void flushFile() {
      if (currentOldPath != null ||
          currentNewPath != null ||
          currentHunks.isNotEmpty) {
        fileDiffs.add(
          GitFileDiff(
            oldPath: currentOldPath == '/dev/null' ? null : currentOldPath,
            newPath: currentNewPath == '/dev/null' ? null : currentNewPath,
            hunks: List.unmodifiable(currentHunks),
            isNew: isNew,
            isDeleted: isDeleted,
            isRenamed: isRenamed,
          ),
        );
        currentOldPath = null;
        currentNewPath = null;
        isNew = false;
        isDeleted = false;
        isRenamed = false;
        currentHunks.clear();
      }
    }

    var i = 0;
    while (i < rawLines.length) {
      final line = rawLines[i];

      final quotedMatch = _diffGitQuotedPattern.firstMatch(line);
      final unquotedMatch = quotedMatch == null
          ? _diffGitUnquotedPattern.firstMatch(line)
          : null;
      final diffMatch = quotedMatch ?? unquotedMatch;
      if (diffMatch != null) {
        flushFile();
        currentOldPath = _cleanPath(diffMatch.group(1)!);
        currentNewPath = _cleanPath(diffMatch.group(2)!);
        i++;
        continue;
      }

      if (line.startsWith('new file mode')) {
        isNew = true;
        i++;
        continue;
      }
      if (line.startsWith('deleted file mode')) {
        isDeleted = true;
        i++;
        continue;
      }
      if (line.startsWith('rename from ') || line.startsWith('rename to ')) {
        isRenamed = true;
        i++;
        continue;
      }

      final minusMatch = _minusFilePattern.firstMatch(line);
      if (minusMatch != null &&
          i + 1 < rawLines.length &&
          rawLines[i + 1].startsWith('+++')) {
        final rawOld = _cleanPath(minusMatch.group(1)!);
        if (currentOldPath == null || rawOld == '/dev/null') {
          currentOldPath = rawOld;
        }
        final plusMatch = _plusFilePattern.firstMatch(rawLines[i + 1]);
        if (plusMatch != null) {
          final rawNew = _cleanPath(plusMatch.group(1)!);
          if (currentNewPath == null || rawNew == '/dev/null') {
            currentNewPath = rawNew;
          }
        }
        i += 2;
        continue;
      }

      final hunkMatch = _hunkHeaderPattern.firstMatch(line);
      if (hunkMatch != null) {
        final oldStart = int.parse(hunkMatch.group(1)!);
        final oldCount = hunkMatch.group(2) != null
            ? int.parse(hunkMatch.group(2)!)
            : 1;
        final newStart = int.parse(hunkMatch.group(3)!);
        final newCount = hunkMatch.group(4) != null
            ? int.parse(hunkMatch.group(4)!)
            : 1;
        final sectionHeading = hunkMatch.group(5)?.trim();

        final hunkLines = <String>[];
        final addedRanges = <LineRange>[];

        var currentNew = newStart < 1 ? 1 : newStart;
        int? rangeStart;
        int? rangeEnd;

        void flushRange() {
          if (rangeStart != null && rangeEnd != null) {
            addedRanges.add(
              LineRange(
                rangeStart! < 1 ? 1 : rangeStart!,
                rangeEnd! < 1 ? 1 : rangeEnd!,
              ),
            );
            rangeStart = null;
            rangeEnd = null;
          }
        }

        i++; // Move past hunk header

        while (i < rawLines.length) {
          final hunkLine = rawLines[i];
          if (hunkLine.startsWith('diff --git') ||
              _hunkHeaderPattern.hasMatch(hunkLine)) {
            break;
          }

          hunkLines.add(hunkLine);

          if (hunkLine.startsWith('+')) {
            rangeStart ??= (currentNew < 1 ? 1 : currentNew);
            rangeEnd = currentNew < 1 ? 1 : currentNew;
            currentNew++;
          } else if (hunkLine.startsWith('-')) {
            // Deletion: does not advance new line counter
          } else if (hunkLine.startsWith(' ') || hunkLine.isEmpty) {
            flushRange();
            currentNew++;
          } else if (hunkLine.startsWith(r'\')) {
            // e.g. \ No newline at end of file
          } else {
            // Unrecognized line format at end of hunk
            break;
          }
          i++;
        }

        flushRange();

        currentHunks.add(
          DiffHunk(
            oldStart: oldStart,
            oldCount: oldCount,
            newStart: newStart,
            newCount: newCount,
            sectionHeading: sectionHeading != null && sectionHeading.isNotEmpty
                ? sectionHeading
                : null,
            lines: List.unmodifiable(hunkLines),
            addedOrModifiedRanges: List.unmodifiable(addedRanges),
          ),
        );
        continue;
      }

      i++;
    }

    flushFile();
    return List.unmodifiable(fileDiffs);
  }
}
