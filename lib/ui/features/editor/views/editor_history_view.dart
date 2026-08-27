import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../models/checkpoint.dart';

/// Recovery sheet that renders checkpoint state and emits restore intents.
class EditorHistoryView extends StatelessWidget {
  const EditorHistoryView({
    super.key,
    required this.checkpoints,
    required this.onCreateCheckpoint,
    required this.onRestore,
  });

  final List<CheckpointInfo> checkpoints;
  final Future<void> Function() onCreateCheckpoint;
  final Future<void> Function(CheckpointInfo checkpoint) onRestore;

  @override
  Widget build(BuildContext context) => SafeArea(
    child: SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.62,
      child: Column(
        children: [
          ListTile(
            leading: const Icon(Icons.add_task_outlined),
            title: const Text('Create recovery checkpoint'),
            onTap: () async {
              await onCreateCheckpoint();
            },
          ),
          const Divider(height: 1),
          Expanded(
            child: checkpoints.isEmpty
                ? const Center(child: Text('No recovery checkpoints yet'))
                : ListView.builder(
                    itemCount: checkpoints.length,
                    itemBuilder: (context, index) {
                      final checkpoint = checkpoints[index];
                      return ListTile(
                        leading: const Icon(Icons.restore),
                        title: Text(
                          DateFormat.yMMMd().add_jm().format(
                            checkpoint.createdAt,
                          ),
                        ),
                        subtitle: const Text('Restore this local version'),
                        onTap: () async {
                          await onRestore(checkpoint);
                          if (context.mounted) Navigator.pop(context);
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
    ),
  );
}
