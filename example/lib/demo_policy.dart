import 'package:fl_panel/fl_panel.dart';

/// The second affinity level, as a host would write it: tools share strips
/// with tools, editors with editors, and the file tree with nobody. The
/// first level — which forms a tab may take — is on the tabs themselves.
final class DemoPolicy extends DockPolicy {
  const DemoPolicy();

  @override
  bool canJoin(PanelTab moving, LeafNode target) {
    final kind = moving.metadata['kind'];
    if (kind == 'files') return false;
    return target.tabs.every((tab) => tab.metadata['kind'] == kind);
  }
}
