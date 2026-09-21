# Changelog

What a host can do with each version, newest first. The reasoning behind a
change lives beside the code in `CLAUDE.md`; this file only says what changed.

## 0.1.0

First release: a docking layout for Flutter — a tree of splits, single panels
and tab groups the user resizes, docks and rearranges, with ordinary widgets
inside every panel, and a file format to bring it back.

### The tree

- `PanelApp` → `PanelWindow` → `LayoutNode` (`SplitNode`, `SinglePanel`,
  `TabGroup`) → `PanelTab`: immutable values, edited by the pure functions in
  `LayoutTree`, which normalises after every edit — no split of one, no empty
  group, no same-axis nesting. Splits are n-ary. A tab holds a `contentId`
  and a `metadata` map, never a widget.
- `PanelExtent.flex(weight)` children share what `PanelExtent.fixed(pixels)`
  ones leave; `PanelTab.minWidth` / `minHeight` are the only hard constraint,
  and an over-constrained layout scales together rather than dropping a child
  to zero.
- `TabGroup.persistent` (false): a group that stays in the tree when its last
  tab closes — an editor area. Window-wide, only the last empty one stands;
  a tab dragged out of one makes another. `PanelHost.emptyLeafBuilder` draws
  what goes where its content would.
- `PanelTab.closable` (true): off for content an application always shows.
  No close glyph, `close` refuses without asking the guard, the group verbs
  skip it; it still moves.
- `PanelTab.forms` says which surface a content may take — a single panel, a
  tab, or either — and `PanelTab.keepAlive` (true) whether an inactive tab
  stays built.
- `package:fl_panel/model.dart` exports the Flutter-free half: the tree, the
  edits, the solver, the resolver, the policy and the format.

### Docking

- Drag a tab out of its strip or a whole panel by its header. Over a leaf,
  the centre joins it and the edges split it; a band along the window's
  edges splits the root; a strip inserts at the index. A live preview shows
  the drop before it lands, and a drop the policy refuses is never offered.
- `DockPolicy`: `canTakeForm` from `PanelTab.forms`, `canJoin` and `canSplit`
  handed both sides of a proposed move with their metadata, and
  `takesFocus(leaf)` (true) for which leaves may be where the next document
  opens. Permissive by default.
- `PanelController.canDock(windowId, source, target)` is the dry run a menu
  greys by.

### The controller

- `PanelController`, a `ChangeNotifier` over the app: `dock`, `open`,
  `close`, `activate`, `resize`, `moveToWindow`, `equalise`, `swap`, and the
  drag session — `beginDrag`, `updateDrag`, `commitDrag`. `onSettled` fires
  once per gesture, never per frame.
- `PanelWindow.focusedLeafId`, persisted: where `open` puts content, what
  `nextTab` / `previousTab` / `closeActive` act on, whose strip shows the full
  accent. `focus(tabId, keyboard:)` activates, reveals the chip in a scrolled
  strip and, with `keyboard`, hands the content the focus.
- `closeGuard` (`CloseGuard?`, null) is asked before any close, from the ×
  or a verb; `closeOthers`, `closeToTheRight` and `closeLeaf` ask per tab.
  `updateTab` for a title or a flag.
- `events`, synchronous: `TabOpened`, `TabClosed`, `TabMoved` — one placement
  diff per commit — plus `TabActivated`, `LeafFocused`, `TabUpdated`,
  `LayoutReplaced`.
- `toJson()` and `load(json, resolve:)` with an integer `version`
  (`PanelApp.version`, 1), refused when newer; the `TabResolver` drops what
  this build cannot show and the tree tidies itself.

### The host and the chrome

- `PanelHost` renders one window as one flat `Stack` with a keyed child per
  tab, so content is never reparented and its state survives a move. Strips
  and headers drag; dividers resize from the first pixel.
- Three `PanelTabStyle`s — `attached`, `blended`, `floating` — from
  `DefaultPanelChrome`, per theme (`PanelTheme.tabStyle`) or per group
  (`PanelHost.tabStyleOf`); geometry per style in `PanelTabStyleSpec`.
- Chips share a strip between `PanelTheme.tabMinWidth` (96) and
  `tabMaxWidth` (200), then the strip scrolls — by wheel and by `focus`,
  never by pointer drag.
- `PanelDecorations` hangs an icon (`tabLeading`), an unsaved dot
  (`tabTrailing`, replacing the close glyph), a wrapper round the whole chip
  (`wrapTab`), a strip button, a header button and `onTabSecondaryTap` on
  the default chrome; `PanelChrome` replaces it entirely, keeping
  `StripScope.tabSlot` / `stripSlot` so chips stay drop targets.
- `PanelHost.contextMenus` (`const PanelMenus()`; null for none): a Material
  menu on a right click on a chip, a strip, a header or a divider, built as
  `PanelMenuEntry` data by `PanelMenus.defaultEntries` — close verbs and a
  Split submenu, Close all, Move to edge, Equalise, Swap — greyed where they
  do not apply, and rewritten through `PanelMenus.build`.
- `example/`: an IDE-shaped demo — files at a fixed width, editors in the
  middle, tools that only group with tools, a console along the bottom — with
  a style switcher, a close guard, a context menu and save/restore. Live at
  https://williamkaroldicioccio.github.io/fl_panel/.
