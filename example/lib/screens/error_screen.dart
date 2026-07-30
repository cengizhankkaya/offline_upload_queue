import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:offline_upload_queue/offline_upload_queue.dart';
import 'package:path_provider/path_provider.dart';

import '../main.dart';

/// Tab 3: Error handling — permanentlyFailed, retry(), purge().
class ErrorScreen extends StatelessWidget {
  const ErrorScreen({super.key});

  Future<void> _enqueueNonExistent(BuildContext context) async {
    // enqueue() requires a real file path; MockUploadAdapter fails on demo:error_case.
    final tempDir = await getTemporaryDirectory();
    final bogusFile = File('${tempDir.path}/dummy_error_file.jpg');
    if (!bogusFile.existsSync()) {
      await bogusFile.writeAsString('dummy');
    }

    await uploadQueue.enqueue(
      filePath: bogusFile.path,
      metadata: {'demo': 'error_case'},
    );
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Error file enqueued — will become permanentlyFailed shortly',
          ),
        ),
      );
    }
  }

  Future<void> _enqueueReal(BuildContext context) async {
    final picker = ImagePicker();
    final file = await picker.pickImage(source: ImageSource.gallery);
    if (file == null) return;
    await uploadQueue.enqueue(filePath: file.path);
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Real file enqueued')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Error handling — retry & purge'),
        centerTitle: true,
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Card(
              color: theme.colorScheme.errorContainer,
              child: const Padding(
                padding: EdgeInsets.all(14),
                child: Text(
                  '"Enqueue error file" intentionally fails.\n'
                  'Once the task is permanentlyFailed, use retry() or purge().',
                  style: TextStyle(fontSize: 13),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Expanded(
                  child: FilledButton.tonal(
                    onPressed: () => _enqueueNonExistent(context),
                    child: const Text('Enqueue error file'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton(
                    onPressed: () => _enqueueReal(context),
                    child: const Text('Enqueue real file'),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                icon: const Icon(
                  Icons.delete_sweep_outlined,
                  color: Colors.redAccent,
                ),
                label: const Text(
                  'Purge all permanent failures',
                  style: TextStyle(color: Colors.redAccent),
                ),
                onPressed: () async {
                  await uploadQueue.purgeAllFailed();
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('All permanentlyFailed tasks deleted'),
                      ),
                    );
                  }
                },
              ),
            ),
          ),
          const Divider(height: 24),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Failed / cancelled tasks',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ),
          Expanded(
            child: StreamBuilder<List<UploadTask>>(
              stream: uploadQueue.watchTasks(
                statuses: {
                  UploadStatus.permanentlyFailed,
                  UploadStatus.cancelled,
                  UploadStatus.failed,
                },
                limit: 30,
              ),
              builder: (context, snap) {
                final tasks = snap.data ?? [];
                if (tasks.isEmpty) {
                  return const Center(
                    child: Text('No errors', style: TextStyle(fontSize: 16)),
                  );
                }
                return ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  itemCount: tasks.length,
                  itemBuilder: (context, i) {
                    final t = tasks[i];
                    return Card(
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      child: ListTile(
                        leading: Icon(
                          t.status == UploadStatus.permanentlyFailed
                              ? Icons.error
                              : Icons.cancel,
                          color: t.status == UploadStatus.permanentlyFailed
                              ? Colors.redAccent
                              : Colors.grey,
                        ),
                        title: Text(
                          t.taskId.substring(0, 8),
                          style: const TextStyle(fontFamily: 'monospace'),
                        ),
                        subtitle: Text(
                          '${t.status.name}  •  ${t.failureType?.name ?? '—'}',
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.refresh),
                              tooltip: 'retry()',
                              onPressed: () => uploadQueue.retry(t.taskId),
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete_outline),
                              tooltip: 'purge()',
                              onPressed: () => uploadQueue.purge(t.taskId),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
