import 'package:flutter/material.dart';
import 'package:offline_upload_queue/offline_upload_queue.dart';

// Global log list that will be populated from main.dart
final ValueNotifier<List<String>> globalLogsNotifier = ValueNotifier([]);

class DebugScreen extends StatefulWidget {
  final UploadQueue uploadQueue;

  const DebugScreen({super.key, required this.uploadQueue});

  @override
  State<DebugScreen> createState() => _DebugScreenState();
}

class _DebugScreenState extends State<DebugScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Debug / Test Panel'),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_sweep),
            tooltip: 'Clear Logs',
            onPressed: () {
              globalLogsNotifier.value = [];
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // Queue Summary
          StreamBuilder<QueueSummary>(
            stream: widget.uploadQueue.watchSummary(),
            builder: (context, snapshot) {
              final summary = snapshot.data;
              if (summary == null) return const SizedBox.shrink();

              return Card(
                margin: const EdgeInsets.all(8),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _Stat('Pending', summary.pending),
                      _Stat('Uploading', summary.uploading),
                      _Stat('Failed', summary.failed),
                      _Stat('Completed', summary.completed),
                    ],
                  ),
                ),
              );
            },
          ),

          const Divider(),
          const Text(
            'Live Logs',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),

          // Log List
          Expanded(
            child: ValueListenableBuilder<List<String>>(
              valueListenable: globalLogsNotifier,
              builder: (context, logs, child) {
                if (logs.isEmpty) {
                  return const Center(child: Text('No logs yet.'));
                }
                return ListView.builder(
                  reverse: false,
                  itemCount: logs.length,
                  itemBuilder: (context, index) {
                    final log = logs[index];
                    Color? textColor;
                    if (log.startsWith('[ERROR]')) {
                      textColor = Colors.red;
                    } else if (log.startsWith('[WARNING]')) {
                      textColor = Colors.orange;
                    } else if (log.startsWith('[INFO]')) {
                      textColor = Colors.blue;
                    }
                    return Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8.0,
                        vertical: 2.0,
                      ),
                      child: Text(
                        log,
                        style: TextStyle(
                          color: textColor,
                          fontSize: 12,
                          fontFamily: 'monospace',
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

class _Stat extends StatelessWidget {
  final String label;
  final int count;

  const _Stat(this.label, this.count);

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          count.toString(),
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        Text(label, style: const TextStyle(fontSize: 12)),
      ],
    );
  }
}
