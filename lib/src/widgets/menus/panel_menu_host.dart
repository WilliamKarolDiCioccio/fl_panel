import 'package:flutter/material.dart';

import 'panel_menu_entry.dart';

/// Renders [PanelMenuEntry] lists as a Material menu anchored to a point.
///
/// The anchor is a zero-sized box placed where the click landed, not the
/// host around it. That is deliberate: [MenuAnchor] wraps its anchor in a
/// `TapRegion` keyed to the menu, and a tap inside that region is not an
/// outside tap. Anchoring to the whole host would make every click anywhere
/// on it count as "inside", and the menu could then only be dismissed with
/// Escape. The same lesson, and the same shape, as `fl_nodes_v2`'s
/// `NodeEditorMenuHost`.
///
/// Everything else — keyboard traversal, the app's `MenuTheme` — comes from
/// the Material widgets. Submenus are Material's [SubmenuButton]; the menus
/// here are two levels deep at most, so the placement trouble the node
/// editor solved for a three-level cascade does not arise.
class PanelMenuHost extends StatefulWidget {
  const PanelMenuHost({super.key, required this.controller});

  final MenuController controller;

  @override
  State<PanelMenuHost> createState() => PanelMenuHostState();
}

class PanelMenuHostState extends State<PanelMenuHost> {
  /// Focused while the menu is open: a menu anchored to a point has no
  /// button to focus, and the anchor's keyboard shortcuts only reach whatever
  /// is focused *inside* it — so without this the arrow keys never walk the
  /// menu.
  final FocusNode _anchorFocus = FocusNode(debugLabel: 'fl_panel.menu');

  List<PanelMenuEntry> _entries = const <PanelMenuEntry>[];
  Offset _at = Offset.zero;

  @override
  void dispose() {
    _anchorFocus.dispose();
    super.dispose();
  }

  /// Opens [entries] at [position], in the coordinate space of the stack
  /// this host is a child of. Nothing to show opens nothing.
  bool open(List<PanelMenuEntry> entries, Offset position) {
    if (entries.isEmpty) return false;
    setState(() {
      _entries = entries;
      _at = position;
    });
    _anchorFocus.requestFocus();
    widget.controller.open();
    return true;
  }

  void close() => widget.controller.close();

  @override
  Widget build(BuildContext context) => Positioned(
    left: _at.dx,
    top: _at.dy,
    child: MenuAnchor(
      controller: widget.controller,
      childFocusNode: _anchorFocus,
      // The click that dismisses is spent dismissing: it must not also land
      // on a chip and activate it.
      consumeOutsideTap: true,
      menuChildren: buildPanelMenuChildren(_entries, autofocusFirst: true),
      child: Focus(focusNode: _anchorFocus, child: const SizedBox.shrink()),
    ),
  );
}

/// Turns entries into Material menu widgets, recursively.
///
/// [autofocusFirst] focuses the first entry that can actually be chosen,
/// which is what puts the menu under the arrow keys. Only the top level does
/// it: a submenu opening on hover must not pull focus off the item the
/// pointer is on.
@visibleForTesting
List<Widget> buildPanelMenuChildren(
  List<PanelMenuEntry> entries, {
  bool autofocusFirst = false,
}) {
  final first = autofocusFirst
      ? entries.firstWhere(
          (entry) => !entry.isSeparator && !entry.isSubmenu && entry.isEnabled,
          orElse: () => const PanelMenuEntry.separator(),
        )
      : null;

  return <Widget>[
    for (final entry in entries)
      if (entry.isSeparator)
        const Divider(height: 8)
      else if (entry.isSubmenu)
        SubmenuButton(
          leadingIcon: entry.icon == null ? null : Icon(entry.icon, size: 18),
          menuChildren: buildPanelMenuChildren(entry.children),
          child: Text(entry.label),
        )
      else
        MenuItemButton(
          autofocus: identical(entry, first),
          leadingIcon: entry.icon == null ? null : Icon(entry.icon, size: 18),
          shortcut: entry.shortcut,
          onPressed: entry.onSelected,
          child: Text(entry.label),
        ),
  ];
}
