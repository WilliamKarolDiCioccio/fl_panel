/// The axis a split lays its children along.
///
/// `horizontal` places children side by side, left to right; `vertical`
/// stacks them top to bottom. The naming follows Flutter's `Axis` — a
/// horizontal split is a `Row` — so a host converting at the edge has nothing
/// to remember.
enum PanelAxis {
  horizontal,
  vertical;

  PanelAxis get flipped =>
      this == PanelAxis.horizontal ? PanelAxis.vertical : PanelAxis.horizontal;
}

/// A side of a rectangle: where a dropped panel lands relative to a target.
enum DockSide {
  left,
  top,
  right,
  bottom;

  /// The axis of the split a drop on this side creates.
  PanelAxis get axis => this == DockSide.left || this == DockSide.right
      ? PanelAxis.horizontal
      : PanelAxis.vertical;

  /// Whether the dropped node goes before (`true`) or after the target along
  /// [axis].
  bool get before => this == DockSide.left || this == DockSide.top;
}

/// An axis-aligned rectangle in whatever coordinate space the caller lays out
/// in. The model and the solver import nothing from Flutter, so they carry
/// their own; the widget layer converts at the edge.
final class PanelRect {
  const PanelRect(this.left, this.top, this.width, this.height);

  const PanelRect.zero() : this(0, 0, 0, 0);

  final double left;
  final double top;
  final double width;
  final double height;

  double get right => left + width;
  double get bottom => top + height;

  bool get isEmpty => width <= 0 || height <= 0;

  /// The extent along [axis] — width for horizontal, height for vertical.
  double along(PanelAxis axis) => axis == PanelAxis.horizontal ? width : height;

  /// The origin along [axis] — left for horizontal, top for vertical.
  double start(PanelAxis axis) => axis == PanelAxis.horizontal ? left : top;

  bool contains(double x, double y) =>
      x >= left && x < right && y >= top && y < bottom;

  PanelRect deflate(double by) =>
      PanelRect(left + by, top + by, width - 2 * by, height - 2 * by);

  @override
  bool operator ==(Object other) =>
      other is PanelRect &&
      other.left == left &&
      other.top == top &&
      other.width == width &&
      other.height == height;

  @override
  int get hashCode => Object.hash(left, top, width, height);

  @override
  String toString() => 'PanelRect($left, $top, $width × $height)';
}
