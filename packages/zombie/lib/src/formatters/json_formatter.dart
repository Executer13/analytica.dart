import 'dart:convert';
import '../models.dart';

/// Formats a [ZombieReport] into pretty-printed JSON adhering to the PRD
/// schema.
class JsonFormatter {
  const JsonFormatter();

  String format(ZombieReport report) {
    const encoder = JsonEncoder.withIndent('  ');
    return encoder.convert(report.toJson());
  }
}
