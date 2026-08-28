import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../models/page_music.dart';
import '../view_models/music_picker_view_model.dart';

class MusicPickerResult {
  const MusicPickerResult.select(this.track) : remove = false;
  const MusicPickerResult.remove() : track = null, remove = true;

  final PageMusicTrack? track;
  final bool remove;
}

class MusicPickerSheet extends StatefulWidget {
  const MusicPickerSheet({
    super.key,
    required this.viewModel,
  });

  final MusicPickerViewModel viewModel;

  @override
  State<MusicPickerSheet> createState() => _MusicPickerSheetState();
}

class _MusicPickerSheetState extends State<MusicPickerSheet> {
  late final TextEditingController _searchController =
      TextEditingController();

  @override
  void initState() {
    super.initState();
    unawaited(widget.viewModel.load());
    widget.viewModel.addListener(_handleModelChanged);
  }

  void _handleModelChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.viewModel.removeListener(_handleModelChanged);
    _searchController.dispose();
    widget.viewModel.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final model = widget.viewModel;
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
                onChanged: model.setQuery,
                textInputAction: TextInputAction.search,
                onSubmitted: (_) => model.search(),
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  hintText: 'Search instrumental music',
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            if (model.current != null)
              ListTile(
                leading: const Icon(Icons.music_off_outlined),
                title: const Text('Remove music from this page'),
                onTap: () =>
                    Navigator.pop(context, const MusicPickerResult.remove()),
              ),
            const Divider(height: 1),
            Expanded(child: _buildResults(model)),
          ],
        ),
      ),
    );
  }

  Widget _buildResults(MusicPickerViewModel model) {
    if (model.loading) return const Center(child: CircularProgressIndicator());
    if (model.error != null && model.tracks.isEmpty) {
      return _MessageState(
        icon: Icons.cloud_off_outlined,
        message: model.error!,
        actionLabel: model.isConfigured ? 'Retry' : null,
        onAction: model.isConfigured
            ? () => model.search()
            : null,
      );
    }
    if (model.tracks.isEmpty) {
      return const _MessageState(
        icon: Icons.search_off_outlined,
        message: 'No instrumental tracks found.',
      );
    }
    return ListView.builder(
      itemCount: model.tracks.length + 1,
      itemBuilder: (context, index) {
        if (index == model.tracks.length) {
          return Padding(
            padding: const EdgeInsets.all(16),
            child: Center(
              child: model.loadingMore
                  ? const CircularProgressIndicator()
                  : OutlinedButton(
                      onPressed: () => model.search(append: true),
                      child: const Text('Load more'),
                    ),
            ),
          );
        }
        final track = model.tracks[index];
        final playing = model.isPlaying(track);
        final loading = model.isLoading(track);
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
                    : () => model.togglePreview(track),
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
