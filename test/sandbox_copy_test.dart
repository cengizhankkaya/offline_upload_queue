import 'dart:async';
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

  // ── §5.6 — completed → sandbox kopyası siliniyor ───────────────────────────

  test(
    '5.6 task completed olduğunda sandbox kopyası diskten siliniyor',
    () async {
      final repo = InMemoryPersistenceRepository();
      final adapter = MockUploadAdapter.alwaysSuccess();
      final monitor = MockConnectivityMonitor();
      final completedCompleter = Completer<void>();

      final sourceFile = File('${tempDir.path}/source_5_6.txt');
      await sourceFile.writeAsBytes(List.filled(64, 0xAB));

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
        copyToSandbox: true, // ← sandbox kopyalama aktif
        boxName: 'test_sandbox_56',
        advanced: const UploadQueueAdvancedOptions(
          staleLockThreshold: Duration(milliseconds: 200),
          heartbeatInterval: Duration(milliseconds: 50),
        ),
      );
      await controller.init();

      final taskId = await controller.enqueue(filePath: sourceFile.path);

      // Sandbox kopyasının yolu
      final sandboxDir = Directory('${tempDir.path}/test_sandbox_56/sandbox');
      final sandboxFile = File('${sandboxDir.path}/$taskId.txt');

      // Enqueue anında sandbox kopyası oluşmuş olmalı
      expect(
        sandboxFile.existsSync(),
        isTrue,
        reason: 'Sandbox kopyası oluşmalı',
      );

      repo.watchTasks(statuses: {UploadStatus.completed}).listen((tasks) {
        if (tasks.any((t) => t.taskId == taskId) &&
            !completedCompleter.isCompleted) {
          completedCompleter.complete();
        }
      });

      await completedCompleter.future.timeout(const Duration(seconds: 3));

      // markCompleted'dan sonra sandbox silme async olarak devam eder.
      // Stream event'i geldiğinde silme henüz tamamlanmamış olabilir.
      await Future.delayed(const Duration(milliseconds: 200));

      // Upload tamamlandıktan sonra sandbox kopyası silinmiş olmalı
      expect(
        sandboxFile.existsSync(),
        isFalse,
        reason: 'completed sonrası sandbox kopyası silinmeli',
      );
      // Orijinal dosya hâlâ var olmalı
      expect(sourceFile.existsSync(), isTrue);

      await controller.dispose();
      QueueController.resetForTesting('test_sandbox_56');
      await repo.dispose();
      monitor.dispose();
    },
  );

  // ── §5.7 — permanentlyFailed/cancelled → sandbox korunuyor ────────────────

  test(
    '5.7 task permanentlyFailed olduğunda sandbox kopyası purge() çağrılana kadar korunuyor',
    () async {
      final repo = InMemoryPersistenceRepository();
      final adapter = MockUploadAdapter.alwaysFailure(FailureType.fileNotFound);
      final monitor = MockConnectivityMonitor();
      final pfCompleter = Completer<void>();

      final sourceFile = File('${tempDir.path}/source_5_7.txt');
      await sourceFile.writeAsBytes(List.filled(32, 0xCD));

      final controller = QueueController(
        repository: repo,
        adapter: adapter,
        retryPolicy: RetryPolicy(
          maxAttempts: 1,
          backoff: BackoffStrategy.fixed(const Duration(milliseconds: 10)),
        ),
        connectivityMonitor: monitor,
        wifiOnly: false,
        verifyChecksum: false,
        copyToSandbox: true,
        boxName: 'test_sandbox_57',
        advanced: const UploadQueueAdvancedOptions(
          staleLockThreshold: Duration(milliseconds: 200),
          heartbeatInterval: Duration(milliseconds: 50),
        ),
      );
      await controller.init();

      final taskId = await controller.enqueue(filePath: sourceFile.path);

      final sandboxDir = Directory('${tempDir.path}/test_sandbox_57/sandbox');
      final sandboxFile = File('${sandboxDir.path}/$taskId.txt');
      expect(sandboxFile.existsSync(), isTrue);

      repo.watchTasks(statuses: {UploadStatus.permanentlyFailed}).listen((
        tasks,
      ) {
        if (tasks.any((t) => t.taskId == taskId) && !pfCompleter.isCompleted) {
          pfCompleter.complete();
        }
      });

      await pfCompleter.future.timeout(const Duration(seconds: 3));

      // permanentlyFailed sonrası sandbox kopyası KORUNMALI
      expect(
        sandboxFile.existsSync(),
        isTrue,
        reason: 'permanentlyFailed sonrası sandbox dosyası silinmemeli',
      );

      await controller.dispose();
      QueueController.resetForTesting('test_sandbox_57');
      await repo.dispose();
      monitor.dispose();
    },
  );

  // ── §5.2 — copyToSandbox:false, dosya silinirse → corruptFile ─────────────

  test(
    '5.2 copyToSandbox:false, orijinal dosya enqueue sonrası silinirse → corruptFile (3 checksum hatasında)',
    () async {
      final repo = InMemoryPersistenceRepository();
      final adapter = MockUploadAdapter.alwaysSuccess();
      final monitor = MockConnectivityMonitor();
      final pfCompleter = Completer<void>();

      // Dosya enqueue anında var
      final sourceFile = File('${tempDir.path}/source_5_2.txt');
      await sourceFile.writeAsBytes([0x01, 0x02, 0x03]);

      final controller = QueueController(
        repository: repo,
        adapter: adapter,
        retryPolicy: RetryPolicy(
          maxAttempts: 6,
          backoff: BackoffStrategy.fixed(const Duration(milliseconds: 5)),
        ),
        connectivityMonitor: monitor,
        wifiOnly: false,
        verifyChecksum: false,
        copyToSandbox: false, // ← sandbox yok
        boxName: 'test_sandbox_52',
        advanced: const UploadQueueAdvancedOptions(
          staleLockThreshold: Duration(milliseconds: 200),
          heartbeatInterval: Duration(milliseconds: 50),
        ),
      );
      await controller.init();

      // Enqueue: dosya var → geçti
      final taskId = await controller.enqueue(filePath: sourceFile.path);

      // Upload başlamadan önce orijinal dosyayı sil
      await sourceFile.delete();

      repo.watchTasks(statuses: {UploadStatus.permanentlyFailed}).listen((
        tasks,
      ) {
        if (tasks.any((t) => t.taskId == taskId) && !pfCompleter.isCompleted) {
          pfCompleter.complete();
        }
      });
      controller.triggerWorkerForTesting();

      await pfCompleter.future.timeout(const Duration(seconds: 5));

      // copyToSandbox:false + dosya silindi → checksum 3 kez başarısız → corruptFile
      expect(repo.taskFor(taskId)?.status, UploadStatus.permanentlyFailed);
      expect(
        repo.taskFor(taskId)?.failureType,
        FailureType.corruptFile,
        reason: '3 checksum hatasından sonra corruptFile olmalı',
      );
      // Upload hiç denenmedi (checksum aşamasında takıldı)
      expect(adapter.callCount, 0);

      await controller.dispose();
      QueueController.resetForTesting('test_sandbox_52');
      await repo.dispose();
      monitor.dispose();
    },
  );
}
