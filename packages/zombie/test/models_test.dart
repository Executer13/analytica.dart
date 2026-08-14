import 'package:checks/checks.dart';
import 'package:test/test.dart';
import 'package:zombie/zombie.dart';

void main() {
  group('Models Serialization & Deserialization', () {
    test('OrphanTestSite serialization round-trip', () {
      const site = OrphanTestSite(
        file: 'test/old_parser_test.dart',
        line: 12,
        column: 5,
        description: 'OldParser parses correctly',
        coInvokedHazard: false,
      );

      final json = site.toJson();
      check(json['file']).equals('test/old_parser_test.dart');
      check(json['line']).equals(12);
      check(json['column']).equals(5);
      check(json['description']).equals('OldParser parses correctly');
      check(json['co_invoked_hazard']).equals(false);

      final deserialized = OrphanTestSite.fromJson(json);
      check(deserialized.file).equals(site.file);
      check(deserialized.line).equals(site.line);
      check(deserialized.column).equals(site.column);
      check(deserialized.description).equals(site.description);
      check(deserialized.coInvokedHazard).isFalse();
    });

    test('ZombieFinding serialization round-trip', () {
      const finding = ZombieFinding(
        id: 'calculateLegacyHash',
        name: 'calculateLegacyHash',
        kind: DeclarationKind.function,
        file: 'lib/src/utils.dart',
        line: 45,
        column: 1,
        length: 19,
        classification: ZombieClassification.pureZombie,
        suggestedAction: SuggestedAction.delete,
      );

      final json = finding.toJson();
      check(json['id']).equals('calculateLegacyHash');
      check(json['name']).equals('calculateLegacyHash');
      check(json['kind']).equals('function');
      check(json['file']).equals('lib/src/utils.dart');
      check(json['line']).equals(45);
      check(json['column']).equals(1);
      check(json['length']).equals(19);
      check(json['classification']).equals('pure_zombie');
      check(json['suggested_action']).equals('delete');
      check(json.containsKey('orphan_tests')).isFalse();

      final deserialized = ZombieFinding.fromJson(json);
      check(deserialized.id).equals(finding.id);
      check(deserialized.name).equals(finding.name);
      check(deserialized.kind).equals(DeclarationKind.function);
      check(
        deserialized.classification,
      ).equals(ZombieClassification.pureZombie);
      check(deserialized.suggestedAction).equals(SuggestedAction.delete);
    });

    test('ZombieReport serialization matches PRD JSON schema', () {
      const report = ZombieReport(
        version: '0.1.0',
        package: 'my_package',
        totalDeclarations: 142,
        pureZombiesFound: 1,
        testedZombiesFound: 1,
        coInvokedHazardsFound: 0,
        zombies: [
          ZombieFinding(
            id: 'calculateLegacyHash',
            name: 'calculateLegacyHash',
            kind: DeclarationKind.function,
            file: 'lib/src/utils.dart',
            line: 45,
            column: 1,
            length: 19,
            classification: ZombieClassification.pureZombie,
            suggestedAction: SuggestedAction.delete,
          ),
          ZombieFinding(
            id: 'OldParser',
            name: 'OldParser',
            kind: DeclarationKind.classType,
            file: 'lib/src/old_parser.dart',
            line: 10,
            column: 7,
            length: 9,
            classification: ZombieClassification.testedZombie,
            suggestedAction: SuggestedAction.deleteWithOrphanTests,
            orphanTests: [
              OrphanTestSite(
                file: 'test/old_parser_test.dart',
                line: 3,
                column: 3,
                description: 'OldParser parses correctly',
                coInvokedHazard: false,
              ),
            ],
          ),
        ],
      );

      final json = report.toJson();
      check(json['version']).equals('0.1.0');
      check(json['package']).equals('my_package');

      final summary = json['summary'] as Map<String, dynamic>;
      check(summary['total_declarations']).equals(142);
      check(summary['pure_zombies_found']).equals(1);
      check(summary['tested_zombies_found']).equals(1);
      check(summary['co_invoked_hazards_found']).equals(0);

      final zombiesList = json['zombies'] as List<dynamic>;
      check(zombiesList.length).equals(2);

      final deserialized = ZombieReport.fromJson(json);
      check(deserialized.package).equals('my_package');
      check(deserialized.totalDeclarations).equals(142);
      check(deserialized.zombies.length).equals(2);
      check(deserialized.zombies[1].orphanTests?.length).equals(1);
    });

    test('Enum fromJson and fromString conversions', () {
      check(
        ZombieClassification.fromJson('pure_zombie'),
      ).equals(ZombieClassification.pureZombie);
      check(
        ZombieClassification.fromJson('tested_zombie'),
      ).equals(ZombieClassification.testedZombie);
      check(
        ZombieClassification.fromJson('co_invoked_hazard'),
      ).equals(ZombieClassification.coInvokedHazard);

      check(
        DeclarationKind.fromJson('class'),
      ).equals(DeclarationKind.classType);
      check(DeclarationKind.fromJson('getter')).equals(DeclarationKind.getter);
      check(DeclarationKind.fromJson('setter')).equals(DeclarationKind.setter);

      check(
        ExampleMode.fromString('demonstration'),
      ).equals(ExampleMode.demonstration);
      check(ExampleMode.fromString('strict')).equals(ExampleMode.strict);
      check(ExampleMode.fromString('skip')).equals(ExampleMode.skip);

      check(AnalysisMode.fromString('library')).equals(AnalysisMode.library);
      check(
        AnalysisMode.fromString('closed-app'),
      ).equals(AnalysisMode.closedApp);

      check(OutputFormat.fromString('markdown')).equals(OutputFormat.markdown);
      check(OutputFormat.fromString('json')).equals(OutputFormat.json);
    });
  });
}
