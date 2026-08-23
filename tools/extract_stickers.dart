import 'dart:collection';
import 'dart:io';
import 'dart:typed_data';

import 'package:image/image.dart' as img;

void main(List<String> args) {
  final sourcePath = args.isNotEmpty
      ? args[0]
      : 'assets/stickers/sticker_sheet_source.png';
  final reportOnly = args.contains('--report-only');
  final source = img.decodePng(File(sourcePath).readAsBytesSync());
  if (source == null) throw StateError('Could not decode $sourcePath');

  final components = _findComponents(source);
  final groups = _mergeNearby(components, gap: 32);
  groups.sort((a, b) => a.top.compareTo(b.top));

  stdout.writeln('source: ${source.width}x${source.height}');
  stdout.writeln('components: ${components.length}, groups: ${groups.length}');
  for (var i = 0; i < groups.length; i++) {
    final g = groups[i];
    stdout.writeln(
      '${i + 1}: ${g.left},${g.top} ${g.width}x${g.height} area=${g.area}',
    );
  }
  if (reportOnly) return;

  final outputDir = Directory('assets/stickers/extracted')..createSync(recursive: true);
  for (var i = 0; i < groups.length; i++) {
    final g = groups[i];
    final padding = 10;
    final left = (g.left - padding).clamp(0, source.width - 1);
    final top = (g.top - padding).clamp(0, source.height - 1);
    final right = (g.right + padding).clamp(0, source.width - 1);
    final bottom = (g.bottom + padding).clamp(0, source.height - 1);
    final cropped = img.copyCrop(
      source,
      x: left,
      y: top,
      width: right - left + 1,
      height: bottom - top + 1,
    );
    File('${outputDir.path}/sticker_${(i + 1).toString().padLeft(2, '0')}.png')
        .writeAsBytesSync(img.encodePng(cropped));
  }
}

class _Box {
  _Box(this.left, this.top, this.right, this.bottom, this.area);

  int left;
  int top;
  int right;
  int bottom;
  int area;

  int get width => right - left + 1;
  int get height => bottom - top + 1;
}

List<_Box> _findComponents(img.Image image) {
  final visited = Uint8List(image.width * image.height);
  final components = <_Box>[];
  final queue = Queue<int>();
  for (var y = 0; y < image.height; y++) {
    for (var x = 0; x < image.width; x++) {
      final start = y * image.width + x;
      if (visited[start] != 0 || image.getPixel(x, y).a < 24) continue;
      visited[start] = 1;
      queue.add(start);
      var left = x;
      var top = y;
      var right = x;
      var bottom = y;
      var area = 0;
      while (queue.isNotEmpty) {
        final current = queue.removeFirst();
        final cx = current % image.width;
        final cy = current ~/ image.width;
        area++;
        if (cx < left) left = cx;
        if (cy < top) top = cy;
        if (cx > right) right = cx;
        if (cy > bottom) bottom = cy;
        for (var dy = -1; dy <= 1; dy++) {
          for (var dx = -1; dx <= 1; dx++) {
            if (dx == 0 && dy == 0) continue;
            final nx = cx + dx;
            final ny = cy + dy;
            if (nx < 0 || ny < 0 || nx >= image.width || ny >= image.height) {
              continue;
            }
            final next = ny * image.width + nx;
            if (visited[next] == 0 && image.getPixel(nx, ny).a >= 24) {
              visited[next] = 1;
              queue.add(next);
            }
          }
        }
      }
      if (area >= 100) components.add(_Box(left, top, right, bottom, area));
    }
  }
  return components;
}

List<_Box> _mergeNearby(List<_Box> input, {required int gap}) {
  final groups = input.map((b) => _Box(b.left, b.top, b.right, b.bottom, b.area)).toList();
  var changed = true;
  while (changed) {
    changed = false;
    outer:
    for (var i = 0; i < groups.length; i++) {
      for (var j = i + 1; j < groups.length; j++) {
        final a = groups[i];
        final b = groups[j];
        final horizontalGap = b.left > a.right
            ? b.left - a.right
            : a.left > b.right
            ? a.left - b.right
            : 0;
        final verticalGap = b.top > a.bottom
            ? b.top - a.bottom
            : a.top > b.bottom
            ? a.top - b.bottom
            : 0;
        if (horizontalGap <= gap && verticalGap <= gap) {
          a.left = a.left < b.left ? a.left : b.left;
          a.top = a.top < b.top ? a.top : b.top;
          a.right = a.right > b.right ? a.right : b.right;
          a.bottom = a.bottom > b.bottom ? a.bottom : b.bottom;
          a.area += b.area;
          groups.removeAt(j);
          changed = true;
          break outer;
        }
      }
    }
  }
  return groups;
}
