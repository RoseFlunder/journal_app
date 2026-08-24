import 'document.dart';

/// A reusable local board snapshot. Assets remain immutable and are referenced
/// by id, so inserting a template never rewrites its source media.
class JournalTemplate {
  JournalTemplate({
    required this.id,
    required this.name,
    required this.document,
    required this.createdAt,
    this.previewAssetId,
  });

  final String id;
  final String name;
  final EntryDocument document;
  final DateTime createdAt;
  final String? previewAssetId;

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'document': document.toJson(),
    'createdAt': createdAt.toIso8601String(),
    'previewAssetId': previewAssetId,
  };

  factory JournalTemplate.fromJson(Map<String, dynamic> json) =>
      JournalTemplate(
        id: json['id'] as String,
        name: json['name'] as String? ?? 'Template',
        document: EntryDocument.fromJson(
          Map<String, dynamic>.from(json['document'] as Map),
        ),
        createdAt: DateTime.parse(json['createdAt'] as String),
        previewAssetId: json['previewAssetId'] as String?,
      );
}
