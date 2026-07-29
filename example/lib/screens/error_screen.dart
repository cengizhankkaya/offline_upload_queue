import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:offline_upload_queue/offline_upload_queue.dart';
import 'package:path_provider/path_provider.dart';

import '../main.dart';

/// Sekme 3: Hata yönetimi.
///
/// Gösterilen API'ler:
///   - `permanentlyFailed` sonrası `retry()` (plan §4, §1 test #16)
///   - `purge()` — tekli silme
///   - `purgeAllFailed()` — toplu silme
///   - Kasıtlı hata üretmek için var olmayan bir dosya yolu enqueue edilir.

class ErrorScreen extends StatelessWidget {
  const ErrorScreen({super.key});

  Future<void> _enqueueNonExistent(BuildContext context) async {
    // QueueController.enqueue dosyanın gerçekten var olmasını bekler.
    // Bu yüzden geçici bir dosya yaratıp kuyruğa ekliyoruz. MockUploadAdapter 
    // metadata'daki 'demo': 'error_case' değerini görüp fileNotFound hatası dönecek.
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
            'Hatalı dosya eklendi — kısa süre içinde permanentlyFailed olacak',
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
      ).showSnackBar(const SnackBar(content: Text('Gerçek dosya eklendi')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Hata Yönetimi — retry & purge'),
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
                  '"Var Olmayan Dosya Ekle" butonu kasıtlı hata üretir.\n'
                  'Görev permanentlyFailed durumuna düşünce retry() veya purge() kullanabilirsiniz.',
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
                    child: const Text('Hatalı Dosya Ekle'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton(
                    onPressed: () => _enqueueReal(context),
                    child: const Text('Gerçek Dosya Ekle'),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          // Toplu temizleme
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
                  'Tüm Kalıcı Hataları Sil (purgeAllFailed)',
                  style: TextStyle(color: Colors.redAccent),
                ),
                onPressed: () async {
                  await uploadQueue.purgeAllFailed();
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Tüm permanentlyFailed görevler silindi'),
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
                'Başarısız / İptal Edilmiş Görevler',
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
                    child: Text('Hata yok 🎉', style: TextStyle(fontSize: 16)),
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
                            // retry() → pending'e döner
                            IconButton(
                              icon: const Icon(Icons.refresh),
                              tooltip: 'retry()',
                              onPressed: () => uploadQueue.retry(t.taskId),
                            ),
                            // purge() → sil
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
