## 0.1.0

The first cut: the tree, the solver, the controller, the host.

- `PanelApp` → `PanelWindow` → `LayoutNode` → `PanelTab`: an immutable tree
  of splits, single panels and tab groups, edited by the pure functions in
  `LayoutTree`, which normalises after every edit so no caller sees a split
  of one, an empty group or a same-axis nesting. Splits are n-ary and flatten
  same-axis children rather than binary, so `((A|B)|C)` and `(A|(B|C))` — which
  draw the same and resize differently — are one tree. A tab holds a
  `contentId` and metadata, never a widget, so the tree serialises and moves
  between windows without asking anybody. `test/model_test.dart`.
- `PanelSolver`: `PanelExtent.flex(weight)` children share what
  `PanelExtent.fixed(pixels)` ones leave; `PanelTab.minWidth`/`minHeight` are
  the only hard constraint, held by taking from siblings with slack, scaled
  together when even they do not fit. `resize` trades pixels between two
  neighbours and nobody else moves. `test/layout_test.dart`.
- `DockResolver`: five zones over a leaf (centre joins, edges split), a band
  along the window's edges splits the root, a strip hit inserts at the index.
  Every candidate is checked by running the edit, so a drop the policy refuses
  is never offered. `DockPolicy` carries the two affinity levels:
  `canTakeForm` from `PanelTab.forms`, `canJoin`/`canSplit` for the host's
  metadata rules. Default permissive. *affinity* in `test/model_test.dart`.
- `PanelController`: a `ChangeNotifier` over the app; `dock`, `open`, `close`,
  `activate`, `resize`, `moveToWindow`; the drag session (`beginDrag`,
  `updateDrag`, `commitDrag`); `toJson`/`load` with an integer `version`
  (`PanelApp.version`, 1) refused when newer and a `TabResolver` that drops
  what this build cannot show. `onSettled` fires once per gesture, never per
  frame.
- `PanelHost`: one window as one flat `Stack`, a keyed `Positioned` per tab,
  chrome above, preview on top — content is never reparented, so its state
  survives a move. Strips and headers drag; dividers resize with
  `DragStartBehavior.down` so they track the pointer from the first pixel.
  `test/panel_host_test.dart`.
- `PanelChrome`: the contract for everything drawn that is not content, with
  `StripScope.tabSlot`/`stripSlot` as the one rule custom chrome keeps to stay
  a drop target. `DefaultPanelChrome` draws three `PanelTabStyle`s —
  `attached`, `blended` (a `BlendedChipPainter` with Chrome's shoulders, the
  bottom left open so the active tab and its content are one surface),
  `floating` — from a `PanelTabStyleSpec` per style, per theme or per group
  through `PanelHost.tabStyleOf`. `PanelDecorations` hangs an icon, an unsaved
  dot, a strip button and a context menu on the default chrome. *styles*,
  *decorations* and *custom chrome* in `test/chrome_test.dart`.
- Chips share a strip between `PanelTheme.tabMinWidth` (96) and
  `tabMaxWidth` (200) and the strip scrolls once they would shrink below the
  floor — by wheel, never by pointer drag, which already means "move". *shrink
  then scroll* in `test/chrome_test.dart`.
- `PanelWindow.focusedLeafId`, persisted: where `open` puts content (falling
  back to the first leaf that accepts, then the right edge) and what
  `nextTab`/`previousTab`/`closeActive` act on; the focused group's strip
  shows the full accent. `PanelController.focus(tabId, keyboard:)` activates,
  reveals the chip in a scrolled strip and, with `keyboard`, hands the content
  the focus. `test/controller_test.dart` *focus*, `test/chrome_test.dart`
  *focus reveals a clipped chip*.
- `PanelController.events`, synchronous: `TabOpened`, `TabClosed`, `TabMoved`
  from one placement diff per commit, plus `TabActivated`, `LeafFocused`,
  `TabUpdated`, `LayoutReplaced`. `closeGuard` asked before any close, from
  the × or a verb; `closeOthers`, `closeToTheRight`, `closeLeaf` ask per tab.
  `updateTab` for a title or a flag. `test/controller_test.dart`.
- `package:fl_panel/model.dart` exports the Flutter-free half;
  `test/flutter_free_test.dart` keeps it so.
- `example/`: an IDE-shaped demo with a metadata policy and save/restore.
