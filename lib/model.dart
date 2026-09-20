/// The Flutter-free half of fl_panel: the layout tree, its edits, the solver,
/// the drop resolver, the policy and the file format.
///
/// Nothing reachable from this import touches `package:flutter`, so a tree
/// can be built, edited, solved and serialised headless — in a plain `dart`
/// test, on a server, in a tool. `test/flutter_free_test.dart` keeps it so.
library;

export 'src/layout/dock_resolver.dart';
export 'src/layout/solver.dart';
export 'src/model/dock.dart';
export 'src/model/edits.dart';
export 'src/model/geometry.dart';
export 'src/model/json.dart';
export 'src/model/node.dart';
export 'src/model/tab.dart';
export 'src/model/window.dart';
export 'src/policy/dock_policy.dart';
