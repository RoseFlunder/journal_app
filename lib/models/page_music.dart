/// Immutable reference to music attached to a journal page.
///
/// Remote audio remains owned by its provider. The journal stores only the
/// metadata required to display attribution and request playback later.
class PageMusicTrack {
  const PageMusicTrack({
    required this.provider,
    required this.trackId,
    required this.title,
    required this.artist,
    required this.streamUrl,
    required this.trackPageUrl,
    required this.licenseUrl,
    this.artworkUrl = '',
    this.duration = Duration.zero,
    this.legacyAssetId,
  });

  const PageMusicTrack.legacy(String assetId)
    : provider = 'legacyAsset',
      trackId = assetId,
      title = 'Legacy page music',
      artist = '',
      artworkUrl = '',
      streamUrl = '',
      trackPageUrl = '',
      licenseUrl = '',
      duration = Duration.zero,
      legacyAssetId = assetId;

  final String provider;
  final String trackId;
  final String title;
  final String artist;
  final String artworkUrl;
  final String streamUrl;
  final String trackPageUrl;
  final String licenseUrl;
  final Duration duration;
  final String? legacyAssetId;

  bool get isPlayable => provider == 'jamendo' && streamUrl.isNotEmpty;
  bool get isLegacy => legacyAssetId != null;

  PageMusicTrack copyWith({String? streamUrl}) => PageMusicTrack(
    provider: provider,
    trackId: trackId,
    title: title,
    artist: artist,
    artworkUrl: artworkUrl,
    streamUrl: streamUrl ?? this.streamUrl,
    trackPageUrl: trackPageUrl,
    licenseUrl: licenseUrl,
    duration: duration,
    legacyAssetId: legacyAssetId,
  );

  Map<String, dynamic> toJson() => {
    'provider': provider,
    'trackId': trackId,
    'title': title,
    'artist': artist,
    'artworkUrl': artworkUrl,
    'streamUrl': streamUrl,
    'trackPageUrl': trackPageUrl,
    'licenseUrl': licenseUrl,
    'durationSeconds': duration.inSeconds,
    if (legacyAssetId != null) 'legacyAssetId': legacyAssetId,
  };

  factory PageMusicTrack.fromJson(Map<String, dynamic> json) => PageMusicTrack(
    provider: json['provider'] as String? ?? 'jamendo',
    trackId: json['trackId'] as String? ?? '',
    title: json['title'] as String? ?? 'Unknown track',
    artist: json['artist'] as String? ?? '',
    artworkUrl: json['artworkUrl'] as String? ?? '',
    streamUrl: json['streamUrl'] as String? ?? '',
    trackPageUrl: json['trackPageUrl'] as String? ?? '',
    licenseUrl: json['licenseUrl'] as String? ?? '',
    duration: Duration(
      seconds: (json['durationSeconds'] as num?)?.toInt() ?? 0,
    ),
    legacyAssetId: json['legacyAssetId'] as String?,
  );

  static PageMusicTrack? decode(Object? value) {
    if (value is String && value.isNotEmpty) {
      return PageMusicTrack.legacy(value);
    }
    if (value is Map) {
      return PageMusicTrack.fromJson(Map<String, dynamic>.from(value));
    }
    return null;
  }
}
