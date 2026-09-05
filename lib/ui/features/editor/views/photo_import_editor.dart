import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:pro_image_editor/pro_image_editor.dart';

import '../../../../services/photo_frame.dart';

/// Keeps all appearance changes local until the user adds the finished photo.
class PhotoImportEditor extends StatefulWidget {
  const PhotoImportEditor({super.key, required this.bytes});

  final Uint8List bytes;

  @override
  State<PhotoImportEditor> createState() => _PhotoImportEditorState();
}

class _PhotoImportEditorState extends State<PhotoImportEditor> {
  late Uint8List _photo = widget.bytes;
  late Uint8List _preview = widget.bytes;
  PhotoFrame _frame = PhotoFrame.none;
  bool _busy = false;
  String? _error;

  Future<void> _updatePreview(Uint8List photo, PhotoFrame frame) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final bytes = await compute(applyPhotoFrame, (photo, frame));
      if (!mounted) return;
      setState(() {
        _photo = photo;
        _frame = frame;
        _preview = bytes;
      });
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'Could not update the photo. Please try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _filters() async {
    // The package owns filter selection, intensity, live preview and export.
    Uint8List? filtered;
    final result = await Navigator.of(context).push<Uint8List>(
      MaterialPageRoute(
        builder: (context) => FilterEditor.memory(
          _photo,
          initConfigs: FilterEditorInitConfigs(
            theme: Theme.of(context),
            convertToUint8List: true,
            callbacks: ProImageEditorCallbacks(
              onImageEditingComplete: (bytes) async => filtered = bytes,
              onCloseEditor: (_) => Navigator.pop(context, filtered),
            ),
          ),
        ),
      ),
    );
    if (!mounted || result == null) return;
    await _updatePreview(result, _frame);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Prepare photo'),
      actions: [
        TextButton(
          key: const ValueKey('photo-add-to-page'),
          onPressed: _busy ? null : () => Navigator.pop(context, _preview),
          child: const Text('Add to page'),
        ),
      ],
    ),
    body: SafeArea(
      child: Column(
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Center(
                    child: Image.memory(
                      _preview,
                      key: const ValueKey('photo-preview'),
                      fit: BoxFit.contain,
                    ),
                  ),
                  if (_busy) const Center(child: CircularProgressIndicator()),
                ],
              ),
            ),
          ),
          if (_error != null)
            Padding(padding: const EdgeInsets.all(8), child: Text(_error!)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                FilledButton.tonalIcon(
                  key: const ValueKey('photo-filters'),
                  onPressed: _busy ? null : _filters,
                  icon: const Icon(Icons.filter_vintage_outlined),
                  label: const Text('Filters'),
                ),
                const SizedBox(width: 12),
                TextButton(
                  onPressed: _busy
                      ? null
                      : () => _updatePreview(widget.bytes, PhotoFrame.none),
                  child: const Text('Reset'),
                ),
              ],
            ),
          ),
          const Padding(
            padding: EdgeInsets.only(top: 12),
            child: Text('Frame'),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
              child: Row(
                children: PhotoFrame.values
                    .map(
                      (frame) => Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: ChoiceChip(
                          key: ValueKey('photo-frame-${frame.name}'),
                          label: Text(switch (frame) {
                            PhotoFrame.none => 'None',
                            PhotoFrame.white => 'White',
                            PhotoFrame.cream => 'Cream',
                            PhotoFrame.black => 'Black',
                          }),
                          selected: _frame == frame,
                          onSelected: _busy
                              ? null
                              : (_) => _updatePreview(_photo, frame),
                        ),
                      ),
                    )
                    .toList(),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}
