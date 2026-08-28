import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../models/page_music.dart';
import '../../../../widgets/paper_page.dart';
import '../view_models/entry_editor_view_model.dart';
import '../../music/view_models/page_music_controller.dart';
import '../../music/views/music_picker_sheet.dart';

/// Feature-native presentation for a page's music chip and dialogs.
class EditorMusicView extends StatelessWidget {
  const EditorMusicView({
    super.key,
    required this.documentId,
    required this.documentTrack,
    required this.controller,
    required this.active,
  });

  final String documentId;
  final PageMusicTrack? documentTrack;
  final PageMusicController controller;
  final bool active;

  /// Opens the music catalog picker without exposing its sheet implementation
  /// to the page host.
  static Future<MusicPickerResult?> showPicker(
    BuildContext context, {
    required EntryEditorViewModel editor,
    PageMusicTrack? current,
  }) => showModalBottomSheet<MusicPickerResult>(
    context: context,
    backgroundColor: PaperPage.paper,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (context) => MusicPickerSheet(
      viewModel: editor.createMusicPickerViewModel(current: current),
    ),
  );

  /// Presents license and source details for a selected track.
  static Future<void> showDetails(
    BuildContext context,
    PageMusicTrack track,
  ) async {
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(track.title),
        content: Text(
          track.isLegacy
              ? 'This page contains a legacy local music reference. Replace or remove it from More tools.'
              : '${track.artist}\n\nStreamed from Jamendo under the linked Creative Commons license.',
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

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      final track = controller.pageId == documentId
          ? controller.track ?? documentTrack
          : documentTrack;
      if (track == null) return const SizedBox.shrink();
      final loading = active && controller.isLoading;
      final playing = active && controller.isPlaying;
      final failed = active && controller.error != null;
      return Material(
        color: PaperPage.paper,
        elevation: 2,
        borderRadius: BorderRadius.circular(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 280),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                key: const ValueKey('page-music-play-pause'),
                tooltip: failed
                    ? 'Retry page music'
                    : playing
                    ? 'Pause page music'
                    : 'Play page music',
                onPressed: !active || loading
                    ? null
                    : () async {
                        await controller.toggle();
                        if (!context.mounted || controller.error == null) {
                          return;
                        }
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text(controller.error!)),
                        );
                      },
                icon: loading
                    ? const SizedBox.square(
                        dimension: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(
                        failed
                            ? Icons.refresh
                            : playing
                            ? Icons.pause
                            : Icons.play_arrow,
                      ),
              ),
              Flexible(
                child: Text(
                  track.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
              IconButton(
                tooltip: 'Page music details',
                onPressed: () => showDetails(context, track),
                icon: const Icon(Icons.info_outline, size: 20),
              ),
            ],
          ),
        ),
      );
    },
  );
}
