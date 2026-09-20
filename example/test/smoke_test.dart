import 'package:fl_panel/fl_panel.dart';
import 'package:fl_panel_example/demo_layout.dart';
import 'package:fl_panel_example/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const DemoApp());
  }

  Finder chip(String title) =>
      find.descendant(of: find.byType(TabChip), matching: find.text(title));

  PanelController controllerOf(WidgetTester tester) =>
      tester.widget<PanelHost>(find.byType(PanelHost)).controller;

  testWidgets('the demo draws its four regions', (tester) async {
    await pump(tester);
    expect(find.byType(PanelHeader), findsOneWidget, reason: 'Files');
    expect(chip('chapter-one.md'), findsOneWidget);
    expect(chip('Inspector'), findsOneWidget);
    expect(chip('Console'), findsOneWidget);
    expect(find.byType(DividerHandle), findsNWidgets(3));
  });

  testWidgets(
    'a new editor joins the editor group and typing survives a move',
    (tester) async {
      await pump(tester);
      await tester.tap(find.text('Editor'));
      await tester.pump();
      expect(chip('Untitled 4'), findsOneWidget);

      await tester.enterText(find.byType(TextField).hitTestable(), 'kept');
      await tester.pump();

      controllerOf(tester).dock(
        mainWindow,
        const DockSource.tab('editor-4'),
        const DockTarget.split('tools', DockSide.bottom),
      );
      await tester.pump();
      expect(find.text('kept'), findsOneWidget);
    },
  );

  testWidgets('a tool never joins the editors', (tester) async {
    await pump(tester);
    final controller = controllerOf(tester);
    expect(
      controller.dock(
        mainWindow,
        const DockSource.tab('inspector'),
        const DockTarget.join('editors'),
      ),
      isFalse,
    );
    expect(
      controller.dock(
        mainWindow,
        const DockSource.tab('inspector'),
        const DockTarget.join('bottom'),
      ),
      isTrue,
      reason: 'the console is a tool too',
    );
  });

  testWidgets('save and restore round-trip the layout', (tester) async {
    await pump(tester);
    final controller = controllerOf(tester);
    final before = controller.rootOf(mainWindow);
    await tester.tap(find.text('Save'));
    await tester.pump();
    await controller.close('outline');
    await tester.pump();
    expect(chip('Outline'), findsNothing);
    await tester.tap(find.text('Restore'));
    await tester.pump();
    expect(controller.rootOf(mainWindow), before);
    expect(chip('Outline'), findsOneWidget);
  });

  testWidgets('the style switcher redraws the editors, not the tools', (
    tester,
  ) async {
    await pump(tester);
    Finder painted() => find.byWidgetPredicate(
      (w) => w is CustomPaint && w.painter is BlendedChipPainter,
    );
    expect(painted(), findsNothing);
    await tester.tap(find.text('blended'));
    await tester.pump();
    expect(painted(), findsNWidgets(3), reason: 'three editor chips');
    expect(chip('Inspector'), findsOneWidget);
  });

  testWidgets('twelve editors make the strip scroll, focus reaches the last', (
    tester,
  ) async {
    await pump(tester);
    await tester.tap(find.text('Twelve'));
    await tester.pump();
    final strip = tester
        .widgetList<TabStrip>(find.byType(TabStrip))
        .firstWhere((s) => s.scope.group.id == 'editors');
    await tester.pumpAndSettle();
    final position = strip.scope.scrollController.position;
    expect(position.maxScrollExtent, greaterThan(0));
    expect(
      position.pixels,
      position.maxScrollExtent,
      reason: 'the last opened editor was focused and revealed',
    );
    controllerOf(tester).focus('editor-1');
    await tester.pumpAndSettle();
    expect(position.pixels, 0);
  });

  testWidgets('typing marks the tab dirty and the guard asks before closing', (
    tester,
  ) async {
    await pump(tester);
    final controller = controllerOf(tester);
    await tester.enterText(find.byType(TextField).hitTestable(), 'changed');
    await tester.pump();
    expect(controller.tab('editor-1')!.metadata['dirty'], isTrue);

    final closing = controller.close('editor-1');
    await tester.pump();
    expect(find.text('Close chapter-one.md?'), findsOneWidget);
    await tester.tap(find.text('Keep'));
    await tester.pump();
    expect(await closing, isFalse);
    expect(chip('chapter-one.md'), findsOneWidget);
  });
}
