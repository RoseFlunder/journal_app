import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../models/journal_share_result.dart';
export '../models/journal_share_result.dart';
import 'journal_archive.dart';
import 'shared_file_io_stub.dart'
    if (dart.library.io) 'shared_file_io.dart'
    as platform;

class IncomingJournalFile {
  const IncomingJournalFile({required this.id, this.path, this.error});
  final String id;
  final String? path;
  final String? error;
}

abstract interface class JournalTransferGateway {
  Future<JournalShareResult> shareArchive(JournalArchive archive);
  Future<bool> saveArchive(JournalArchive archive);
  Future<JournalArchive?> pickArchive();
  Stream<IncomingJournalFile> get incomingFiles;
  Future<JournalArchive> readIncoming(IncomingJournalFile file);
  Future<void> acknowledgeIncoming(String id);
}

class JournalTransferService implements JournalTransferGateway {
  const JournalTransferService();
  static const _events = EventChannel('app.stephandev.journal/incoming');
  static const _methods = MethodChannel('app.stephandev.journal/files');
  // Includes ZIP headers and manifest above the archive's 512 MiB asset limit.
  static const maxFileBytes = 544 * 1024 * 1024;

  static String fileName(JournalArchive archive) {
    var title = archive.document.title
        .trim()
        .replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1f]'), '_')
        .replaceAll(RegExp(r'[. ]+$'), '');
    if (title.isEmpty) title = 'Journal page';
    title = String.fromCharCodes(title.runes.take(80));
    final date = archive.document.createdAt
        .toUtc()
        .toIso8601String()
        .split('T')
        .first;
    return '$date $title.cozyjournal';
  }

  @override
  Future<JournalShareResult> shareArchive(JournalArchive archive) async {
    final bytes = archive.encode();
    final name = fileName(archive);
    final file = await platform.prepareSharedFile(bytes, name);
    try {
      final result = await SharePlus.instance.share(
        ShareParams(
          files: [file],
          fileNameOverrides: [name],
          title: 'Share page',
        ),
      );
      return switch (result.status) {
        ShareResultStatus.success => JournalShareResult.shared,
        ShareResultStatus.dismissed => JournalShareResult.dismissed,
        // Unavailable means the OS cannot report the outcome.
        ShareResultStatus.unavailable => JournalShareResult.unknown,
      };
    } on MissingPluginException {
      return JournalShareResult.unavailable;
    } on PlatformException {
      return JournalShareResult.unavailable;
    } on UnsupportedError {
      return JournalShareResult.unavailable;
    }
  }

  @override
  Future<bool> saveArchive(JournalArchive archive) async =>
      await FilePicker.saveFile(
        fileName: fileName(archive),
        bytes: archive.encode(),
        mimeType: 'application/x-cozyjournal',
        dialogTitle: 'Save shared page',
        type: FileType.custom,
        allowedExtensions: ['cozyjournal'],
      ) !=
      null;

  @override
  Future<JournalArchive?> pickArchive() async {
    final picked = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['cozyjournal'],
    );
    if (picked.isEmpty) return null;
    final file = picked.single;
    if ((file.lengthSync() ?? 0) > maxFileBytes) {
      throw const FormatException('This shared page is too large.');
    }
    return readArchiveStream(file.readAsByteStream());
  }

  static Future<JournalArchive> readArchiveFile(XFile file) async {
    if (await file.length() > maxFileBytes) {
      throw const FormatException('This shared page is too large.');
    }
    return readArchiveStream(file.openRead());
  }

  static Future<JournalArchive> readArchiveStream(
    Stream<List<int>> stream,
  ) async {
    final bytes = BytesBuilder(copy: false);
    await for (final chunk in stream) {
      if (bytes.length + chunk.length > maxFileBytes) {
        throw const FormatException('This shared page is too large.');
      }
      bytes.add(chunk);
    }
    return JournalArchive.decode(bytes.takeBytes());
  }

  @override
  Stream<IncomingJournalFile> get incomingFiles async* {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return;
    }
    try {
      if (await _methods.invokeMethod<bool>('isAvailable') != true) return;
    } on MissingPluginException {
      return;
    }
    yield* _events.receiveBroadcastStream().map((event) {
      final data = event as Map;
      return IncomingJournalFile(
        id: data['id'] as String,
        path: data['path'] as String?,
        error: data['error'] as String?,
      );
    });
  }

  @override
  Future<JournalArchive> readIncoming(IncomingJournalFile file) async {
    if (file.error != null || file.path == null) {
      throw const FormatException('Could not read this shared page.');
    }
    return readArchiveFile(XFile(file.path!));
  }

  @override
  Future<void> acknowledgeIncoming(String id) =>
      _methods.invokeMethod<void>('acknowledge', id);
}
