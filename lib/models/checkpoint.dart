/// Immutable checkpoint metadata exposed to feature workflows.
///
/// The full mutable storage snapshot remains private to the Hive data source;
/// features only need identity and timestamp to render recovery actions.
class CheckpointInfo {
  const CheckpointInfo({
    required this.id,
    required this.documentId,
    required this.createdAt,
  });

  final String id;
  final String documentId;
  final DateTime createdAt;
}
