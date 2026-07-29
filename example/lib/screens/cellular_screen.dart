import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:offline_upload_queue/offline_upload_queue.dart';

import '../main.dart';

/// Sekme 2: wifiOnly + forceUploadOnce().
///
/// Gösterilen API'ler:
///   - `wifiOnly: true` etkin ayrı kuyruk örneği
///   - `forceUploadOnce()` — cellular'da "Şimdi Yükle" butonu (plan §1, test #15)
///   - `pause()` / `resume()`
///   - `watchSummary()` üzerinden `isPaused` bayrağı

/// wifiOnly: true modunda çalışan ayrı kuyruk örneği.
final wifiOnlyQueue = UploadQueue(
  adapter: uploadQueue.adapter, // MockUploadAdapter'ı paylaş
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
        const SnackBar(content: Text('Kuyruğa eklendi (Wi-Fi bekleniyor)')),
      );
    }
  }

  Future<void> _forceUpload() async {
    await _ensureWifiQueueReady();
    // forceUploadOnce() → wifiOnly: true olsa bile mevcut bağlantıda işler
    await wifiOnlyQueue.forceUploadOnce();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('forceUploadOnce() çağrıldı — cellular\'da çalışır'),
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
            // Açıklama kartı
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
                      'Bu sekmedeki kuyruk yalnızca Wi-Fi bağlantısında '
                      'otomatik yükleme yapar.\n\n'
                      '"Şimdi Yükle" butonu forceUploadOnce() çağırır — '
                      'cellular\'da da çalışır (tek seferlik bypass).',
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Canlı özet (Sadece kuyruk hazırsa göster)
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
                            _Info('Bekliyor', s.pending.toString()),
                            _Info('Tamamlandı', s.completed.toString()),
                            _Info(
                              'Duraklatıldı',
                              s.isPaused ? 'Evet' : 'Hayır',
                            ),
                          ],
                        ),
                      );
                    },
                  )
                : const Center(child: CircularProgressIndicator()),
            const SizedBox(height: 24),

            // Butonlar
            FilledButton.icon(
              onPressed: _pickAndEnqueue,
              icon: const Icon(Icons.photo_library_outlined),
              label: const Text('Galeriden Ekle (Wi-Fi bekliyor)'),
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
                  Text('Şimdi Yükle — forceUploadOnce()'),
                ],
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _togglePause,
              icon: Icon(_paused ? Icons.play_arrow : Icons.pause),
              label: Text(_paused ? 'Devam Et (resume)' : 'Duraklat (pause)'),
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
