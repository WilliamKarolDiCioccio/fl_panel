import 'package:fl_panel/fl_panel.dart';
import 'package:flutter/material.dart';

/// The host's side of the contract: a `contentId` comes in, a widget goes
/// out. The widget is keyed on the tab by the host, so whatever state it
/// holds — the text typed here — survives every move.
Widget buildPane(
  BuildContext context,
  PanelTab tab, {
  required void Function(String tabId, bool dirty) onDirty,
}) => switch (tab.contentId) {
  'editor' => EditorPane(
    title: tab.metadata['title'] as String,
    onDirty: (dirty) => onDirty(tab.id, dirty),
  ),
  'files' => const FilesPane(),
  'tool' => ToolPane(title: tab.metadata['title'] as String),
  _ => Center(child: Text('unknown content ${tab.contentId}')),
};

class EditorPane extends StatefulWidget {
  const EditorPane({super.key, required this.title, required this.onDirty});
  final String title;
  final ValueChanged<bool> onDirty;

  @override
  State<EditorPane> createState() => _EditorPaneState();
}

class _EditorPaneState extends State<EditorPane> {
  late final String _initial =
      '# ${widget.title}\n\nType here, then drag this tab somewhere else.\n';
  late final TextEditingController _text = TextEditingController(
    text: _initial,
  );
  bool _dirty = false;

  @override
  void initState() {
    super.initState();
    _text.addListener(() {
      final dirty = _text.text != _initial;
      if (dirty != _dirty) {
        _dirty = dirty;
        widget.onDirty(dirty);
      }
    });
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Theme.of(context).colorScheme.surface,
      padding: const EdgeInsets.all(12),
      child: TextField(
        controller: _text,
        maxLines: null,
        expands: true,
        style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
        decoration: const InputDecoration.collapsed(hintText: ''),
      ),
    );
  }
}

class FilesPane extends StatelessWidget {
  const FilesPane({super.key});

  @override
  Widget build(BuildContext context) {
    const names = [
      'chapter-one.md',
      'chapter-two.md',
      'notes.txt',
      'assets/',
      'characters/',
    ];
    return Container(
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      child: ListView(
        children: [
          for (final name in names)
            ListTile(
              dense: true,
              leading: Icon(
                name.endsWith('/')
                    ? Icons.folder_outlined
                    : Icons.description_outlined,
                size: 18,
              ),
              title: Text(name),
            ),
        ],
      ),
    );
  }
}

class ToolPane extends StatefulWidget {
  const ToolPane({super.key, required this.title});
  final String title;

  @override
  State<ToolPane> createState() => _ToolPaneState();
}

class _ToolPaneState extends State<ToolPane> {
  int _count = 0;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Theme.of(context).colorScheme.surfaceContainer,
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(widget.title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Text('$_count', style: Theme.of(context).textTheme.headlineMedium),
          TextButton(
            onPressed: () => setState(() => _count++),
            child: const Text('count'),
          ),
        ],
      ),
    );
  }
}
