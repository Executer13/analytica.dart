import 'dart:io';
import 'package:zombie/src/cli.dart';

Future<void> main(List<String> args) async {
  final runner = ZombieCliRunner();
  final code = await runner.run(args);
  if (code != 0) {
    exitCode = code;
  }
}
