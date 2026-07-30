import 'package:flutter/material.dart';
import 'package:offline_upload_queue/offline_upload_queue.dart';

import '../main.dart';

/// Tab 4: Disk usage and queue summary — estimatedDiskUsageBytes, purge helpers.
class DiskScreen extends StatelessWidget {
  const DiskScreen({super.key});

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Disk & summary — estimatedDiskUsageBytes'),
        centerTitle: true,
      ),
      body: StreamBuilder<QueueSummary>(
        stream: uploadQueue.watchSummary(),
        builder: (context, snap) {
          final s = snap.data;
          if (s == null) {
            return const Center(child: CircularProgressIndicator());
          }
          final diskBytes = s.estimatedDiskUsageBytes;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                color: theme.colorScheme.primaryContainer,
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    children: [
                      const Icon(Icons.storage, size: 40),
                      const SizedBox(height: 8),
                      Text(
                        _formatBytes(diskBytes),
                        style: const TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const Text(
                        'Estimated disk usage',
                        style: TextStyle(fontSize: 13),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'copyToSandbox: true — sandbox copies for\n'
                        'pending/failed tasks are counted here\n'
                        '(~2× cost when hardlink falls back to a full copy).',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 11,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Status summary',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(height: 12),
                      _SummaryRow('pending', s.pending, Colors.orange),
                      _SummaryRow('uploading', s.uploading, Colors.blue),
                      _SummaryRow('completed', s.completed, Colors.green),
                      _SummaryRow('failed', s.failed, Colors.amber),
                      _SummaryRow(
                        'permanentlyFailed',
                        s.permanentlyFailed,
                        Colors.red,
                      ),
                      _SummaryRow('cancelled', s.cancelled, Colors.grey),
                      const Divider(),
                      _SummaryRow('TOTAL', s.total, theme.colorScheme.primary),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              const Text(
                'Cleanup',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
              ),
              const SizedBox(height: 8),

              FilledButton.tonal(
                onPressed: s.completed > 0
                    ? () => uploadQueue.purgeAllCompleted()
                    : null,
                child: Text('Purge completed (${s.completed} records)'),
              ),
              const SizedBox(height: 8),
              FilledButton.tonal(
                onPressed: s.cancelled > 0
                    ? () => uploadQueue.purgeAllCancelled()
                    : null,
                child: Text('Purge cancelled (${s.cancelled} records)'),
              ),
              const SizedBox(height: 8),
              FilledButton.tonal(
                onPressed: s.permanentlyFailed > 0
                    ? () => uploadQueue.purgeAllFailed()
                    : null,
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.redAccent.withValues(alpha: 0.15),
                  foregroundColor: Colors.redAccent,
                ),
                child: Text(
                  'Purge permanent failures (${s.permanentlyFailed} records)',
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  final String label;
  final int count;
  final Color color;
  const _SummaryRow(this.label, this.count, this.color);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(label, style: const TextStyle(fontFamily: 'monospace')),
          ),
          Text(
            '$count',
            style: TextStyle(fontWeight: FontWeight.bold, color: color),
          ),
        ],
      ),
    );
  }
}
