// Named capability parameters keep repository fields private.
// ignore_for_file: prefer_initializing_formals

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../../models/document.dart';
import '../../../../services/journal_archive.dart';
import '../../../../services/journal_transfer_service.dart';
import '../../../../services/repositories.dart';

class SharedPageViewModel extends ChangeNotifier {
  SharedPageViewModel({
    required ArchiveRepository archives,
    required JournalTransferGateway transfer,
  }) : _archives = archives,
       _transfer = transfer;

  final ArchiveRepository _archives;
  final JournalTransferGateway _transfer;
  final Set<String> _deliveries = {};
  StreamSubscription<IncomingJournalFile>? _subscription;
  Future<void> _queue = Future<void>.value();
  Completer<bool>? _confirmation;
  EntryDocument? _pending;
  bool _disposed = false;
  int _queued = 0;
  String? _error;
  String? _addedPageId;

  EntryDocument? get pendingPage => _pending;
  bool get busy => _queued > 0;

  String? takeError() {
    final error = _error;
    _error = null;
    return error;
  }

  String? takeAddedPageId() {
    final id = _addedPageId;
    _addedPageId = null;
    return id;
  }

  void start() {
    _subscription ??= _transfer.incomingFiles.listen(
      (file) {
        if (!_deliveries.add(file.id)) return;
        _enqueue(() => _transfer.readIncoming(file), deliveryId: file.id);
      },
      onError: (Object error) {
        _error = 'Could not open the shared page. Try Add shared page.';
        _notify();
      },
    );
  }

  Future<void> pickPage() {
    if (busy || _disposed) return Future<void>.value();
    return _enqueue(_transfer.pickArchive);
  }

  void confirm(bool add) {
    final confirmation = _confirmation;
    if (confirmation != null && !confirmation.isCompleted) {
      confirmation.complete(add);
    }
  }

  Future<void> _enqueue(
    Future<JournalArchive?> Function() read, {
    String? deliveryId,
  }) {
    _queued++;
    _notify();
    _queue = _queue.then((_) async {
      if (_disposed) return;
      try {
        final archive = await read();
        if (archive == null || _disposed) return;
        archive.validate();
        _pending = archive.document;
        final confirmation = Completer<bool>();
        _confirmation = confirmation;
        _notify();
        final add = await confirmation.future;
        _pending = null;
        _confirmation = null;
        _notify();
        if (add && !_disposed) {
          final document = await _archives.importArchive(archive);
          _addedPageId = document.id;
        }
      } on FormatException {
        _error = 'This file is not a supported shared page, or it is damaged or too large.';
      } catch (_) {
        _error = 'Could not add this page. Please try again.';
      } finally {
        _pending = null;
        _confirmation = null;
        if (deliveryId != null) {
          try {
            await _transfer.acknowledgeIncoming(deliveryId);
          } catch (_) {
            // Keep the delivery ID in memory so a reconnect cannot add it twice.
          }
        }
        _queued--;
        _notify();
      }
    });
    return _queue;
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    confirm(false);
    unawaited(_subscription?.cancel());
    super.dispose();
  }
}
