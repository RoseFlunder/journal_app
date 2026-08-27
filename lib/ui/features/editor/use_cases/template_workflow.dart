import 'dart:ui';

import 'package:uuid/uuid.dart';

import '../../../../editor/editor_controller.dart';
import '../../../../models/document.dart';
import '../../../../models/template.dart';
import '../../../../services/repositories.dart';

/// Owns template persistence and insertion orchestration for the editor.
class TemplateWorkflow {
  TemplateWorkflow({required this.templates});

  static const _uuid = Uuid();
  final TemplateRepository templates;

  List<JournalTemplate> get available => templates.templates;

  Future<void> saveSelection({
    required String name,
    required EntryDocument source,
    required Iterable<CanvasNode> nodes,
    required DateTime createdAt,
  }) =>
      templates.saveTemplate(
        JournalTemplate(
          id: _uuid.v4(),
          name: name,
          document: EntryDocument(
            id: _uuid.v4(),
            title: source.title,
            createdAt: createdAt,
            modifiedAt: createdAt,
            nodes: nodes,
            board: source.board,
          ),
          createdAt: createdAt,
        ),
      );

  void insert(TemplateInsertion insertion, EditorController editor) {
    editor.insertNodeGraph(
      insertion.nodes,
      offset: insertion.offset,
      label: 'Insert template',
    );
  }
}

class TemplateInsertion {
  const TemplateInsertion({required this.nodes, required this.offset});

  final List<CanvasNode> nodes;
  final Offset offset;
}
