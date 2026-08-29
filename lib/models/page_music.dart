/// Stable, durable music identity attached to a journal page.
///
/// This value deliberately has no stream URL. Providers can rotate signed
/// playback URLs, so only this identity and its attribution are part of the
/// frozen document contract.
class MusicReference {
  const MusicReference({
    required this.provider,
    required this.trackId,
    required this.title,
    required this.artist,
    required this.trackPageUrl,
    required this.licenseUrl,
    this.artworkUrl = '',
    this.duration = Duration.zero,
    this.legacyAssetId,
  });

  final String provider;
  final String trackId;
  final String title;
  final String artist;
  final String trackPageUrl;
  final String licenseUrl;
  final String artworkUrl;
  final Duration duration;
  final String? legacyAssetId;

  bool get isLegacy => legacyAssetId != null;
}

/// Runtime catalog result for a durable [MusicReference]. The stream URL is
/// intentionally kept at this edge and is never emitted by the canonical
/// document codec.
class PageMusicTrack extends MusicReference {
  const PageMusicTrack({
    required super.provider,
    required super.trackId,
    required super.title,
    required super.artist,
    required this.streamUrl,
    required super.trackPageUrl,
    required super.licenseUrl,
    super.artworkUrl = '',
    super.duration = Duration.zero,
    super.legacyAssetId,
  });

  const PageMusicTrack.legacy(String assetId)
      : streamUrl = '',
        super(
          provider: 'legacyAsset',
          trackId: assetId,
          title: 'Legacy page music',
          artist: '',
          artworkUrl: '',
          trackPageUrl: '',
          licenseUrl: '',
          duration: Duration.zero,
          legacyAssetId: assetId,
        );

  final String streamUrl;

  bool get isPlayable => provider == 'jamendo' && streamUrl.isNotEmpty;

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
    duration: json['durationMs'] is num
        ? Duration(milliseconds: (json['durationMs'] as num).toInt())
        : Duration(
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
