import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:offline_upload_queue/offline_upload_queue.dart';

import '../main.dart';

/// Tab 2: wifiOnly + forceUploadOnce(), pause / resume.

final wifiOnlyQueue = UploadQueue(
  adapter: uploadQueue.adapter,
  wifiOnly: true,
  boxName: 'wifi_only_demo',
  maxAttempts: 3,
);

bool _wifiQueueInitialized = false;

Future<void> _ensureWifiQueueReady() async {
  if (!_wifiQueueInitialized) {
    await wifiOnlyQueue.init();
    _wifiQueueInitialized = true;
  }
}

class CellularScreen extends StatefulWidget {
  const CellularScreen({super.key});

  @override
  State<CellularScreen> createState() => _CellularScreenState();
}

class _CellularScreenState extends State<CellularScreen> {
  bool _paused = false;
  bool _isReady = false;

  @override
  void initState() {
    super.initState();
    _ensureWifiQueueReady().then((_) {
      if (mounted) {
        setState(() => _isReady = true);
      }
    });
  }

  Future<void> _pickAndEnqueue() async {
    await _ensureWifiQueueReady();
    final picker = ImagePicker();
    final file = await picker.pickImage(source: ImageSource.gallery);
    if (file == null) return;
    await wifiOnlyQueue.enqueue(
      filePath: file.path,
      metadata: {'demo': 'wifi_only'},
    );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enqueued (waiting for Wi‑Fi)')),
      );
    }
  }

  Future<void> _forceUpload() async {
    await _ensureWifiQueueReady();
    await wifiOnlyQueue.forceUploadOnce();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('forceUploadOnce() — runs once on cellular'),
        ),
      );
    }
  }

  void _togglePause() {
    setState(() => _paused = !_paused);
    if (_paused) {
      wifiOnlyQueue.pause();
    } else {
      wifiOnlyQueue.resume();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Cellular Override — forceUploadOnce'),
        centerTitle: true,
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Card(
              color: theme.colorScheme.surfaceContainerHighest,
              child: const Padding(
                padding: EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'wifiOnly: true',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    SizedBox(height: 8),
                    Text(
                      'This queue only auto-uploads on Wi‑Fi.\n\n'
                      '"Upload now" calls forceUploadOnce() — a one-shot '
                      'bypass that also works on cellular.',
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            _isReady
                ? StreamBuilder<QueueSummary>(
                    stream: wifiOnlyQueue.watchSummary(),
                    builder: (context, snap) {
                      final s = snap.data;
                      if (s == null) return const SizedBox.shrink();
                      return Container(
                        padding: const EdgeInsets.symmetric(
                          vertical: 12,
                          horizontal: 16,
                        ),
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: theme.colorScheme.outline.withValues(
                              alpha: 0.4,
                            ),
                          ),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceAround,
                          children: [
                            _Info('Pending', s.pending.toString()),
                            _Info('Completed', s.completed.toString()),
                            _Info(
                              'Paused',
                              s.isPaused ? 'Yes' : 'No',
                            ),
                          ],
                        ),
                      );
                    },
                  )
                : const Center(child: CircularProgressIndicator()),
            const SizedBox(height: 24),

            FilledButton.icon(
              onPressed: _pickAndEnqueue,
              icon: const Icon(Icons.photo_library_outlined),
              label: const Text('Add from gallery (waits for Wi‑Fi)'),
            ),
            const SizedBox(height: 12),
            FilledButton.tonal(
              onPressed: _forceUpload,
              style: FilledButton.styleFrom(
                backgroundColor: Colors.deepOrangeAccent.withValues(alpha: 0.2),
                foregroundColor: Colors.deepOrangeAccent,
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.bolt),
                  SizedBox(width: 8),
                  Text('Upload now — forceUploadOnce()'),
                ],
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _togglePause,
              icon: Icon(_paused ? Icons.play_arrow : Icons.pause),
              label: Text(_paused ? 'Resume' : 'Pause'),
            ),
          ],
        ),
      ),
    );
  }
}

class _Info extends StatelessWidget {
  final String label;
  final String value;
  const _Info(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          value,
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 2),
        Text(label, style: const TextStyle(fontSize: 11)),
      ],
    );
  }
}
