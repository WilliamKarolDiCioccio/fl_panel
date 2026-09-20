import '../model/geometry.dart';
import '../model/node.dart';

/// Where a divider between two split children is drawn, and what it resizes.
final class DividerGeometry {
  const DividerGeometry({
    required this.splitId,
    required this.index,
    required this.axis,
    required this.rect,
  });

  final String splitId;

  /// The divider sits after child [index] of its split.
  final int index;

  /// The axis of the split — the divider is dragged along it.
  final PanelAxis axis;
  final PanelRect rect;

  @override
  String toString() => 'Divider($splitId[$index] $rect)';
}

/// The solved layout of one window: a rectangle for every node, the dividers
/// between them. Splits are in [rects] too — the drop resolver uses the
/// root's bounds for its edge bands.
final class LayoutResult {
  const LayoutResult({
    required this.bounds,
    required this.rects,
    required this.dividers,
  });

  final PanelRect bounds;
  final Map<String, PanelRect> rects;
  final List<DividerGeometry> dividers;

  PanelRect? rectOf(String nodeId) => rects[nodeId];

  /// The leaf under a point, if any.
  LeafNode? leafAt(LayoutNode? root, double x, double y) {
    if (root == null) return null;
    for (final leaf in root.leaves) {
      final rect = rects[leaf.id];
      if (rect != null && rect.contains(x, y)) return leaf;
    }
    return null;
  }
}

/// The pure function from tree to rectangles, and its inverse for one
/// divider. Nothing here knows about widgets; the host calls [layout] with
/// its constraints and positions children where the result says.
final class PanelSolver {
  const PanelSolver({this.dividerThickness = 6});

  /// The gap between two split children, in the same units as the bounds.
  final double dividerThickness;

  LayoutResult layout(LayoutNode? root, PanelRect bounds) {
    final rects = <String, PanelRect>{};
    final dividers = <DividerGeometry>[];
    if (root != null) _layout(root, bounds, rects, dividers);
    return LayoutResult(bounds: bounds, rects: rects, dividers: dividers);
  }

  void _layout(
    LayoutNode node,
    PanelRect rect,
    Map<String, PanelRect> rects,
    List<DividerGeometry> dividers,
  ) {
    rects[node.id] = rect;
    if (node is! SplitNode) return;
    final gaps = dividerThickness * (node.children.length - 1);
    final sizes = distribute(node, rect.along(node.axis) - gaps);
    var offset = rect.start(node.axis);
    for (var i = 0; i < node.children.length; i++) {
      final child = node.axis == PanelAxis.horizontal
          ? PanelRect(offset, rect.top, sizes[i], rect.height)
          : PanelRect(rect.left, offset, rect.width, sizes[i]);
      _layout(node.children[i], child, rects, dividers);
      offset += sizes[i];
      if (i < node.children.length - 1) {
        dividers.add(
          DividerGeometry(
            splitId: node.id,
            index: i,
            axis: node.axis,
            rect: node.axis == PanelAxis.horizontal
                ? PanelRect(offset, rect.top, dividerThickness, rect.height)
                : PanelRect(rect.left, offset, rect.width, dividerThickness),
          ),
        );
        offset += dividerThickness;
      }
    }
  }

  /// The pixels each child of [split] takes of [available], the extent along
  /// its axis with the dividers already taken out.
  ///
  /// Fixed children take their pixels, flex children share the rest by
  /// weight, and every child is held at its minimum by taking from the ones
  /// with slack. When the minimums alone do not fit, every child is scaled
  /// down proportionally — the same call the two-pane split this replaces
  /// made — rather than one going to zero.
  List<double> distribute(SplitNode split, double available) {
    final n = split.children.length;
    final result = List<double>.filled(n, 0);
    if (available <= 0) return result;

    final mins = List<double>.generate(
      n,
      (i) => split.children[i].minAlong(split.axis, dividerThickness),
    );
    var minTotal = 0.0;
    for (final min in mins) {
      minTotal += min;
    }
    if (minTotal >= available) {
      if (minTotal == 0) return List.filled(n, available / n);
      final scale = available / minTotal;
      for (var i = 0; i < n; i++) {
        result[i] = mins[i] * scale;
      }
      return result;
    }

    var fixedTotal = 0.0;
    var flexMinTotal = 0.0;
    final flex = <int>[];
    for (var i = 0; i < n; i++) {
      final size = split.sizes[i];
      if (size is FixedExtent) {
        result[i] = size.pixels > mins[i] ? size.pixels : mins[i];
        fixedTotal += result[i];
      } else {
        flex.add(i);
        flexMinTotal += mins[i];
      }
    }

    if (flex.isEmpty) {
      // Nothing to absorb the remainder, so the fixed children stretch — a
      // fixed child is fixed relative to its flex siblings, not to a gap.
      final scale = available / fixedTotal;
      for (var i = 0; i < n; i++) {
        result[i] *= scale;
      }
      return result;
    }

    var remaining = available - fixedTotal;
    if (remaining < flexMinTotal) {
      // The fixed children are too greedy for the flex minimums. Give back
      // from their slack above their content minimums, in proportion; the
      // early return above guarantees enough slack exists.
      final shortfall = flexMinTotal - remaining;
      var slack = 0.0;
      for (var i = 0; i < n; i++) {
        if (split.sizes[i] is FixedExtent) {
          slack +=
              result[i] -
              split.children[i].minAlong(split.axis, dividerThickness);
        }
      }
      for (var i = 0; i < n; i++) {
        if (split.sizes[i] is FixedExtent && slack > 0) {
          final own =
              result[i] -
              split.children[i].minAlong(split.axis, dividerThickness);
          result[i] -= shortfall * own / slack;
        }
      }
      remaining = flexMinTotal;
    }

    // Flex share by weight, then hold anything below its minimum there and
    // share what is left among the rest. Each pass locks at least one child,
    // so it ends within n passes.
    final locked = List<bool>.filled(n, false);
    while (true) {
      var weights = 0.0;
      var pool = remaining;
      for (final i in flex) {
        if (locked[i]) {
          pool -= mins[i];
        } else {
          weights += (split.sizes[i] as FlexExtent).weight;
        }
      }
      var violated = false;
      for (final i in flex) {
        if (locked[i]) continue;
        result[i] = pool * (split.sizes[i] as FlexExtent).weight / weights;
        if (result[i] < mins[i]) {
          locked[i] = true;
          result[i] = mins[i];
          violated = true;
        }
      }
      if (!violated) break;
    }
    return result;
  }

  /// The extents of [split] after the divider after child [dividerIndex] is
  /// dragged by [delta] pixels, given the [pixels] each child has now. The
  /// two children either side trade the pixels, clamped so neither goes
  /// below its content minimum; nobody else moves. Flex children are
  /// re-encoded from their pixels so the rest of the row stays put.
  List<PanelExtent> resize(
    SplitNode split,
    List<double> pixels,
    int dividerIndex,
    double delta,
  ) {
    final a = dividerIndex;
    final b = dividerIndex + 1;
    final minA = split.children[a].minAlong(split.axis, dividerThickness);
    final minB = split.children[b].minAlong(split.axis, dividerThickness);
    final low = minA - pixels[a];
    final high = pixels[b] - minB;
    final moved = delta < low ? low : (delta > high ? high : delta);
    if (moved == 0 || high < low) return split.sizes;

    final next = List<double>.of(pixels);
    next[a] += moved;
    next[b] -= moved;

    var flexTotal = 0.0;
    for (var i = 0; i < next.length; i++) {
      if (split.sizes[i] is FlexExtent) flexTotal += next[i];
    }
    return List.generate(next.length, (i) {
      if (split.sizes[i] is FixedExtent) return FixedExtent(next[i]);
      // Weights are normalised to sum to one so a saved file reads as
      // proportions; the floor keeps a child dragged shut from becoming a
      // zero weight, which the model refuses.
      final weight = flexTotal == 0 ? 1.0 : next[i] / flexTotal;
      return FlexExtent(weight < 1e-4 ? 1e-4 : weight);
    });
  }
}
