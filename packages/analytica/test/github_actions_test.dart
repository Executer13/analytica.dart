import 'package:analytica/analytica.dart';
import 'package:checks/checks.dart';
import 'package:test/scaffolding.dart';
import 'package:test_descriptor/test_descriptor.dart' as d;

void main() {
  group('GitHub Actions Workflow Annotations', () {
    test('emitGitHubError formats message and attributes', () {
      final sink = StringBuffer();
      emitGitHubError(
        'Syntax error',
        file: 'lib/foo.dart',
        line: 10,
        endLine: 12,
        col: 5,
        endColumn: 15,
        title: 'Error Title',
        sink: sink,
      );

      check(sink.toString().trim()).equals(
        '::error file=lib/foo.dart,line=10,endLine=12,col=5,endColumn=15,title=Error Title::Syntax error',
      );
    });

    test('emitGitHubWarning formats warning annotation', () {
      final sink = StringBuffer();
      emitGitHubWarning(
        'Complexity increase',
        file: 'lib/bar.dart',
        line: 20,
        title: 'Warning Title',
        sink: sink,
      );

      check(sink.toString().trim()).equals(
        '::warning file=lib/bar.dart,line=20,title=Warning Title::Complexity increase',
      );
    });

    test('emitGitHubNotice formats notice annotation', () {
      final sink = StringBuffer();
      emitGitHubNotice(
        'Informational notice',
        file: 'lib/baz.dart',
        sink: sink,
      );

      check(
        sink.toString().trim(),
      ).equals('::notice file=lib/baz.dart::Informational notice');
    });
  });

  group('appendGitHubStepSummary', () {
    test('writes markdown to specified summary file', () async {
      await d.file('summary.md', '# Initial\n').create();
      final summaryFile = d.file('summary.md').io;

      appendGitHubStepSummary('## Section\n', summaryFile: summaryFile);

      final content = await summaryFile.readAsString();
      check(content).equals('# Initial\n## Section\n');
    });
  });
}
