import 'package:flutter/material.dart';
import 'package:workmanager/workmanager.dart';

import 'package:offline_upload_queue/offline_upload_queue.dart';

import 'screens/queue_screen.dart';
import 'screens/cellular_screen.dart';
import 'screens/error_screen.dart';
import 'screens/disk_screen.dart';

/// Demo adapter — yanıt vermiyor ama API'yi göstermek için yeterli.
///
/// Gerçek uygulamada `RestUploadAdapter(baseUrl: 'https://...')` kullanın.
class MockUploadAdapter implements UploadAdapter {
  @override
  Future<UploadResult> uploadFile({
    required String taskId,
    required String filePath,
    required Map<String, dynamic> metadata,
    required String checksum,
    void Function(int sent, int total)? onProgress,
    UploadCancelToken? cancelToken,
  }) async {
    // Simulate a 2-second upload with progress
    const steps = 10;
    for (var i = 1; i <= steps; i++) {
      if (cancelToken?.isCancelled ?? false) {
        return const UploadResult.failure(FailureType.unknown);
      }
      await Future<void>.delayed(const Duration(milliseconds: 200));
      onProgress?.call(i * 100, steps * 100);
    }
    return const UploadResult.success();
  }
}

@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((taskName, inputData) async {
    if (taskName == AndroidBackgroundRunner.taskName) {
      final queue = UploadQueue(adapter: MockUploadAdapter());
      final hasPending = await BackgroundTaskRunner.run(queue);
      if (hasPending) await AndroidBackgroundRunner.scheduleNextRun();
      return true;
    }
    return false;
  });
}

/// Uygulama genelinde paylaşılan tek UploadQueue örneği.
final uploadQueue = UploadQueue(
  adapter: MockUploadAdapter(),
  wifiOnly: false,
  maxAttempts: 4,
  advanced: UploadQueueAdvancedOptions(
    diskUsageWarningBytes: 50 * 1024 * 1024, // 50 MB
    onDiskUsageWarning: (current, limit) {
      debugPrint('⚠️ Disk uyarısı: $current / $limit byte');
    },
    onLog: (message, {required level}) {
      if (level == LogLevel.warning || level == LogLevel.error) {
        debugPrint('[${level.name.toUpperCase()}] $message');
      }
    },
  ),
);

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  Workmanager().initialize(callbackDispatcher, isInDebugMode: true);

  await uploadQueue.init();

  runApp(const OfflineUploadQueueDemoApp());
}

class OfflineUploadQueueDemoApp extends StatelessWidget {
  const OfflineUploadQueueDemoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'offline_upload_queue Demo',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF5B6BF8),
          brightness: Brightness.dark,
        ),
      ),
      home: const MainShell(),
    );
  }
}

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _selectedIndex = 0;

  static const _screens = [
    QueueScreen(),
    CellularScreen(),
    ErrorScreen(),
    DiskScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _screens[_selectedIndex],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (i) => setState(() => _selectedIndex = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.upload_outlined),
            selectedIcon: Icon(Icons.upload),
            label: 'Kuyruk',
          ),
          NavigationDestination(
            icon: Icon(Icons.signal_cellular_alt_outlined),
            selectedIcon: Icon(Icons.signal_cellular_alt),
            label: 'Cellular',
          ),
          NavigationDestination(
            icon: Icon(Icons.error_outline),
            selectedIcon: Icon(Icons.error),
            label: 'Hata',
          ),
          NavigationDestination(
            icon: Icon(Icons.storage_outlined),
            selectedIcon: Icon(Icons.storage),
            label: 'Disk',
          ),
        ],
      ),
    );
  }
}
