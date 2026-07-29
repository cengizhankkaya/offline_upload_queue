import 'package:flutter/material.dart';
import 'package:workmanager/workmanager.dart';
import 'package:http/http.dart' as http;
import 'dart:io';

import 'package:offline_upload_queue/offline_upload_queue.dart';

import 'screens/queue_screen.dart';
import 'screens/cellular_screen.dart';
import 'screens/error_screen.dart';
import 'screens/disk_screen.dart';
import 'screens/debug_screen.dart';

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
    if (metadata['demo'] == 'error_case') {
      return const UploadResult.failure(FailureType.fileNotFound);
    }
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

class ExampleRestAdapter implements UploadAdapter {
  // TODO: Update this to your development machine's local IP address
  // For Android Emulator, use 10.0.2.2. For iOS Simulator, use localhost.
  final String baseUrl = 'http://10.0.2.2:8080';

  @override
  Future<UploadResult> uploadFile({
    required String taskId,
    required String filePath,
    required Map<String, dynamic> metadata,
    required String checksum,
    void Function(int sent, int total)? onProgress,
    UploadCancelToken? cancelToken,
  }) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) {
        return const UploadResult.failure(FailureType.fileNotFound);
      }

      String endpoint = '/upload';
      if (metadata['demo'] == 'error_case') endpoint = '/upload_error';
      if (metadata['demo'] == 'timeout_case') endpoint = '/upload_timeout';
      if (metadata['demo'] == '429_case') endpoint = '/upload_429';

      final uri = Uri.parse('$baseUrl$endpoint');
      final request = http.MultipartRequest('POST', uri)
        ..files.add(await http.MultipartFile.fromPath('file', filePath));

      final streamedResponse = await request.send().timeout(
        const Duration(seconds: 5),
      );
      if (cancelToken?.isCancelled ?? false) {
        return const UploadResult.failure(FailureType.unknown);
      }

      if (streamedResponse.statusCode == 200) {
        return const UploadResult.success();
      } else {
        return const UploadResult.failure(FailureType.serverError);
      }
    } catch (e) {
      return const UploadResult.failure(FailureType.network);
    }
  }
}

@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((taskName, inputData) async {
    WidgetsFlutterBinding.ensureInitialized();
    if (taskName == AndroidBackgroundRunner.taskName) {
      final queue = UploadQueue(adapter: MockUploadAdapter());
      final hasPending = await BackgroundTaskRunner.run(queue);
      if (hasPending) await AndroidBackgroundRunner.scheduleNextRun();
      return true;
    }
    return false;
  });
}

final uploadQueue = UploadQueue(
  adapter:
      ExampleRestAdapter(), // Using real network adapter to talk to mock server
  wifiOnly: false,
  maxAttempts: 4,
  advanced: UploadQueueAdvancedOptions(
    diskUsageWarningBytes: 50 * 1024 * 1024, // 50 MB
    onDiskUsageWarning: (current, limit) {
      final msg = '⚠️ Disk uyarısı: $current / $limit byte';
      debugPrint(msg);
      globalLogsNotifier.value = [
        ...globalLogsNotifier.value,
        '[WARNING] $msg',
      ];
    },
    onLog: (message, {required level}) {
      if (level == LogLevel.warning || level == LogLevel.error) {
        debugPrint('[${level.name.toUpperCase()}] $message');
      }
      globalLogsNotifier.value = [
        ...globalLogsNotifier.value,
        '[${level.name.toUpperCase()}] $message',
      ];
    },
    heartbeatInterval: const Duration(seconds: 5),
    staleLockThreshold: const Duration(seconds: 15),
  ),
);

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  Workmanager().initialize(callbackDispatcher);

  // FutureBuilder içinde çağrılacak
  // uploadQueue.init() burada çağrılmıyor.

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
  late final Future<void> _initFuture;

  @override
  void initState() {
    super.initState();
    _initFuture = uploadQueue.init();
  }

  late final _screens = [
    const QueueScreen(),
    const CellularScreen(),
    const ErrorScreen(),
    const DiskScreen(),
    DebugScreen(uploadQueue: uploadQueue),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: FutureBuilder(
        future: _initFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Kuyruk başlatılıyor... (Kilit bekleniyor olabilir)'),
                ],
              ),
            );
          }
          if (snapshot.hasError) {
            return Center(child: Text('Hata: ${snapshot.error}'));
          }
          return _screens[_selectedIndex];
        },
      ),
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
          NavigationDestination(
            icon: Icon(Icons.bug_report_outlined),
            selectedIcon: Icon(Icons.bug_report),
            label: 'Debug',
          ),
        ],
      ),
    );
  }
}
