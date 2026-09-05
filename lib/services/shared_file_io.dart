import 'dart:io';

import 'package:cross_file/cross_file.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

Future<XFile> prepareSharedFile(List<int> bytes, String name) async {
  final root = Directory('${(await getTemporaryDirectory()).path}/cozy-shares');
  await root.create(recursive: true);
  final expiry = DateTime.now().subtract(const Duration(days: 7));
  await for (final item in root.list(followLinks: false)) {
    if (item is Directory && (await item.stat()).modified.isBefore(expiry)) {
      try {
        await item.delete(recursive: true);
      } on FileSystemException {
        // Another app may still be reading a previously shared file.
      }
    }
  }
  final folder = await Directory('${root.path}/${const Uuid().v4()}').create();
  final file = await File('${folder.path}/$name')
      .writeAsBytes(bytes, flush: true);
  return XFile(file.path, mimeType: 'application/x-cozyjournal');
}
