import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../models/page_music.dart';
import '../../../../services/audio_playback.dart';
import '../../../../services/repositories.dart';

class MusicPickerResult {
  const MusicPickerResult.select(this.track) : remove = false;
  const MusicPickerResult.remove() : track = null, remove = true;

  final PageMusicTrack? track;
  final bool remove;
}

class MusicPickerSheet extends StatefulWidget {
  const MusicPickerSheet({
    super.key,
    required this.catalog,
    required this.audioPlaybackFactory,
    this.current,
  });

  final MusicCatalogRepository catalog;
  final AudioPlaybackFactory audioPlaybackFactory;
  final PageMusicTrack? current;

  @override
  State<MusicPickerSheet> createState() => _MusicPickerSheetState();
}

class _MusicPickerSheetState extends State<MusicPickerSheet> {
  static const _pageSize = 20;
  late final TextEditingController _searchController = TextEditingController();
  late final AudioPlaybackService _preview = widget.audioPlaybackFactory();
  StreamSubscription<AudioPlaybackSnapshot>? _previewSubscription;
  Timer? _debounce;
  List<PageMusicTrack> _tracks = const [];
  bool _loading = true;
  bool _loadingMore = false;
  String? _error;
  String? _previewTrackId;
  AudioPlaybackStatus _previewStatus = AudioPlaybackStatus.idle;
  int _requestGeneration = 0;

  @override
  void initState() {
    super.initState();
    _previewSubscription = _preview.states.listen((snapshot) {
      if (!mounted) return;
      setState(() => _previewStatus = snapshot.status);
    });
    unawaited(_preview.setLoopOne().catchError((_) {}));
    unawaited(_search());
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    unawaited(_previewSubscription?.cancel());
    unawaited(_preview.dispose());
    super.dispose();
  }

  void _onQueryChanged(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () {
      unawaited(_search());
    });
  }

  Future<void> _search({bool append = false}) async {
    final generation = ++_requestGeneration;
    if (!widget.catalog.isConfigured) {
      setState(() {
        _loading = false;
        _error = 'Set JAMENDO_CLIENT_ID to enable the music catalog.';
      });
      return;
    }
    setState(() {
      if (append) {
        _loadingMore = true;
      } else {
        _loading = true;
        _error = null;
      }
    });
    try {
      final tracks = await widget.catalog.searchTracks(
        query: _searchController.text,
        offset: append ? _tracks.length : 0,
        limit: _pageSize,
      );
      if (!mounted || generation != _requestGeneration) return;
      setState(() {
        _tracks = append ? [..._tracks, ...tracks] : tracks;
        _loading = false;
        _loadingMore = false;
      });
    } catch (error) {
      if (!mounted || generation != _requestGeneration) return;
      setState(() {
        _loading = false;
        _loadingMore = false;
        _error = error.toString();
      });
    }
  }

  Future<void> _togglePreview(PageMusicTrack track) async {
    if (_previewTrackId == track.trackId &&
        _previewStatus == AudioPlaybackStatus.playing) {
      await _preview.pause();
      return;
    }
    try {
      if (_previewTrackId != track.trackId) {
        await _preview.stopAndReset();
        if (!mounted) return;
        setState(() {
          _previewTrackId = track.trackId;
          _previewStatus = AudioPlaybackStatus.loading;
        });
        await _preview.load(track.streamUrl);
      }
      await _preview.play();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _previewStatus = AudioPlaybackStatus.error;
        _error = 'Could not preview ${track.title}: $error';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.82,
        child: Column(
          children: [
            ListTile(
              leading: const Icon(Icons.library_music_outlined),
              title: const Text('Choose page music'),
              subtitle: const Text('Creative Commons music from Jamendo'),
              trailing: IconButton(
                tooltip: 'Close music picker',
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: TextField(
                key: const ValueKey('music-search-field'),
                controller: _searchController,
                onChanged: _onQueryChanged,
                textInputAction: TextInputAction.search,
                onSubmitted: (_) => unawaited(_search()),
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  hintText: 'Search instrumental music',
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            if (widget.current != null)
              ListTile(
                leading: const Icon(Icons.music_off_outlined),
                title: const Text('Remove music from this page'),
                onTap: () =>
                    Navigator.pop(context, const MusicPickerResult.remove()),
              ),
            const Divider(height: 1),
            Expanded(child: _buildResults()),
          ],
        ),
      ),
    );
  }

  Widget _buildResults() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null && _tracks.isEmpty) {
      return _MessageState(
        icon: Icons.cloud_off_outlined,
        message: _error!,
        actionLabel: widget.catalog.isConfigured ? 'Retry' : null,
        onAction: widget.catalog.isConfigured
            ? () => unawaited(_search())
            : null,
      );
    }
    if (_tracks.isEmpty) {
      return const _MessageState(
        icon: Icons.search_off_outlined,
        message: 'No instrumental tracks found.',
      );
    }
    return ListView.builder(
      itemCount: _tracks.length + 1,
      itemBuilder: (context, index) {
        if (index == _tracks.length) {
          return Padding(
            padding: const EdgeInsets.all(16),
            child: Center(
              child: _loadingMore
                  ? const CircularProgressIndicator()
                  : OutlinedButton(
                      onPressed: () => unawaited(_search(append: true)),
                      child: const Text('Load more'),
                    ),
            ),
          );
        }
        final track = _tracks[index];
        final previewing = _previewTrackId == track.trackId;
        final playing =
            previewing && _previewStatus == AudioPlaybackStatus.playing;
        final loading =
            previewing && _previewStatus == AudioPlaybackStatus.loading;
        return ListTile(
          key: ValueKey('music-track-${track.trackId}'),
          leading: _Artwork(url: track.artworkUrl),
          title: Text(
            track.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Text(
            '${track.artist} • ${_durationLabel(track.duration)}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                tooltip: playing ? 'Pause preview' : 'Preview ${track.title}',
                onPressed: loading
                    ? null
                    : () => unawaited(_togglePreview(track)),
                icon: loading
                    ? const SizedBox.square(
                        dimension: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(playing ? Icons.pause : Icons.play_arrow),
              ),
              FilledButton.tonal(
                onPressed: () =>
                    Navigator.pop(context, MusicPickerResult.select(track)),
                child: const Text('Use'),
              ),
            ],
          ),
          onTap: () => unawaited(_showTrackDetails(context, track)),
        );
      },
    );
  }
}

class _Artwork extends StatelessWidget {
  const _Artwork({required this.url});
  final String url;

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(6),
    child: url.isEmpty
        ? const SizedBox.square(
            dimension: 48,
            child: ColoredBox(
              color: Color(0xFFE8E1D2),
              child: Icon(Icons.music_note),
            ),
          )
        : Image.network(
            url,
            width: 48,
            height: 48,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => const SizedBox.square(
              dimension: 48,
              child: Icon(Icons.music_note),
            ),
          ),
  );
}

class _MessageState extends StatelessWidget {
  const _MessageState({
    required this.icon,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 40),
          const SizedBox(height: 12),
          Text(message, textAlign: TextAlign.center),
          if (actionLabel != null) ...[
            const SizedBox(height: 12),
            FilledButton(onPressed: onAction, child: Text(actionLabel!)),
          ],
        ],
      ),
    ),
  );
}

String _durationLabel(Duration duration) {
  final minutes = duration.inMinutes;
  final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
  return '$minutes:$seconds';
}

Future<void> _showTrackDetails(
  BuildContext context,
  PageMusicTrack track,
) async {
  await showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(track.title),
      content: Text(
        '${track.artist}\n\nMusic is streamed from Jamendo under the linked Creative Commons license.',
      ),
      actions: [
        if (track.licenseUrl.isNotEmpty)
          TextButton(
            onPressed: () => launchUrl(Uri.parse(track.licenseUrl)),
            child: const Text('License'),
          ),
        if (track.trackPageUrl.isNotEmpty)
          TextButton(
            onPressed: () => launchUrl(Uri.parse(track.trackPageUrl)),
            child: const Text('Open on Jamendo'),
          ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    ),
  );
}
