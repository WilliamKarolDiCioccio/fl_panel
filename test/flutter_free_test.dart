import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// `package:fl_panel/model.dart` is the headless half: the tree, the edits,
/// the solver, the resolver, the policy, the file format. Nothing under it may
/// import Flutter, so it can be used and tested without an engine. This is
/// the grep that keeps it so.
void main() {
  test('the model, layout and policy import nothing from Flutter', () {
    final offenders = <String>[];
    for (final dir in ['lib/src/model', 'lib/src/layout', 'lib/src/policy']) {
      for (final entity in Directory(dir).listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        for (final line in entity.readAsLinesSync()) {
          if (line.startsWith('import ') &&
              (line.contains('package:flutter') || line.contains('dart:ui'))) {
            offenders.add('${entity.path}: $line');
          }
        }
      }
    }
    expect(offenders, isEmpty);
  });

  test('the model barrel exports only from those directories', () {
    final lines = File('lib/model.dart').readAsLinesSync();
    for (final line in lines.where((l) => l.startsWith('export '))) {
      expect(
        line,
        anyOf(
          contains("'src/model/"),
          contains("'src/layout/"),
          contains("'src/policy/"),
        ),
        reason: 'a widget or controller export would drag Flutter in',
      );
    }
  });
}
