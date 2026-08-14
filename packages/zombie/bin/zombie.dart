import 'dart:io';
import 'package:zombie/src/cli.dart';

Future<void> main(List<String> args) async {
  final runner = ZombieCliRunner();
  final exitCode = await runner.run(args);
  exit(exitCode);
}
