import '../../../../models/document.dart';
import '../../../../services/repositories.dart';

/// Coordinates checkpoint listing, creation, and restoration with the
/// document repository. Dialogs and error presentation stay in the view.
class CheckpointRecoveryUseCase {
  const CheckpointRecoveryUseCase({
    required this.checkpoints,
    required this.documents,
  });

  final CheckpointRepository checkpoints;
  final DocumentRepository documents;

  List<CheckpointInfo> forDocument(String documentId) =>
      checkpoints.checkpointsFor(documentId);

  Future<void> create(String documentId) =>
      checkpoints.createCheckpoint(documentId);

  Future<EntryDocument?> restore({
    required String checkpointId,
    required String documentId,
  }) async {
    await checkpoints.restoreCheckpoint(checkpointId);
    for (final document in documents.documents) {
      if (document.id == documentId) return document;
    }
    return null;
  }
}
