import '../models.dart';

/// Formats a [ZombieReport] into human-readable GitHub-flavored Markdown
/// tables.
class MarkdownFormatter {
  const MarkdownFormatter();

  String format(ZombieReport report) {
    final buffer = StringBuffer();
    buffer.writeln('# Zombie Code Analysis: `${report.package}`');
    buffer.writeln();

    // Summary Section
    buffer.writeln('### Summary');
    buffer.writeln();
    buffer.writeln('| Metric | Count |');
    buffer.writeln('| :--- | :--- |');
    buffer.writeln(
      '| **Total Declarations Scanned** | ${report.totalDeclarations} |',
    );
    buffer.writeln('| **Pure Zombies** | ${report.pureZombiesFound} |');
    buffer.writeln('| **Tested Zombies** | ${report.testedZombiesFound} |');
    buffer.writeln(
      '| **Co-Invoked Hazards** | ${report.coInvokedHazardsFound} |',
    );
    buffer.writeln();

    if (report.zombies.isEmpty) {
      buffer.writeln('🎉 **No zombie declarations detected across package.**');
      return buffer.toString();
    }

    final pureZombies = report.zombies
        .where((z) => z.classification == ZombieClassification.pureZombie)
        .toList();
    final testedZombies = report.zombies
        .where((z) => z.classification == ZombieClassification.testedZombie)
        .toList();
    final coInvokedHazards = report.zombies
        .where((z) => z.classification == ZombieClassification.coInvokedHazard)
        .toList();

    if (pureZombies.isNotEmpty) {
      buffer.writeln('## Pure Zombies (Safe to Delete)');
      buffer.writeln();
      buffer.writeln('| Symbol | Kind | Location | Suggested Action |');
      buffer.writeln('| :--- | :--- | :--- | :--- |');
      for (final z in pureZombies) {
        final loc = '${z.file}:${z.line}:${z.column}';
        buffer.writeln(
          '| `${z.name}` | ${z.kind.jsonValue} | `$loc` | Delete declaration |',
        );
      }
      buffer.writeln();
    }

    if (testedZombies.isNotEmpty) {
      buffer.writeln('## Tested Zombies (Orphan Tests)');
      buffer.writeln();
      buffer.writeln(
        '| Symbol | Kind | Location | Orphan Test Sites | Suggested Action |',
      );
      buffer.writeln('| :--- | :--- | :--- | :--- | :--- |');
      for (final z in testedZombies) {
        final loc = '${z.file}:${z.line}:${z.column}';
        final testSites = (z.orphanTests ?? [])
            .map((t) {
              final desc = t.description != null ? ' ("${t.description}")' : '';
              return '`${t.file}:${t.line}`$desc';
            })
            .join('<br>');
        buffer.writeln(
          '| `${z.name}` | ${z.kind.jsonValue} | `$loc` | $testSites | '
          'Delete declaration + orphan test block |',
        );
      }
      buffer.writeln();
    }

    if (coInvokedHazards.isNotEmpty) {
      buffer.writeln(
        '## Co-Invoked Test Hazards (Manual Refactoring Required)',
      );
      buffer.writeln();
      buffer.writeln(
        '| Symbol | Kind | Location | Co-Invoked Test Sites | '
        'Suggested Action |',
      );
      buffer.writeln('| :--- | :--- | :--- | :--- | :--- |');
      for (final z in coInvokedHazards) {
        final loc = '${z.file}:${z.line}:${z.column}';
        final testSites = (z.orphanTests ?? [])
            .map((t) {
              final desc = t.description != null ? ' ("${t.description}")' : '';
              return '`${t.file}:${t.line}`$desc';
            })
            .join('<br>');
        buffer.writeln(
          '| `${z.name}` | ${z.kind.jsonValue} | `$loc` | $testSites | '
          'Manual refactoring required |',
        );
      }
      buffer.writeln();
    }

    return buffer.toString();
  }
}
