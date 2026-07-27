import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:offline_upload_queue/offline_upload_queue.dart';
import 'package:offline_upload_queue/src/queue/queue_controller.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'helpers/in_memory_persistence_repository.dart';
import 'offline_upload_queue_test.dart'; // Re-use mock implementations

class MockPathProviderPlatform extends Fake
    with MockPlatformInterfaceMixin
    implements PathProviderPlatform {
  final String tempPath;
  MockPathProviderPlatform(this.tempPath);

  @override
  Future<String?> getApplicationSupportPath() async {
    return tempPath;
  }
}

void main() {
  late Directory tempDir;
  late MockPathProviderPlatform mockPathProvider;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp(
      'offline_queue_sandbox_test',
    );
    mockPathProvider = MockPathProviderPlatform(tempDir.path);
    PathProviderPlatform.instance = mockPathProvider;
  });

  tearDown(() async {
    await tempDir.delete(recursive: true);
    QueueController.resetForTesting('test_sandbox');
  });

  test(
    'sandboxCopyThresholdBytes üzerinde olan dosya kopyalanır (streaming)',
    () async {
      final repo = InMemoryPersistenceRepository();
      final adapter = MockUploadAdapter.alwaysSuccess();
      final monitor = MockConnectivityMonitor();

      // Büyük bir dummy dosya oluştur (> 100 bayt eşiği)
      final sourceFile = File('${tempDir.path}/large_file.txt');
      await sourceFile.writeAsBytes(List.filled(200, 0)); // 200 bayt

      final controller = QueueController(
        repository: repo,
        adapter: adapter,
        retryPolicy: RetryPolicy(
          maxAttempts: 3,
          backoff: BackoffStrategy.fixed(const Duration(milliseconds: 10)),
        ),
        connectivityMonitor: monitor,
        wifiOnly: false,
        verifyChecksum: false,
        copyToSandbox: true,
        boxName: 'test_sandbox',
        advanced: const UploadQueueAdvancedOptions(
          sandboxCopyThresholdBytes: 100, // Eşik çok düşük
        ),
      );

      await controller.init();

      final taskId = await controller.enqueue(filePath: sourceFile.path);

      // Kuyruğa eklendiğinde sandbox klasöründe dosya olmalı
      final sandboxDir = Directory('${tempDir.path}/test_sandbox/sandbox');
      expect(sandboxDir.existsSync(), isTrue);

      final destFile = File('${sandboxDir.path}/$taskId.txt');
      expect(destFile.existsSync(), isTrue);
      expect((await destFile.stat()).size, 200);

      await controller.dispose();
    },
  );

  test(
    'sandboxCopyThresholdBytes altında olan dosya kopyalanır (standart/hardlink)',
    () async {
      final repo = InMemoryPersistenceRepository();
      final adapter = MockUploadAdapter.alwaysSuccess();
      final monitor = MockConnectivityMonitor();

      // Küçük bir dummy dosya oluştur (< 100 bayt eşiği)
      final sourceFile = File('${tempDir.path}/small_file.txt');
      await sourceFile.writeAsBytes(List.filled(50, 0)); // 50 bayt

      final controller = QueueController(
        repository: repo,
        adapter: adapter,
        retryPolicy: RetryPolicy(
          maxAttempts: 3,
          backoff: BackoffStrategy.fixed(const Duration(milliseconds: 10)),
        ),
        connectivityMonitor: monitor,
        wifiOnly: false,
        verifyChecksum: false,
        copyToSandbox: true,
        boxName: 'test_sandbox',
        advanced: const UploadQueueAdvancedOptions(
          sandboxCopyThresholdBytes: 100,
        ),
      );

      await controller.init();

      final taskId = await controller.enqueue(filePath: sourceFile.path);

      final sandboxDir = Directory('${tempDir.path}/test_sandbox/sandbox');
      final destFile = File('${sandboxDir.path}/$taskId.txt');
      expect(destFile.existsSync(), isTrue);
      expect((await destFile.stat()).size, 50);

      await controller.dispose();
    },
  );
}
