import 'package:fl_panel/model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  PanelTab tab(String id, {Set<SurfaceForm>? forms}) => PanelTab(
    id: id,
    contentId: 'content.$id',
    forms: forms ?? const {SurfaceForm.single, SurfaceForm.tabbed},
  );
  SinglePanel panel(String id) => SinglePanel(id: 'p.$id', tab: tab(id));
  TabGroup tabGroup(String id, List<String> tabs, {int active = 0}) =>
      TabGroup(id: 'g.$id', tabs: tabs.map(tab).toList(), active: active);
  SplitNode split(
    String id,
    PanelAxis axis,
    List<LayoutNode> children, {
    List<PanelExtent>? sizes,
  }) => SplitNode(id: 's.$id', axis: axis, children: children, sizes: sizes);
  String Function() ids() {
    var n = 0;
    return () => 'new.${n++}';
  }

  group('normalise', () {
    test('a split of one is replaced by its child', () {
      final tree = split('a', PanelAxis.horizontal, [panel('x'), panel('y')]);
      final removed = LayoutTree.removeLeaf(tree, 'p.y');
      expect(
        removed,
        panel('x'),
        reason: 'the sibling absorbs the whole extent',
      );
    });

    test('a same-axis child split is spliced into its parent', () {
      final nested = split(
        'outer',
        PanelAxis.horizontal,
        [
          panel('a'),
          split('inner', PanelAxis.horizontal, [panel('b'), panel('c')]),
        ],
        sizes: const [PanelExtent.flex(1), PanelExtent.flex(1)],
      );
      final flat = LayoutTree.normalise(nested) as SplitNode;
      expect(flat.children, [panel('a'), panel('b'), panel('c')]);
      expect(flat.sizes, const [
        PanelExtent.flex(1),
        PanelExtent.flex(0.5),
        PanelExtent.flex(0.5),
      ], reason: 'the inner pair shares the half the inner split had');
    });

    test('a cross-axis child split is left alone', () {
      final nested = split('outer', PanelAxis.horizontal, [
        panel('a'),
        split('inner', PanelAxis.vertical, [panel('b'), panel('c')]),
      ]);
      expect(identical(LayoutTree.normalise(nested), nested), isTrue);
    });

    test('a group of one stays a group', () {
      final tree = tabGroup('g', ['a', 'b']);
      final closed = LayoutTree.removeTab(tree, 'b');
      expect(closed, tabGroup('g', ['a']));
    });

    test('closing the last tab of a group removes the leaf', () {
      final tree = split('s', PanelAxis.vertical, [
        tabGroup('g', ['a']),
        panel('b'),
      ]);
      expect(LayoutTree.removeTab(tree, 'a'), panel('b'));
      expect(LayoutTree.removeTab(panel('b'), 'b'), isNull);
    });

    test('closing a tab keeps the active content in view', () {
      final tree = tabGroup('g', ['a', 'b', 'c'], active: 2);
      final closed = LayoutTree.removeTab(tree, 'a') as TabGroup;
      expect(closed.activeTab.id, 'c', reason: 'the index shifts with the tab');
      final closedActive = LayoutTree.removeTab(tree, 'c') as TabGroup;
      expect(
        closedActive.activeTab.id,
        'b',
        reason: 'closing the active tab shows its neighbour',
      );
    });
  });

  group('dock', () {
    final a = panel('a');
    final b = panel('b');
    final base = split('root', PanelAxis.horizontal, [a, b]);

    test('a panel joining a panel makes a group of two under the same id', () {
      final joined = LayoutTree.dock(
        base,
        const DockSource.leaf('p.a'),
        const DockTarget.join('p.b'),
      );
      expect(
        joined,
        TabGroup(id: 'p.b', tabs: [tab('b'), tab('a')], active: 1),
      );
    });

    test('a tab leaving a group can become a single panel', () {
      final tree = split('root', PanelAxis.horizontal, [
        tabGroup('g', ['a', 'b']),
        panel('c'),
      ]);
      final result =
          LayoutTree.dock(
                tree,
                const DockSource.tab('a'),
                const DockTarget.split(
                  'p.c',
                  DockSide.bottom,
                  form: SurfaceForm.single,
                ),
                newId: ids(),
              )
              as SplitNode;
      expect(result.children.first, tabGroup('g', ['b']));
      final right = result.children[1] as SplitNode;
      expect(right.axis, PanelAxis.vertical);
      expect(right.children, [
        panel('c'),
        SinglePanel(id: 'new.0', tab: tab('a')),
      ]);
    });

    test('a split beside a same-axis sibling flattens and halves it', () {
      final tree = split('root', PanelAxis.horizontal, [a, b, panel('c')]);
      final result =
          LayoutTree.dock(
                tree,
                const DockSource.tab('a'),
                const DockTarget.split('p.b', DockSide.right),
                newId: ids(),
              )
              as SplitNode;
      expect(result.children, [
        b,
        TabGroup(id: 'new.0', tabs: [tab('a')]),
        panel('c'),
      ]);
      expect(
        result.sizes,
        const [
          PanelExtent.flex(0.5),
          PanelExtent.flex(0.5),
          PanelExtent.flex(1),
        ],
        reason: 'b gave half of its flex(1) to the newcomer; c is untouched',
      );
    });

    test('a split beside the lone remaining leaf wraps it in halves', () {
      final result =
          LayoutTree.dock(
                base,
                const DockSource.tab('a'),
                const DockTarget.split('p.b', DockSide.bottom),
                newId: ids(),
              )
              as SplitNode;
      expect(result.axis, PanelAxis.vertical);
      expect(result.children, [
        b,
        TabGroup(id: 'new.0', tabs: [tab('a')]),
      ]);
      expect(result.sizes, const [PanelExtent.flex(1), PanelExtent.flex(1)]);
    });

    test('a tab dropped on the centre of its own group is a no-op', () {
      final tree = tabGroup('g', ['a', 'b']);
      expect(
        LayoutTree.dock(
          tree,
          const DockSource.tab('a'),
          const DockTarget.join('g.g'),
        ),
        isNull,
      );
    });

    test('a panel dropped beside itself is a no-op', () {
      expect(
        LayoutTree.dock(
          base,
          const DockSource.leaf('p.a'),
          const DockTarget.split('p.a', DockSide.left),
        ),
        isNull,
      );
    });

    test('reordering within a strip counts indices with the tab in place', () {
      final tree = tabGroup('g', ['a', 'b', 'c']);
      TabGroup move(String id, int index) =>
          LayoutTree.dock(
                tree,
                DockSource.tab(id),
                DockTarget.join('g.g', index: index),
              )
              as TabGroup;
      expect(move('a', 3).tabs.map((t) => t.id), ['b', 'c', 'a']);
      expect(move('c', 0).tabs.map((t) => t.id), ['c', 'a', 'b']);
      expect(move('a', 2).tabs.map((t) => t.id), ['b', 'a', 'c']);
      expect(
        LayoutTree.dock(
          tree,
          const DockSource.tab('b'),
          const DockTarget.join('g.g', index: 1),
        ),
        isNull,
        reason: 'dropping a tab into its own slot changes nothing',
      );
      expect(
        LayoutTree.dock(
          tree,
          const DockSource.tab('b'),
          const DockTarget.join('g.g', index: 2),
        ),
        isNull,
        reason: 'and so does the slot right after it',
      );
    });

    test('an empty window takes the dropped leaf as its root', () {
      final result = LayoutTree.dock(
        null,
        DockSource.fresh([tab('a')]),
        const DockTarget.root(DockSide.left, form: SurfaceForm.single),
        newId: ids(),
      );
      expect(result, SinglePanel(id: 'new.0', tab: tab('a')));
    });

    test('a window-edge drop splits the whole tree', () {
      final result =
          LayoutTree.dock(
                base,
                DockSource.fresh([tab('c')]),
                const DockTarget.root(DockSide.bottom),
                newId: ids(),
              )
              as SplitNode;
      expect(result.axis, PanelAxis.vertical);
      expect(result.children.first, base);
    });
  });

  group('affinity', () {
    test('level one: a tab that may not stand alone cannot become a panel', () {
      final tree = tabGroup('g', ['a', 'b']);
      final locked = tree.copyWith(
        tabs: [
          tab('a', forms: const {SurfaceForm.tabbed}),
          tab('b'),
        ],
      );
      expect(
        LayoutTree.dock(
          locked,
          const DockSource.tab('a'),
          const DockTarget.split(
            'g.g',
            DockSide.left,
            form: SurfaceForm.single,
          ),
        ),
        isNull,
      );
      expect(
        LayoutTree.dock(
          locked,
          const DockSource.tab('a'),
          const DockTarget.split('g.g', DockSide.left),
        ),
        isNotNull,
        reason: 'as a group of one it is fine',
      );
    });

    test(
      'level one: a single panel that may not be tabbed refuses company',
      () {
        final solo = SinglePanel(
          id: 'p.a',
          tab: tab('a', forms: const {SurfaceForm.single}),
        );
        final tree = split('s', PanelAxis.horizontal, [solo, panel('b')]);
        expect(
          LayoutTree.dock(
            tree,
            const DockSource.leaf('p.b'),
            const DockTarget.join('p.a'),
          ),
          isNull,
        );
        expect(
          LayoutTree.dock(
            tree,
            const DockSource.leaf('p.a'),
            const DockTarget.join('p.b'),
          ),
          isNull,
          reason: 'nor can it join anyone else',
        );
      },
    );

    test('level two: the host decides who groups with whom', () {
      final tree = split('s', PanelAxis.horizontal, [
        TabGroup(
          id: 'tools',
          tabs: [
            PanelTab(
              id: 't1',
              contentId: 'tool',
              metadata: const {'kind': 'tool'},
            ),
          ],
        ),
        TabGroup(
          id: 'docs',
          tabs: [
            PanelTab(
              id: 'd1',
              contentId: 'doc',
              metadata: const {'kind': 'document'},
            ),
          ],
        ),
      ]);
      const policy = _SameKindOnly();
      expect(
        LayoutTree.dock(
          tree,
          const DockSource.tab('t1'),
          const DockTarget.join('docs'),
          policy: policy,
        ),
        isNull,
      );
      expect(
        LayoutTree.dock(
          tree,
          const DockSource.tab('t1'),
          const DockTarget.split('docs', DockSide.right),
          policy: policy,
        ),
        isNotNull,
        reason: 'beside is not among',
      );
    });
  });

  group('json', () {
    final app = PanelApp(
      windows: [
        PanelWindow(
          id: 'main',
          root: split(
            'root',
            PanelAxis.horizontal,
            [
              SinglePanel(
                id: 'p.files',
                tab: PanelTab(
                  id: 'files',
                  contentId: 'files',
                  metadata: const {
                    'title': 'Files',
                    'depth': 2,
                    'tags': ['a', 'b'],
                  },
                  forms: const {SurfaceForm.single},
                  minWidth: 160,
                ),
              ),
              tabGroup('editors', ['a', 'b'], active: 1),
            ],
            sizes: const [PanelExtent.fixed(240), PanelExtent.flex(1)],
          ),
        ),
        const PanelWindow(id: 'aux'),
      ],
    );

    test('round-trips', () {
      final json = PanelJson.encodeApp(app);
      expect(json['version'], PanelApp.version);
      expect(PanelJson.decodeApp(json), app);
    });

    test('refuses a newer version', () {
      final json = PanelJson.encodeApp(app)..['version'] = PanelApp.version + 1;
      expect(
        () => PanelJson.decodeApp(json),
        throwsA(isA<PanelFormatException>()),
      );
    });

    test('a dropped tab takes its empty leaf with it', () {
      final restored = PanelJson.decodeApp(
        PanelJson.encodeApp(app),
        resolve: (tab) => tab.contentId == 'files' ? null : tab,
      );
      expect(
        restored.window('main')!.root,
        tabGroup('editors', ['a', 'b'], active: 1),
        reason: 'the split of one collapsed onto the group',
      );
    });

    test('dropping a tab before the active one keeps the content shown', () {
      final restored = PanelJson.decodeApp(
        PanelJson.encodeApp(app),
        resolve: (tab) => tab.id == 'a' ? null : tab,
      );
      final editors =
          restored.window('main')!.root!.find('g.editors') as TabGroup;
      expect(editors.activeTab.id, 'b');
    });
  });
}

final class _SameKindOnly extends DockPolicy {
  const _SameKindOnly();

  @override
  bool canJoin(PanelTab moving, LeafNode target) => target.tabs.every(
    (tab) => tab.metadata['kind'] == moving.metadata['kind'],
  );
}
