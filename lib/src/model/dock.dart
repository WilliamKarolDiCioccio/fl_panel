import 'geometry.dart';
import 'tab.dart';

/// What is being moved.
sealed class DockSource {
  const DockSource();

  /// One tab, taken out of whatever leaf holds it.
  const factory DockSource.tab(String tabId) = DockTabSource;

  /// A whole leaf — a single panel or a group with every one of its tabs.
  const factory DockSource.leaf(String leafId) = DockLeafSource;

  /// Content not yet in the tree: opening something new.
  const factory DockSource.fresh(List<PanelTab> tabs) = DockFreshSource;
}

final class DockTabSource extends DockSource {
  const DockTabSource(this.tabId);
  final String tabId;

  @override
  bool operator ==(Object other) =>
      other is DockTabSource && other.tabId == tabId;
  @override
  int get hashCode => Object.hash(DockTabSource, tabId);
  @override
  String toString() => 'DockSource.tab($tabId)';
}

final class DockLeafSource extends DockSource {
  const DockLeafSource(this.leafId);
  final String leafId;

  @override
  bool operator ==(Object other) =>
      other is DockLeafSource && other.leafId == leafId;
  @override
  int get hashCode => Object.hash(DockLeafSource, leafId);
  @override
  String toString() => 'DockSource.leaf($leafId)';
}

final class DockFreshSource extends DockSource {
  const DockFreshSource(this.tabs);
  final List<PanelTab> tabs;

  @override
  String toString() => 'DockSource.fresh(${tabs.map((t) => t.id).join(', ')})';
}

/// Where it lands.
sealed class DockTarget {
  const DockTarget();

  /// Into the leaf with [leafId] as tabs — at [index] in its strip, or at the
  /// end. Joining a single panel turns it into a group of two, which is where
  /// the "a panel CAN become a tab" of the specification happens.
  const factory DockTarget.join(String leafId, {int? index}) = DockJoin;

  /// Beside the node with [nodeId], on [side], as a new leaf of [form]. A
  /// tab dropped this way in the `single` form has left its strip and become
  /// a panel.
  const factory DockTarget.split(
    String nodeId,
    DockSide side, {
    SurfaceForm form,
  }) = DockSplit;

  /// Along a window edge: beside the whole tree.
  const factory DockTarget.root(DockSide side, {SurfaceForm form}) = DockRoot;
}

final class DockJoin extends DockTarget {
  const DockJoin(this.leafId, {this.index});
  final String leafId;
  final int? index;

  @override
  bool operator ==(Object other) =>
      other is DockJoin && other.leafId == leafId && other.index == index;
  @override
  int get hashCode => Object.hash(DockJoin, leafId, index);
  @override
  String toString() => 'DockTarget.join($leafId, index: $index)';
}

final class DockSplit extends DockTarget {
  const DockSplit(this.nodeId, this.side, {this.form = SurfaceForm.tabbed});
  final String nodeId;
  final DockSide side;
  final SurfaceForm form;

  @override
  bool operator ==(Object other) =>
      other is DockSplit &&
      other.nodeId == nodeId &&
      other.side == side &&
      other.form == form;
  @override
  int get hashCode => Object.hash(DockSplit, nodeId, side, form);
  @override
  String toString() => 'DockTarget.split($nodeId, ${side.name}, ${form.name})';
}

final class DockRoot extends DockTarget {
  const DockRoot(this.side, {this.form = SurfaceForm.tabbed});
  final DockSide side;
  final SurfaceForm form;

  @override
  bool operator ==(Object other) =>
      other is DockRoot && other.side == side && other.form == form;
  @override
  int get hashCode => Object.hash(DockRoot, side, form);
  @override
  String toString() => 'DockTarget.root(${side.name}, ${form.name})';
}
