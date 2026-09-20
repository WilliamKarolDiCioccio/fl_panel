import 'geometry.dart';
import 'tab.dart';

/// How much of its parent a split child takes.
///
/// `flex` children share what is left after the `fixed` ones have taken their
/// pixels, in proportion to their weights. Weights persist and pixels do not,
/// which is what makes a saved layout indifferent to DPI and window size; a
/// fixed extent is for the strip that must stay 240 wide whatever happens to
/// the window.
sealed class PanelExtent {
  const PanelExtent();

  const factory PanelExtent.flex([double weight]) = FlexExtent;
  const factory PanelExtent.fixed(double pixels) = FixedExtent;
}

final class FlexExtent extends PanelExtent {
  const FlexExtent([this.weight = 1]) : assert(weight > 0);
  final double weight;

  @override
  bool operator ==(Object other) =>
      other is FlexExtent && other.weight == weight;
  @override
  int get hashCode => Object.hash(FlexExtent, weight);
  @override
  String toString() => 'flex($weight)';
}

final class FixedExtent extends PanelExtent {
  const FixedExtent(this.pixels) : assert(pixels >= 0);
  final double pixels;

  @override
  bool operator ==(Object other) =>
      other is FixedExtent && other.pixels == pixels;
  @override
  int get hashCode => Object.hash(FixedExtent, pixels);
  @override
  String toString() => 'fixed($pixels)';
}

/// A node of a window's layout tree.
///
/// The tree is a BSP tree with one relaxation: a [SplitNode] holds any number
/// of children along one axis, and no child ever shares its parent's axis.
/// A strictly binary tree draws `((A|B)|C)` and `(A|(B|C))` identically and
/// resizes them differently, and which one a user has is an accident of the
/// order they docked things in. Flattening same-axis nesting gives every
/// layout exactly one tree, so a saved file round-trips to what the user
/// recognises and tests compare trees by equality.
sealed class LayoutNode {
  const LayoutNode();

  String get id;

  /// Every leaf under this node, in reading order.
  Iterable<LeafNode> get leaves;

  /// Every tab under this node, in reading order.
  Iterable<PanelTab> get tabs => leaves.expand((leaf) => leaf.tabs);

  /// The node with [nodeId] under this one, itself included.
  LayoutNode? find(String nodeId);

  /// The split directly above [nodeId], or null at the root or when absent.
  SplitNode? parentOf(String nodeId);

  /// The leaf holding [tabId].
  LeafNode? leafOf(String tabId) {
    for (final leaf in leaves) {
      if (leaf.tabs.any((tab) => tab.id == tabId)) return leaf;
    }
    return null;
  }

  /// The smallest extent this subtree can be laid out at along [axis].
  double minAlong(PanelAxis axis, double dividerThickness);
}

final class SplitNode extends LayoutNode {
  SplitNode({
    required this.id,
    required this.axis,
    required List<LayoutNode> children,
    List<PanelExtent>? sizes,
  }) : assert(children.length >= 2, 'a split holds at least two children'),
       assert(
         sizes == null || sizes.length == children.length,
         'one extent per child',
       ),
       children = List.unmodifiable(children),
       sizes = List.unmodifiable(
         sizes ?? List.filled(children.length, const PanelExtent.flex()),
       );

  @override
  final String id;
  final PanelAxis axis;
  final List<LayoutNode> children;
  final List<PanelExtent> sizes;

  @override
  Iterable<LeafNode> get leaves => children.expand((child) => child.leaves);

  @override
  LayoutNode? find(String nodeId) {
    if (nodeId == id) return this;
    for (final child in children) {
      final found = child.find(nodeId);
      if (found != null) return found;
    }
    return null;
  }

  @override
  SplitNode? parentOf(String nodeId) {
    for (final child in children) {
      if (child.id == nodeId) return this;
      final found = child.parentOf(nodeId);
      if (found != null) return found;
    }
    return null;
  }

  /// Along its own axis a split needs every child's minimum plus the
  /// dividers; across it, the largest. Fixed extents are not minimums: a
  /// fixed child is a preference the solver honours when it can, and only
  /// content minimums are hard.
  @override
  double minAlong(PanelAxis along, double dividerThickness) {
    if (along == axis) {
      var total = dividerThickness * (children.length - 1);
      for (final child in children) {
        total += child.minAlong(along, dividerThickness);
      }
      return total;
    }
    var largest = 0.0;
    for (final child in children) {
      final min = child.minAlong(along, dividerThickness);
      if (min > largest) largest = min;
    }
    return largest;
  }

  SplitNode copyWith({
    PanelAxis? axis,
    List<LayoutNode>? children,
    List<PanelExtent>? sizes,
  }) => SplitNode(
    id: id,
    axis: axis ?? this.axis,
    children: children ?? this.children,
    sizes: sizes ?? this.sizes,
  );

  @override
  bool operator ==(Object other) =>
      other is SplitNode &&
      other.id == id &&
      other.axis == axis &&
      _sameList(other.children, children) &&
      _sameList(other.sizes, sizes);

  @override
  int get hashCode => Object.hash(id, axis, children.length);

  @override
  String toString() =>
      'Split(${axis.name}, ${children.map((c) => c.toString()).join(' | ')})';
}

/// A node that shows content: a single panel or a tab group.
///
/// The two stay distinct in the model rather than being a flag on one type,
/// because the affinities are about which *form* a content may take, and
/// both shapes exist in real products — Blender's areas are single panels
/// with a header, VS Code's editor groups keep their strip at one tab. A group
/// of one never collapses to a single panel by itself; only a drop that asks
/// for the single form makes one.
sealed class LeafNode extends LayoutNode {
  const LeafNode();

  @override
  List<PanelTab> get tabs;

  /// The tab currently shown.
  PanelTab get activeTab;

  /// The form every tab in this leaf currently takes.
  SurfaceForm get form;

  @override
  Iterable<LeafNode> get leaves => [this];

  @override
  LayoutNode? find(String nodeId) => nodeId == id ? this : null;

  @override
  SplitNode? parentOf(String nodeId) => null;

  /// A leaf's minimum is the largest minimum among its tabs, not the active
  /// tab's — switching tabs must never move a divider.
  @override
  double minAlong(PanelAxis axis, double dividerThickness) {
    var largest = 0.0;
    for (final tab in tabs) {
      final min = axis == PanelAxis.horizontal ? tab.minWidth : tab.minHeight;
      if (min > largest) largest = min;
    }
    return largest;
  }
}

final class SinglePanel extends LeafNode {
  const SinglePanel({required this.id, required this.tab});

  @override
  final String id;
  final PanelTab tab;

  @override
  List<PanelTab> get tabs => [tab];

  @override
  PanelTab get activeTab => tab;

  @override
  SurfaceForm get form => SurfaceForm.single;

  SinglePanel copyWith({PanelTab? tab}) =>
      SinglePanel(id: id, tab: tab ?? this.tab);

  @override
  bool operator ==(Object other) =>
      other is SinglePanel && other.id == id && other.tab == tab;

  @override
  int get hashCode => Object.hash(id, tab);

  @override
  String toString() => 'Panel(${tab.id})';
}

final class TabGroup extends LeafNode {
  TabGroup({required this.id, required List<PanelTab> tabs, this.active = 0})
    : assert(tabs.isNotEmpty, 'a group holds at least one tab'),
      assert(active >= 0 && active < tabs.length, 'active tab out of range'),
      tabs = List.unmodifiable(tabs);

  @override
  final String id;

  @override
  final List<PanelTab> tabs;

  /// Index into [tabs] of the tab shown.
  final int active;

  @override
  PanelTab get activeTab => tabs[active];

  @override
  SurfaceForm get form => SurfaceForm.tabbed;

  int indexOf(String tabId) => tabs.indexWhere((tab) => tab.id == tabId);

  TabGroup copyWith({List<PanelTab>? tabs, int? active}) =>
      TabGroup(id: id, tabs: tabs ?? this.tabs, active: active ?? this.active);

  @override
  bool operator ==(Object other) =>
      other is TabGroup &&
      other.id == id &&
      other.active == active &&
      _sameList(other.tabs, tabs);

  @override
  int get hashCode => Object.hash(id, active, tabs.length);

  @override
  String toString() =>
      'Group(${tabs.map((t) => t.id).join(', ')}; active ${tabs[active].id})';
}

bool _sameList<T>(List<T> a, List<T> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
