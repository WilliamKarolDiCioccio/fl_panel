import 'dart:async';

import 'package:flutter/foundation.dart';

import '../layout/dock_resolver.dart';
import '../layout/solver.dart';
import '../model/dock.dart';
import '../model/edits.dart';
import '../model/geometry.dart';
import '../model/json.dart';
import '../model/node.dart';
import '../model/tab.dart';
import '../model/window.dart';
import '../policy/dock_policy.dart';

/// A drag in progress: what is being moved, from which window, and the drop
/// it would make right now.
final class DockDrag {
  const DockDrag({
    required this.windowId,
    required this.source,
    required this.preferredForm,
    this.candidate,
  });

  final String windowId;
  final DockSource source;

  /// The form the moved content takes when it is put down as a new leaf: a
  /// tab pulled from a strip stays tabbed, a single panel stays single, each
  /// falling back to the other when its own is refused.
  final SurfaceForm preferredForm;
  final DockCandidate? candidate;

  DockDrag withCandidate(DockCandidate? candidate) => DockDrag(
    windowId: windowId,
    source: source,
    preferredForm: preferredForm,
    candidate: candidate,
  );
}

/// "Bring this tab into view" — and, with [keyboard], give its content the
/// keyboard. Issued by [PanelController.focus]; the host answers it after the
/// next layout, once it knows where the chip is. The nonce is what tells a
/// host it has not answered this one yet.
final class RevealRequest {
  const RevealRequest({
    required this.tabId,
    required this.keyboard,
    required this.nonce,
  });

  final String tabId;
  final bool keyboard;
  final int nonce;
}

/// Asked before a tab closes. Return false to keep it — an unsaved document,
/// a session mid-way. Asked once per tab, in order, for the group verbs too.
typedef CloseGuard = Future<bool> Function(PanelTab tab);

/// What changed, for a host that keeps things behind tabs — sessions,
/// documents — and needs to know when one appears, moves or goes.
sealed class PanelEvent {
  const PanelEvent();
}

final class TabOpened extends PanelEvent {
  const TabOpened(this.tab, this.windowId, this.leafId);
  final PanelTab tab;
  final String windowId;
  final String leafId;
}

final class TabClosed extends PanelEvent {
  const TabClosed(this.tab, this.windowId, this.leafId);
  final PanelTab tab;
  final String windowId;
  final String leafId;
}

final class TabMoved extends PanelEvent {
  const TabMoved(this.tab, this.from, this.to);
  final PanelTab tab;
  final TabPlacement from;
  final TabPlacement to;
}

/// The tab's own fields changed — a title, a flag — through [PanelController.updateTab].
final class TabUpdated extends PanelEvent {
  const TabUpdated(this.before, this.after);
  final PanelTab before;
  final PanelTab after;
}

final class TabActivated extends PanelEvent {
  const TabActivated(this.tab, this.windowId, this.leafId);
  final PanelTab tab;
  final String windowId;
  final String leafId;
}

final class LeafFocused extends PanelEvent {
  const LeafFocused(this.windowId, this.leafId);
  final String windowId;
  final String leafId;
}

/// Every window was replaced at once — a file loaded, a preset applied. The
/// tab diff against the previous state is sent first, as opens and closes.
final class LayoutReplaced extends PanelEvent {
  const LayoutReplaced();
}

/// The one object an application holds: the layout of every window, the
/// verbs that edit it, the drag session, and the file format.
///
/// State is the immutable [PanelApp]; every verb swaps it for a new one and
/// notifies. The widget layer is a view onto this and knows nothing about
/// what a tab contains.
class PanelController extends ChangeNotifier {
  PanelController({
    PanelApp? app,
    this.policy = DockPolicy.permissive,
    this.solver = const PanelSolver(),
    this.newId = PanelIds.next,
    this.onSettled,
    this.closeGuard,
  }) : _app = app ?? PanelApp();

  /// What may dock where. Swappable at runtime; the next drag reads it.
  DockPolicy policy;

  /// Geometry: divider thickness and the distribution of extents.
  final PanelSolver solver;

  /// Fresh ids for the splits and leaves edits create.
  final String Function() newId;

  /// Called after every edit that is worth writing to disk — a drop, a close,
  /// a divider released — and not for the frames of a drag in between, nor
  /// for a change of active tab or focused leaf.
  VoidCallback? onSettled;

  /// Consulted before any tab closes, from the × as much as from a verb.
  CloseGuard? closeGuard;

  PanelApp _app;
  PanelApp get app => _app;

  final _events = StreamController<PanelEvent>.broadcast(sync: true);

  /// What changed, as it changes. Synchronous: a listener sees the event
  /// before the frame that draws its consequence.
  Stream<PanelEvent> get events => _events.stream;

  DockDrag? _drag;

  /// The drag in progress, if any. Listeners see it change as the pointer
  /// moves; the overlay draws its candidate.
  DockDrag? get drag => _drag;

  RevealRequest? _reveal;
  int _revealNonce = 0;

  /// The outstanding reveal, if any. A host showing the tab's window answers
  /// it; see [RevealRequest].
  RevealRequest? get reveal => _reveal;

  PanelWindow? window(String id) => _app.window(id);
  LayoutNode? rootOf(String windowId) => _app.window(windowId)?.root;

  /// The leaf `open` puts content in and the keyboard verbs act on.
  LeafNode? focusedLeaf(String windowId) => _app.window(windowId)?.focusedLeaf;

  PanelTab? tab(String tabId) {
    for (final placement in _app.placements) {
      if (placement.tab.id == tabId) return placement.tab;
    }
    return null;
  }

  @override
  void dispose() {
    _events.close();
    super.dispose();
  }

  // -- whole-layout ---------------------------------------------------------

  /// Replaces every window at once — restoring a file, applying a preset.
  void replaceApp(PanelApp app) {
    final before = _app;
    _app = app;
    _drag = null;
    _reveal = null;
    _emitDiff(before, app);
    _events.add(const LayoutReplaced());
    notifyListeners();
    onSettled?.call();
  }

  void setRoot(String windowId, LayoutNode? root) {
    final window = _app.window(windowId) ?? PanelWindow(id: windowId);
    _commit(_app.withWindow(window.withRoot(LayoutTree.normalise(root))));
  }

  Map<String, Object?> toJson() => PanelJson.encodeApp(_app);

  /// Reads a file written by [toJson]. Throws [PanelFormatException] for a
  /// newer version; [resolve] may drop tabs this build no longer knows.
  void load(Map<String, Object?> json, {TabResolver? resolve}) {
    replaceApp(PanelJson.decodeApp(json, resolve: resolve));
  }

  // -- tabs -----------------------------------------------------------------

  /// Shows [tabId] in its group and focuses the group. Not settled: which
  /// tab is active is persisted, but not worth a write per click.
  void activate(String tabId) {
    final window = _app.windowOfTab(tabId);
    final leaf = window?.root?.leafOf(tabId);
    if (window == null || leaf == null) return;
    final root = LayoutTree.activate(window.root, tabId);
    final focusChanged = window.focusedLeafId != leaf.id;
    if (identical(root, window.root) && !focusChanged) return;
    _app = _app.withWindow(window.withRoot(root).withFocus(leaf.id));
    if (!identical(root, window.root)) {
      _events.add(TabActivated(tab(tabId)!, window.id, leaf.id));
    }
    if (focusChanged) _events.add(LeafFocused(window.id, leaf.id));
    notifyListeners();
  }

  /// [activate], and bring the tab into view: a strip that scrolls scrolls
  /// to its chip; with [keyboard], its content gets the keyboard too. The
  /// verb an application calls when it opens or jumps to something.
  void focus(String tabId, {bool keyboard = false}) {
    if (_app.windowOfTab(tabId) == null) return;
    activate(tabId);
    _reveal = RevealRequest(
      tabId: tabId,
      keyboard: keyboard,
      nonce: ++_revealNonce,
    );
    notifyListeners();
  }

  /// Makes [leafId] the window's focused leaf without changing its active
  /// tab — the pointer going down in a panel, say.
  void focusLeaf(String windowId, String leafId) {
    final window = _app.window(windowId);
    if (window == null || window.focusedLeafId == leafId) return;
    if (window.root?.find(leafId) is! LeafNode) return;
    _app = _app.withWindow(window.withFocus(leafId));
    _events.add(LeafFocused(windowId, leafId));
    notifyListeners();
  }

  /// Closes [tabId], unless [closeGuard] says no. True when it closed.
  Future<bool> close(String tabId) async {
    final target = tab(tabId);
    if (target == null) return false;
    if (closeGuard != null && !await closeGuard!(target)) return false;
    final window = _app.windowOfTab(tabId);
    if (window == null) return false;
    _commit(
      _app.withWindow(
        window.withRoot(LayoutTree.removeTab(window.root, tabId)),
      ),
    );
    return true;
  }

  /// Closes every tab of [leafId] the guard allows.
  Future<void> closeLeaf(String windowId, String leafId) async {
    final leaf = _app.window(windowId)?.root?.find(leafId);
    if (leaf is! LeafNode) return;
    for (final tab in leaf.tabs) {
      await close(tab.id);
    }
  }

  /// Closes the other tabs of [tabId]'s group.
  Future<void> closeOthers(String tabId) async {
    final leaf = _app.windowOfTab(tabId)?.root?.leafOf(tabId);
    if (leaf == null) return;
    for (final tab in leaf.tabs) {
      if (tab.id != tabId) await close(tab.id);
    }
  }

  /// Closes the tabs after [tabId] in its strip.
  Future<void> closeToTheRight(String tabId) async {
    final leaf = _app.windowOfTab(tabId)?.root?.leafOf(tabId);
    if (leaf is! TabGroup) return;
    final from = leaf.indexOf(tabId);
    for (final tab in leaf.tabs.skip(from + 1)) {
      await close(tab.id);
    }
  }

  /// Closes the active tab of the focused leaf.
  Future<bool> closeActive(String windowId) async {
    final leaf = focusedLeaf(windowId);
    return leaf == null ? false : close(leaf.activeTab.id);
  }

  /// Activates the tab after the active one in the focused group, wrapping.
  void nextTab(String windowId) => _step(windowId, 1);

  void previousTab(String windowId) => _step(windowId, -1);

  void _step(String windowId, int by) {
    final leaf = focusedLeaf(windowId);
    if (leaf is! TabGroup || leaf.tabs.length < 2) return;
    final index = (leaf.active + by) % leaf.tabs.length;
    activate(leaf.tabs[index].id);
  }

  /// Replaces a tab's fields in place: a title after a rename, a flag. The
  /// id may not change — that would be a different tab.
  void updateTab(String tabId, PanelTab Function(PanelTab tab) change) {
    final window = _app.windowOfTab(tabId);
    final before = tab(tabId);
    if (window == null || before == null) return;
    final after = change(before);
    assert(after.id == before.id, 'updateTab may not change the id');
    if (after == before) return;
    _app = _app.withWindow(
      window.withRoot(LayoutTree.replaceTab(window.root, after)),
    );
    _events.add(TabUpdated(before, after));
    notifyListeners();
    onSettled?.call();
  }

  // -- placing --------------------------------------------------------------

  /// Moves [source] to [target] in [windowId]. Returns whether anything
  /// changed — false when the policy refuses or the move is a no-op.
  bool dock(String windowId, DockSource source, DockTarget target) {
    final window = _app.window(windowId) ?? PanelWindow(id: windowId);
    final root = LayoutTree.dock(
      window.root,
      source,
      target,
      policy: policy,
      newId: newId,
    );
    if (root == null) return false;
    _commit(_app.withWindow(window.withRoot(root)));
    return true;
  }

  /// Opens content that is not in the tree yet and focuses its first tab.
  /// With no [target] it joins the window's focused leaf — or, when that leaf
  /// or the policy refuses, the first leaf that accepts, or a new leaf along
  /// the right edge. An empty or missing window takes it as the root.
  bool open(String windowId, List<PanelTab> tabs, {DockTarget? target}) {
    if (tabs.isEmpty) return false;
    final window = _app.window(windowId) ?? PanelWindow(id: windowId);
    final root = window.root;
    final source = DockFreshSource(tabs);
    LayoutNode? attempt(DockTarget where) =>
        LayoutTree.dock(root, source, where, policy: policy, newId: newId);

    LayoutNode? result;
    if (root == null) {
      result = attempt(
        DockRoot(
          DockSide.right,
          form: target == null ? SurfaceForm.tabbed : _formOf(target),
        ),
      );
    } else if (target != null) {
      result = attempt(target);
    } else {
      final candidates = <DockTarget>[
        DockJoin(window.focusedLeaf!.id),
        for (final leaf in root.leaves) DockJoin(leaf.id),
        const DockRoot(DockSide.right),
      ];
      for (final where in candidates) {
        result = attempt(where);
        if (result != null) break;
      }
    }
    if (result == null) return false;
    _commit(_app.withWindow(window.withRoot(result)));
    focus(tabs.first.id);
    return true;
  }

  /// Moves a tab out of its window and into [toWindowId]. The other window
  /// is created when it does not exist, so this is also how a tab is torn
  /// off into a new one.
  bool moveToWindow(
    String tabId,
    String toWindowId, {
    DockTarget target = const DockRoot(DockSide.right),
  }) {
    final from = _app.windowOfTab(tabId);
    final moving = tab(tabId);
    if (from == null || moving == null || from.id == toWindowId) return false;
    final to = _app.window(toWindowId) ?? PanelWindow(id: toWindowId);
    final root = LayoutTree.dock(
      to.root,
      DockFreshSource([moving]),
      to.root == null
          ? DockRoot(DockSide.right, form: _formOf(target))
          : target,
      policy: policy,
      newId: newId,
    );
    if (root == null) return false;
    _commit(
      _app
          .withWindow(from.withRoot(LayoutTree.removeTab(from.root, tabId)))
          .withWindow(to.withRoot(root)),
    );
    return true;
  }

  /// Drags the divider after child [dividerIndex] of [splitId] by [delta]
  /// pixels, in a window laid out in [bounds]. Live: notifies and does not
  /// settle — call [settle] when the pointer is released.
  ///
  /// The current tree is solved here rather than read from the host's last
  /// frame on purpose: a pointer reports faster than the screen paints, and
  /// two deltas landing between frames must add up, not have the second
  /// measured against the same stale pixels as the first.
  void resize(
    String windowId,
    String splitId,
    int dividerIndex,
    double delta,
    PanelRect bounds,
  ) {
    final window = _app.window(windowId);
    final split = window?.root?.find(splitId);
    if (window == null || split is! SplitNode) return;
    final layout = solver.layout(window.root, bounds);
    final pixels = <double>[];
    for (final child in split.children) {
      final rect = layout.rectOf(child.id);
      if (rect == null) return;
      pixels.add(rect.along(split.axis));
    }
    final sizes = solver.resize(split, pixels, dividerIndex, delta);
    if (identical(sizes, split.sizes)) return;
    final root = LayoutTree.replace(
      window.root,
      splitId,
      split.copyWith(sizes: sizes),
    );
    _app = _app.withWindow(window.withRoot(root));
    notifyListeners();
  }

  /// Marks the end of a run of live edits: the moment to write to disk.
  void settle() => onSettled?.call();

  // -- drag session ---------------------------------------------------------

  void beginDrag(String windowId, DockSource source) {
    final root = rootOf(windowId);
    final SurfaceForm preferred = switch (source) {
      DockTabSource(:final tabId) =>
        root?.leafOf(tabId)?.form ?? SurfaceForm.tabbed,
      DockLeafSource(:final leafId) => switch (root?.find(leafId)) {
        LeafNode(:final form) => form,
        _ => SurfaceForm.tabbed,
      },
      DockFreshSource() => SurfaceForm.tabbed,
    };
    _drag = DockDrag(
      windowId: windowId,
      source: source,
      preferredForm: preferred,
    );
    notifyListeners();
  }

  /// Re-resolves the drop for what is under the pointer now.
  void updateDrag(DockHit hit, LayoutResult layout) {
    final drag = _drag;
    if (drag == null) return;
    final candidate = DockResolver(policy: policy, newId: newId).resolve(
      root: rootOf(drag.windowId),
      layout: layout,
      source: drag.source,
      hit: hit,
      preferredForm: drag.preferredForm,
    );
    if (candidate?.target == drag.candidate?.target &&
        candidate?.preview == drag.candidate?.preview) {
      return;
    }
    _drag = drag.withCandidate(candidate);
    notifyListeners();
  }

  /// Performs the drop the drag is over, if any, and ends the drag. A
  /// dropped tab is focused where it landed.
  bool commitDrag() {
    final drag = _drag;
    _drag = null;
    final candidate = drag?.candidate;
    if (drag == null || candidate == null) {
      notifyListeners();
      return false;
    }
    final window = _app.window(drag.windowId) ?? PanelWindow(id: drag.windowId);
    _commit(_app.withWindow(window.withRoot(candidate.result)));
    final moved = switch (drag.source) {
      DockTabSource(:final tabId) => tabId,
      DockLeafSource(:final leafId) =>
        (candidate.result.find(leafId) as LeafNode?)?.activeTab.id,
      DockFreshSource(:final tabs) => tabs.first.id,
    };
    if (moved != null) {
      final leaf = candidate.result.leafOf(moved);
      if (leaf != null) focusLeaf(drag.windowId, leaf.id);
    }
    return true;
  }

  void cancelDrag() {
    if (_drag == null) return;
    _drag = null;
    notifyListeners();
  }

  // -- internals ------------------------------------------------------------

  void _commit(PanelApp app) {
    final before = _app;
    _app = app;
    _emitDiff(before, app);
    notifyListeners();
    onSettled?.call();
  }

  /// Opens, closes and moves, by comparing where every tab was with where it
  /// is. One diff serves every verb, so no verb can forget to report.
  void _emitDiff(PanelApp before, PanelApp after) {
    if (!_events.hasListener) return;
    final was = {for (final p in before.placements) p.tab.id: p};
    final now = {for (final p in after.placements) p.tab.id: p};
    for (final entry in was.entries) {
      final to = now[entry.key];
      final from = entry.value;
      if (to == null) {
        _events.add(TabClosed(from.tab, from.windowId, from.leafId));
      } else if (to.windowId != from.windowId || to.leafId != from.leafId) {
        _events.add(TabMoved(to.tab, from, to));
      }
    }
    for (final entry in now.entries) {
      if (!was.containsKey(entry.key)) {
        final p = entry.value;
        _events.add(TabOpened(p.tab, p.windowId, p.leafId));
      }
    }
  }

  static SurfaceForm _formOf(DockTarget target) => switch (target) {
    DockSplit(:final form) => form,
    DockRoot(:final form) => form,
    DockJoin() => SurfaceForm.tabbed,
  };
}
