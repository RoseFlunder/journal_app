import '../models/page_music.dart';

/// Search and resolution capability for externally hosted page music.
abstract interface class MusicCatalogRepository {
  bool get isConfigured;

  Future<List<PageMusicTrack>> searchTracks({
    String query = '',
    int offset = 0,
    int limit = 20,
  });

  Future<PageMusicTrack> resolveTrack(String trackId);
}

/// Explicit no-op catalog used by tests and builds without a catalog key.
class DisabledMusicCatalogRepository implements MusicCatalogRepository {
  const DisabledMusicCatalogRepository();

  @override
  bool get isConfigured => false;

  @override
  Future<PageMusicTrack> resolveTrack(String trackId) =>
      Future.error(StateError('The music catalog is not configured.'));

  @override
  Future<List<PageMusicTrack>> searchTracks({
    String query = '',
    int offset = 0,
    int limit = 20,
  }) => Future.error(StateError('The music catalog is not configured.'));
}
