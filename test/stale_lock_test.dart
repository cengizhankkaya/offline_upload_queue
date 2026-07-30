/// §2 Crash / Kill Simülasyonu ve Stale Lock testleri.
///
/// InMemoryPersistenceRepository'nin `tryAcquireLock()` her zaman `true`
/// döndürdüğünden, stale lock senaryoları `StaleLockMockRepository` ile
/// simüle edilir.
///
/// CI filtreleme: `flutter test test/stale_lock_test.dart`
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:offline_upload_queue/offline_upload_queue.dart';
import 'package:offline_upload_queue/src/queue/queue_controller.dart';

import 'helpers/in_memory_persistence_repository.dart';
import 'helpers/stale_lock_mock_repository.dart';
import 'offline_upload_queue_test.dart';

/// Stale lock testleri için `QueueController` oluşturucu.
///
/// Heartbeat ve staleLock eşiği kısa tutulmuştur (test performansı için).
QueueController makeStaleLockController({
  required StaleLockMockRepository repo,
  required MockConnectivityMonitor monitor,
  required MockUploadAdapter adapter,
  String boxName = 'stale-lock-test',
}) {
  return QueueController(
    repository: repo,
    adapter: adapter,
    retryPolicy: RetryPolicy(
      maxAttempts: 3,
      backoff: BackoffStrategy.fixed(const Duration(milliseconds: 5)),
    ),
    connectivityMonitor: monitor,
    wifiOnly: false,
    verifyChecksum: false,
    copyToSandbox: false,
    boxName: boxName,
    advanced: const UploadQueueAdvancedOptions(
      // staleLockThreshold >= heartbeatInterval * 3 kısıtı:
      // 50ms >= 15ms * 3 = 45ms ✓
      heartbeatInterval: Duration(milliseconds: 15),
      staleLockThreshold: Duration(milliseconds: 50),
    ),
  );
}

void main() {
  late MockConnectivityMonitor monitor;
  late MockUploadAdapter adapter;
  late File fakeFile;
  late String fakeFilePath;

  setUp(() async {
    monitor = MockConnectivityMonitor(ConnectivityStatus.wifi);
    adapter = MockUploadAdapter.alwaysSuccess();
    fakeFile = File(
      '${Directory.systemTemp.path}/sl_${DateTime.now().microsecondsSinceEpoch}.jpg',
    )..writeAsBytesSync([0x00, 0x01]);
    fakeFilePath = fakeFile.path;
  });

  tearDown(() async {
    monitor.dispose();
    if (fakeFile.existsSync()) fakeFile.deleteSync();
    QueueController.resetForTesting('stale-lock-test');
  });

  // ── §2.1 ──────────────────────────────────────────────────────────────────

  test(
    '2.1 Stale lock: ikinci controller kilidi devralıyor ve task\'ı işliyor',
    () async {
      // İlk 1 tryAcquireLock çağrısında false dön (başka worker kilit tutuyor)
      // 15ms sonra watchLockUpdates'e event → ikinci çağrıda true
      final repo = StaleLockMockRepository(
        callsBeforeSuccess: 1,
        releaseDelay: const Duration(milliseconds: 20),
      );

      await repo.enqueue(taskId: 'stale-task', filePath: fakeFilePath);

      final completedCompleter = Completer<void>();
      repo.watchTasks(statuses: {UploadStatus.completed}).listen((tasks) {
        if (tasks.any((t) => t.taskId == 'stale-task') &&
            !completedCompleter.isCompleted) {
          completedCompleter.complete();
        }
      });

      final controller = makeStaleLockController(
        repo: repo,
        monitor: monitor,
        adapter: adapter,
      );

      // init() lock alana kadar bloklar (stale threshold dolunca devralır)
      await controller.init();

      await completedCompleter.future.timeout(const Duration(seconds: 3));

      // Kilit en az 2 kez denenmiş olmalı (1 fail + 1 success)
      expect(repo.acquireCallCount, greaterThanOrEqualTo(2));
      expect(repo.taskFor('stale-task')?.status, UploadStatus.completed);

      await controller.dispose();
      await repo.dispose();
    },
    timeout: const Timeout(Duration(seconds: 10)),
  );

  // ── §2.3 ──────────────────────────────────────────────────────────────────

  test(
    '2.3 Taze heartbeat: lock update sinyali olmadan task işlenmiyor',
    () async {
      // İlk çağrı başarısız, lock update eventi YOK (NeverAcquiresLockRepository)
      final repo = NeverAcquiresLockRepository();

      await repo.enqueue(taskId: 'blocked-task', filePath: fakeFilePath);

      final controller = QueueController(
        repository: repo,
        adapter: adapter,
        retryPolicy: RetryPolicy(
          maxAttempts: 3,
          backoff: BackoffStrategy.fixed(const Duration(milliseconds: 5)),
        ),
        connectivityMonitor: monitor,
        wifiOnly: false,
        verifyChecksum: false,
        copyToSandbox: false,
        boxName: 'never-lock-test',
        advanced: const UploadQueueAdvancedOptions(
          heartbeatInterval: Duration(milliseconds: 15),
          staleLockThreshold: Duration(milliseconds: 50),
        ),
      );

      // init() kilidi hiç alamaz — timeout ile iptal ediyoruz
      bool initCompleted = false;
      final initFuture = controller.init().then((_) {
        initCompleted = true;
      });

      // 200ms boyunca init() tamamlanmamalı (lock alınamıyor)
      await Future.delayed(const Duration(milliseconds: 200));

      expect(initCompleted, isFalse, reason: 'Kilit hiç alınamamalı');
      // Task işlenmemiş olmalı
      expect(repo.taskFor('blocked-task')?.status, UploadStatus.pending);
      expect(adapter.callCount, 0);

      // Cleanup: controller'ı dispose et (bu da init'i çıkaracak)
      controller
          .dispose()
          .ignore(); // disposed flag'i set eder, lock while exit
      await initFuture.timeout(
        const Duration(seconds: 2),
        onTimeout: () {}, // timeout normal
      );
      QueueController.resetForTesting('never-lock-test');
      await repo.dispose();
    },
    timeout: const Timeout(Duration(seconds: 5)),
  );

  // ── §2.7 ──────────────────────────────────────────────────────────────────

  test(
    '2.7 Kilit devralınırken task silinmişse → crash olmadan graceful',
    () async {
      final repo = InMemoryPersistenceRepository();

      // Task eklendi ama worker başlamadan önce silindi
      await repo.enqueue(taskId: 'ghost-task', filePath: fakeFilePath);
      await repo.markCancelled('ghost-task');
      await repo.purge('ghost-task');

      final controller = makeController(
        adapter: adapter,
        monitor: monitor,
        repo: repo,
        maxAttempts: 3,
      );
      await controller.init();
      controller.triggerWorkerForTesting();

      // Kısa bekleme — task yoksa getNextPending() null döner, crash yok
      await Future.delayed(const Duration(milliseconds: 100));

      expect(
        repo.taskFor('ghost-task'),
        isNull,
        reason: 'Task silinmiş olmalı',
      );
      expect(
        adapter.callCount,
        0,
        reason: 'Silinmiş task için upload denenmemeli',
      );

      await controller.dispose();
      await repo.dispose();
    },
  );

  // ── §2.5 (var olan kural doğrulaması) ─────────────────────────────────────

  test(
    '2.5 staleLockThreshold < heartbeatInterval × 3 → ArgumentError (regresyon)',
    () {
      final repo = InMemoryPersistenceRepository();
      final c = QueueController(
        repository: repo,
        adapter: adapter,
        retryPolicy: RetryPolicy(
          maxAttempts: 3,
          backoff: BackoffStrategy.fixed(const Duration(seconds: 1)),
        ),
        connectivityMonitor: monitor,
        wifiOnly: false,
        verifyChecksum: false,
        copyToSandbox: false,
        boxName: 'arg-error-box',
        advanced: const UploadQueueAdvancedOptions(
          staleLockThreshold: Duration(seconds: 5),
          heartbeatInterval: Duration(seconds: 10), // 10*3=30 > 5 → hata!
        ),
      );
      expect(
        () => c.init(),
        throwsA(
          isA<ArgumentError>().having(
            (e) => e.message,
            'message',
            contains('staleLockThreshold'),
          ),
        ),
      );
      QueueController.resetForTesting('arg-error-box');
      repo.dispose().ignore();
    },
  );
}
