import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:offline_upload_queue/offline_upload_queue.dart';

import '../main.dart';

/// Sekme 1: Temel kuyruk kullanımı.
///
/// Gösterilen API'ler:
///   - `image_picker` ile dosya seçme
///   - `enqueue()` ile kuyruğa ekleme
///   - `watchSummary()` ile canlı sayaç
///   - `watchTasks()` ile görev listesi (liste index'i kullanılır, sequenceNumber değil)
///   - `cancel()` ve `purge()`
class QueueScreen extends StatelessWidget {
  const QueueScreen({super.key});

  Future<void> _pickAndEnqueue(BuildContext context) async {
    final picker = ImagePicker();
    final files = await picker.pickMultiImage();
    if (files.isEmpty) return;
    final items = files
        .map(
          (f) => (
            filePath: f.path,
            metadata: <String, dynamic>{'source': 'gallery', 'name': f.name},
            priority: 0,
          ),
        )
        .toList();

    await uploadQueue.enqueueBatch(items);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${files.length} dosya kuyruğa eklendi')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Kuyruk — enqueue + watchSummary'),
        centerTitle: true,
      ),
      body: Column(
        children: [
          // ── Canlı özet banner ──────────────────────────────────────────────
          StreamBuilder<QueueSummary>(
            stream: uploadQueue.watchSummary(),
            builder: (context, snap) {
              final s = snap.data;
              return Container(
                width: double.infinity,
                margin: const EdgeInsets.all(12),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: s == null
                    ? const Center(child: CircularProgressIndicator())
                    : Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          _StatChip(
                            label: 'Bekliyor',
                            value: s.pending,
                            color: Colors.orangeAccent,
                          ),
                          _StatChip(
                            label: 'Yükleniyor',
                            value: s.uploading,
                            color: Colors.blueAccent,
                          ),
                          _StatChip(
                            label: 'Tamamlandı',
                            value: s.completed,
                            color: Colors.greenAccent,
                          ),
                          _StatChip(
                            label: 'Hata',
                            value: s.permanentlyFailed,
                            color: Colors.redAccent,
                          ),
                        ],
                      ),
              );
            },
          ),

          // ── Genel İlerleme (Overall Progress) ───────────────────────────────
          StreamBuilder<double>(
            stream: uploadQueue.watchOverallProgress(),
            builder: (context, snap) {
              final progress = snap.data ?? 0.0;
              // 0.0 veya 1.0 (hiç işlem yok veya bitti) ise çubuğu gizle
              if (progress == 0.0 || progress == 1.0) {
                return const SizedBox.shrink();
              }
              return Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16.0,
                  vertical: 4.0,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Genel İlerleme: ${(progress * 100).toStringAsFixed(1)}%',
                      style: theme.textTheme.bodySmall,
                    ),
                    const SizedBox(height: 6),
                    LinearProgressIndicator(
                      value: progress,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ],
                ),
              );
            },
          ),

          // ── Görev listesi (index kullanılır, sequenceNumber değil) ─────────
          Expanded(
            child: StreamBuilder<List<UploadTask>>(
              stream: uploadQueue.watchTasks(limit: 30),
              builder: (context, snap) {
                final tasks = snap.data ?? [];
                if (tasks.isEmpty) {
                  return const Center(
                    child: Text(
                      'Kuyruk boş.\nGaleri\'den fotoğraf seç.',
                      textAlign: TextAlign.center,
                    ),
                  );
                }
                return ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  itemCount: tasks.length,
                  itemBuilder: (context, index) {
                    final task = tasks[index];
                    return _TaskTile(
                      // UI'da "N. sıra" için liste index'i kullanılır (plan §5)
                      position: index + 1,
                      task: task,
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _pickAndEnqueue(context),
        icon: const Icon(Icons.add_photo_alternate_outlined),
        label: const Text('Fotoğraf Ekle'),
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  final String label;
  final int value;
  final Color color;
  const _StatChip({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '$value',
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        const SizedBox(height: 4),
        Text(label, style: const TextStyle(fontSize: 11)),
      ],
    );
  }
}

class _TaskTile extends StatelessWidget {
  final int position;
  final UploadTask task;
  const _TaskTile({required this.position, required this.task});

  Color _statusColor(UploadStatus s) => switch (s) {
    UploadStatus.pending => Colors.orange,
    UploadStatus.uploading => Colors.blue,
    UploadStatus.completed => Colors.green,
    UploadStatus.failed => Colors.amber,
    UploadStatus.permanentlyFailed => Colors.red,
    UploadStatus.cancelled => Colors.grey,
  };

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: _statusColor(task.status).withValues(alpha: 0.2),
          child: Text(
            '$position',
            style: TextStyle(color: _statusColor(task.status)),
          ),
        ),
        title: Text(
          task.taskId.substring(0, 8),
          style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
        ),
        subtitle: Text(task.status.name),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (task.status == UploadStatus.uploading)
              StreamBuilder<double>(
                stream: uploadQueue.watchProgress(task.taskId),
                builder: (ctx, snap) {
                  return SizedBox(
                    width: 32,
                    height: 32,
                    child: CircularProgressIndicator(
                      value: snap.data,
                      strokeWidth: 3,
                    ),
                  );
                },
              )
            else if (task.status == UploadStatus.pending ||
                task.status == UploadStatus.failed)
              IconButton(
                icon: const Icon(Icons.cancel_outlined),
                onPressed: () => uploadQueue.cancel(task.taskId),
                tooltip: 'İptal',
              ),
            if (task.status == UploadStatus.cancelled ||
                task.status == UploadStatus.permanentlyFailed)
              IconButton(
                icon: const Icon(Icons.delete_outline),
                onPressed: () => uploadQueue.purge(task.taskId),
                tooltip: 'Sil',
              ),
          ],
        ),
      ),
    );
  }
}
