import 'package:flutter/material.dart';

import '../models/entry.dart';

class BlockWidget extends StatefulWidget {
  const BlockWidget({
    super.key,
    required this.block,
    required this.selected,
    required this.editing,
    required this.textEditing,
    required this.onTap,
    required this.onEditText,
    required this.onMove,
    required this.onResize,
    required this.onTextChanged,
  });

  final ContentBlock block;
  final bool selected;
  final bool editing;
  final bool textEditing;
  final VoidCallback onTap;
  final VoidCallback onEditText;
  final ValueChanged<Offset> onMove;
  final ValueChanged<Offset> onResize;
  final ValueChanged<String> onTextChanged;

  @override
  State<BlockWidget> createState() => _BlockWidgetState();
}

class _BlockWidgetState extends State<BlockWidget> {
  late final TextEditingController _controller;
  bool _resizing = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.block.text);
  }

  @override
  void didUpdateWidget(covariant BlockWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.block.text != widget.block.text &&
        _controller.text != widget.block.text) {
      _controller.value = TextEditingValue(
        text: widget.block.text,
        selection: TextSelection.collapsed(offset: widget.block.text.length),
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final content = widget.editing && widget.selected && widget.textEditing
        ? TextField(
            controller: _controller,
            autofocus: true,
            maxLines: null,
            expands: true,
            onChanged: widget.onTextChanged,
            style: Theme.of(context).textTheme.bodyLarge,
            decoration: const InputDecoration(
              border: InputBorder.none,
              contentPadding: EdgeInsets.all(8),
            ),
          )
        : Align(
            alignment: Alignment.topLeft,
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Text(
                widget.block.text.isEmpty ? 'Write here...' : widget.block.text,
                style: Theme.of(context).textTheme.bodyLarge,
              ),
            ),
          );

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.editing ? widget.onTap : null,
      onDoubleTap: widget.editing ? widget.onEditText : null,
      onPanStart: widget.editing
        ? (details) {
          final size = context.size ?? Size.zero;
          _resizing = details.localPosition.dx >= size.width - 44 &&
            details.localPosition.dy >= size.height - 44;
          widget.onTap();
        }
        : null,
      onPanUpdate: widget.editing
        ? (details) =>
          _resizing ? widget.onResize(details.delta) : widget.onMove(details.delta)
        : null,
      onPanEnd: widget.editing ? (_) => _resizing = false : null,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: widget.selected
              ? Border.all(color: const Color(0xFFC97068), width: 1.5)
              : null,
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            content,
            if (widget.editing && widget.selected)
              Positioned(
                right: 0,
                bottom: 0,
                child: Listener(
                  behavior: HitTestBehavior.opaque,
                  onPointerMove: (event) => widget.onResize(event.delta),
                  child: Container(
                  key: ValueKey('resize-${widget.block.id}'),
                    width: 28,
                    height: 28,
                    decoration: const BoxDecoration(
                      color: Color(0xFFC97068),
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}