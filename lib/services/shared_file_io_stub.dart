import 'dart:typed_data';

import 'package:cross_file/cross_file.dart';

Future<XFile> prepareSharedFile(List<int> bytes, String name) async =>
    XFile.fromData(
      Uint8List.fromList(bytes),
      name: name,
      mimeType: 'application/x-cozyjournal',
    );
