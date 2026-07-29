/// §1 Backoff & Retry + §4 FailureType testleri.
///
/// Bu dosyadaki testlerin büyük çoğunluğu senkron veya Completer tabanlıdır
/// — gerçek `Future.delayed` kullanılmaz.
///
/// CI filtreleme: `flutter test test/backoff_retry_test.dart`
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:offline_upload_queue/offline_upload_queue.dart';
import 'package:offline_upload_queue/src/queue/queue_controller.dart';

import 'helpers/in_memory_persistence_repository.dart';
import 'offline_upload_queue_test.dart';

void main() {
  late InMemoryPersistenceRepository repo;
  late MockConnectivityMonitor monitor;
  late File fakeFile;
  late String fakeFilePath;

  setUp(() async {
    repo = InMemoryPersistenceRepository();
    monitor = MockConnectivityMonitor(ConnectivityStatus.wifi);
    fakeFile = File(
      '${Directory.systemTemp.path}/br_${DateTime.now().microsecondsSinceEpoch}.jpg',
    )..writeAsBytesSync([0x00, 0x01, 0x02]);
    fakeFilePath = fakeFile.path;
  });

  tearDown(() async {
    QueueController.resetForTesting('test');
    await repo.dispose();
    monitor.dispose();
    if (fakeFile.existsSync()) fakeFile.deleteSync();
  });

  // ── §1 Backoff & Retry ────────────────────────────────────────────────────

  group('§1 Backoff & Retry', () {
    // ── §1.1 ─────────────────────────────────────────────────────────────────
    test(
      '1.1 maxAttempts=6 sürekli network hatası → permanentlyFailed, adapter 6 kez çağrıldı',
      () async {
        final adapter = MockUploadAdapter.alwaysFailure(FailureType.network);
        final completer = Completer<void>();

        final controller = makeController(
          adapter: adapter,
          monitor: monitor,
          repo: repo,
          maxAttempts: 6,
          backoff: BackoffStrategy.fixed(const Duration(milliseconds: 5)),
        );
        await controller.init();

        await repo.enqueue(taskId: 'task-1-1', filePath: fakeFilePath);
        repo.watchTasks(statuses: {UploadStatus.permanentlyFailed}).listen((
          tasks,
        ) {
          if (tasks.any((t) => t.taskId == 'task-1-1') &&
              !completer.isCompleted) {
            completer.complete();
          }
        });
        controller.triggerWorkerForTesting();

        await completer.future.timeout(const Duration(seconds: 5));

        expect(
          repo.taskFor('task-1-1')?.status,
          UploadStatus.permanentlyFailed,
        );
        // maxAttempts=6: adapter tam 6 kez çağrılmış olmalı
        expect(adapter.callCount, 6);

        await controller.dispose();
      },
    );

    // ── §1.2 ─────────────────────────────────────────────────────────────────
    test(
      '1.2 Exponential backoff: yüksek retryCount\'ta max (10 dk) sınırı aşılmıyor',
      () {
        final policy = RetryPolicy(
          maxAttempts: 30,
          backoff: BackoffStrategy.exponential(
            base: const Duration(seconds: 2),
            max: const Duration(minutes: 10),
          ),
        );
        final now = DateTime(2024, 1, 1);
        const maxMs = 10 * 60 * 1000; // 10 dakika ms

        for (var i = 0; i < 25; i++) {
          final next = policy.nextRetryAt(
            retryCount: i,
            failureType: FailureType.network,
            from: now,
          );
          expect(
            next!.difference(now).inMilliseconds,
            lessThanOrEqualTo(maxMs),
            reason: 'retryCount=$i için max (10dk) aşıldı',
          );
          // Pozitif süre
          expect(next.difference(now).inMilliseconds, greaterThanOrEqualTo(0));
        }
      },
    );

    // ── §1.3 ─────────────────────────────────────────────────────────────────
    test('1.3 Jitter: tekrarlanan compute() çağrıları farklı süreler üretir', () {
      final policy = RetryPolicy(
        maxAttempts: 6,
        backoff: BackoffStrategy.exponential(
          base: const Duration(seconds: 2),
          max: const Duration(minutes: 10),
        ),
      );
      final now = DateTime(2024, 1, 1);

      // 50 çağrıda en az 2 farklı sonuç olmalı → jitter var
      final results = List.generate(50, (_) {
        return policy
            .nextRetryAt(
              retryCount: 0,
              failureType: FailureType.network,
              from: now,
            )!
            .difference(now)
            .inMilliseconds;
      }).toSet();

      expect(
        results.length,
        greaterThan(1),
        reason:
            'Jitter olmadan tüm değerler aynı olur; farklı değerler bekleniyor',
      );
    });

    // ── §1.4 ─────────────────────────────────────────────────────────────────
    test('1.4 FixedBackoff: her retryCount için aynı süre döner', () {
      const fixedDuration = Duration(seconds: 7);
      final policy = RetryPolicy(
        maxAttempts: 6,
        backoff: BackoffStrategy.fixed(fixedDuration),
      );
      final now = DateTime(2024, 1, 1);

      final results = List.generate(10, (i) {
        return policy
            .nextRetryAt(
              retryCount: i,
              failureType: FailureType.network,
              from: now,
            )!
            .difference(now)
            .inMilliseconds;
      }).toSet();

      // Tüm sonuçlar aynı olmalı (7000 ms)
      expect(results, equals({fixedDuration.inMilliseconds}));
    });

    // ── §1.6 ─────────────────────────────────────────────────────────────────
    test(
      '1.6 retry() sonrası eski task yeni task\'tan önce işleniyor (sequenceNumber korunur)',
      () async {
        // task-a (seq=1) permanentlyFailed → retry() → pending
        // task-c (seq=3) yeni eklendi
        // getNextPending → task-a döner (seq=1 < seq=3) → önce işlenir
        await repo.enqueue(taskId: 'task-a', filePath: fakeFilePath);
        await repo.markPermanentlyFailed(
          'task-a',
          failureType: FailureType.fileNotFound,
        );
        await repo.enqueue(taskId: 'task-c', filePath: fakeFilePath);

        // retry → pending (retryCount sıfırlanır, sequenceNumber korunur)
        await repo.markPending('task-a');

        final task = await repo.getNextPending(DateTime.now());
        expect(
          task?.taskId,
          'task-a',
          reason: 'Eski task (seq=1) önce alınmalı',
        );
      },
    );

    // ── §1.8 ─────────────────────────────────────────────────────────────────
    test(
      '1.8 cancelled task retry() → pending → upload tamamlanıyor',
      () async {
        final adapter = MockUploadAdapter.alwaysSuccess();
        final completedCompleter = Completer<void>();

        final controller = makeController(
          adapter: adapter,
          monitor: monitor,
          repo: repo,
          maxAttempts: 3,
        );
        await repo.enqueue(taskId: 'cancelled-retry', filePath: fakeFilePath);
        await repo.markCancelled('cancelled-retry');

        await controller.init();

        expect(repo.taskFor('cancelled-retry')?.status, UploadStatus.cancelled);

        repo.watchTasks(statuses: {UploadStatus.completed}).listen((tasks) {
          if (tasks.any((t) => t.taskId == 'cancelled-retry') &&
              !completedCompleter.isCompleted) {
            completedCompleter.complete();
          }
        });

        await controller.retry('cancelled-retry');
        await completedCompleter.future.timeout(const Duration(seconds: 2));

        expect(repo.taskFor('cancelled-retry')?.status, UploadStatus.completed);

        await controller.dispose();
      },
    );

    // ── §1.9 ─────────────────────────────────────────────────────────────────
    test(
      '1.9 pause() backoff penceresi içindeyken resume() → nextRetryAt korunuyor',
      () async {
        final adapter = MockUploadAdapter.alwaysFailure(FailureType.network);
        final failedCompleter = Completer<void>();

        final controller = makeController(
          adapter: adapter,
          monitor: monitor,
          repo: repo,
          maxAttempts: 6,
          // Çok uzun backoff → resume() sonrası da task işlenmemeli
          backoff: BackoffStrategy.fixed(const Duration(hours: 1)),
        );
        await controller.init();

        await repo.enqueue(taskId: 'backoff-pause', filePath: fakeFilePath);
        repo.watchTasks(statuses: {UploadStatus.failed}).listen((tasks) {
          if (tasks.any((t) => t.taskId == 'backoff-pause') &&
              !failedCompleter.isCompleted) {
            failedCompleter.complete();
          }
        });
        controller.triggerWorkerForTesting();
        await failedCompleter.future.timeout(const Duration(seconds: 2));

        final nextRetryBefore = repo.taskFor('backoff-pause')!.nextRetryAt;
        expect(nextRetryBefore, isNotNull);

        // pause() → resume() → nextRetryAt değişmemeli, task işlenmemeli
        controller.pause();
        controller.resume();
        await Future.delayed(const Duration(milliseconds: 100));

        final taskAfter = repo.taskFor('backoff-pause')!;
        expect(
          taskAfter.status,
          UploadStatus.failed,
          reason: 'Backoff devam ediyor',
        );
        expect(
          taskAfter.nextRetryAt,
          equals(nextRetryBefore),
          reason: 'nextRetryAt sıfırlanmamalı',
        );

        await controller.dispose();
      },
    );
  });

  // ── §4 FailureType ────────────────────────────────────────────────────────

  group('§4 FailureType', () {
    // ── §4.8 ─────────────────────────────────────────────────────────────────
    test(
      '4.8 dosya 3 checksum hatasında corruptFile (kalıcı) — adapter hiç çağrılmaz',
      () async {
        // Var olmayan dosya yolu: checksum hesabı başarısız olacak
        const nonExistentPath = '/tmp/__br_nonexistent_xyz_abc.jpg';
        final adapter = MockUploadAdapter.alwaysSuccess();
        final completer = Completer<void>();

        final controller = makeController(
          adapter: adapter,
          monitor: monitor,
          repo: repo,
          maxAttempts: 6,
          backoff: BackoffStrategy.fixed(const Duration(milliseconds: 5)),
        );
        await controller.init();

        // repo.enqueue() doğrudan → dosya varlık kontrolü atlanır
        await repo.enqueue(taskId: 'corrupt-task', filePath: nonExistentPath);
        repo.watchTasks(statuses: {UploadStatus.permanentlyFailed}).listen((
          tasks,
        ) {
          if (tasks.any((t) => t.taskId == 'corrupt-task') &&
              !completer.isCompleted) {
            completer.complete();
          }
        });
        controller.triggerWorkerForTesting();

        await completer.future.timeout(const Duration(seconds: 5));

        final task = repo.taskFor('corrupt-task')!;
        expect(task.status, UploadStatus.permanentlyFailed);
        expect(
          task.failureType,
          FailureType.corruptFile,
          reason: '3 checksum hatasından sonra corruptFile olmalı',
        );
        // Checksum aşamasında takıldığından adapter hiç çağrılmadı
        expect(adapter.callCount, 0);

        await controller.dispose();
      },
    );

    // ── §4.13 ────────────────────────────────────────────────────────────────
    test('4.13 permanentlyFailed → otomatik retry denenmez', () async {
      final adapter = MockUploadAdapter.alwaysFailure(FailureType.fileNotFound);
      final pfCompleter = Completer<void>();

      final controller = makeController(
        adapter: adapter,
        monitor: monitor,
        repo: repo,
        maxAttempts: 6,
      );
      await controller.init();

      await repo.enqueue(taskId: 'pf-no-auto', filePath: fakeFilePath);
      repo.watchTasks(statuses: {UploadStatus.permanentlyFailed}).listen((
        tasks,
      ) {
        if (tasks.any((t) => t.taskId == 'pf-no-auto') &&
            !pfCompleter.isCompleted) {
          pfCompleter.complete();
        }
      });
      controller.triggerWorkerForTesting();
      await pfCompleter.future.timeout(const Duration(seconds: 2));

      final callCountAtFail = adapter.callCount;

      // Ek bekleme süresi — otomatik retry olsaydı callCount artardı
      await Future.delayed(const Duration(milliseconds: 300));

      expect(
        adapter.callCount,
        callCountAtFail,
        reason: 'permanentlyFailed sonrası otomatik retry denenmemeli',
      );
      expect(adapter.callCount, 1, reason: 'Kalıcı hata → yalnızca 1 deneme');

      await controller.dispose();
    });

    // ── §4 Sınır Testleri ─────────────────────────────────────────────────────
    test(
      '4 RetryPolicy: rateLimited + retryAfter → backend\'in verdiği süre kullanılır',
      () {
        final policy = RetryPolicy(
          maxAttempts: 6,
          backoff: BackoffStrategy.fixed(const Duration(seconds: 10)),
        );
        final now = DateTime(2024, 6, 1, 12, 0, 0);
        const serverRetryAfter = Duration(seconds: 90);

        final next = policy.nextRetryAt(
          retryCount: 0,
          failureType: FailureType.rateLimited,
          retryAfter: serverRetryAfter,
          from: now,
        );

        // backoff stratejisi değil, serverRetryAfter kullanılmalı (90s)
        expect(next, equals(now.add(serverRetryAfter)));
        expect(
          next!.difference(now).inSeconds,
          90,
          reason: 'Retry-After header değeri kullanılmalı',
        );
      },
    );

    test(
      '4 RetryPolicy: rateLimited + retryAfter yok → fallback backoff stratejisi devreye girer',
      () {
        const fixedDuration = Duration(seconds: 15);
        final policy = RetryPolicy(
          maxAttempts: 6,
          backoff: BackoffStrategy.fixed(fixedDuration),
        );
        final now = DateTime(2024, 6, 1, 12, 0, 0);

        final next = policy.nextRetryAt(
          retryCount: 0,
          failureType: FailureType.rateLimited,
          retryAfter: null, // header yok
          from: now,
        );

        // Fallback: fixed backoff stratejisi kullanılmalı
        expect(next, equals(now.add(fixedDuration)));
      },
    );
  });
}
