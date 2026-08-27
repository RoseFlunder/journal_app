import 'package:flutter/material.dart';

import '../../../../models/template.dart';

/// Saved-template picker. It renders immutable template documents and emits a
/// single insertion intent for the editor view model.
class EditorTemplatesView extends StatelessWidget {
  const EditorTemplatesView({
    super.key,
    required this.templates,
    required this.onInsert,
  });

  final List<JournalTemplate> templates;
  final ValueChanged<JournalTemplate> onInsert;

  @override
  Widget build(BuildContext context) => SafeArea(
    child: SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.68,
      child: templates.isEmpty
          ? const Center(child: Text('No saved templates yet'))
          : ListView.builder(
              itemCount: templates.length,
              itemBuilder: (context, index) {
                final template = templates[index];
                return ListTile(
                  leading: const Icon(Icons.dashboard_customize_outlined),
                  title: Text(template.name),
                  subtitle: Text(
                    '${template.document.nodes.length} top-level objects',
                  ),
                  onTap: () {
                    Navigator.pop(context);
                    onInsert(template);
                  },
                );
              },
            ),
    ),
  );
}
