/// §7.3 + §8 + §10 + §11 — Yaşam döngüsü, auth, stream ve forceUploadOnce testleri.
///
/// CI filtreleme: `flutter test test/lifecycle_api_test.dart`
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
      '${Directory.systemTemp.path}/lc_${DateTime.now().microsecondsSinceEpoch}.jpg',
    )..writeAsBytesSync([0x00, 0x01, 0x02]);
    fakeFilePath = fakeFile.path;
  });

  tearDown(() async {
    QueueController.resetForTesting('test');
    await repo.dispose();
    monitor.dispose();
    if (fakeFile.existsSync()) fakeFile.deleteSync();
  });

  // ── §7. forceUploadOnce ───────────────────────────────────────────────────

  group('§7 forceUploadOnce', () {
    // §7.3
    test(
      '7.3 forceUploadOnce() snapshot alındıktan sonra enqueue → yeni task wifi bekler',
      () async {
        monitor.setStatus(ConnectivityStatus.cellular);
        final aCompletedCompleter = Completer<void>();

        final adapter = MockUploadAdapter([
          const UploadResult.success(),
          const UploadResult.success(),
        ]);

        final controller = makeController(
          adapter: adapter,
          monitor: monitor,
          repo: repo,
          wifiOnly: true,
        );
        await controller.init();

        // task-a: snapshot'a girecek (forceUploadOnce öncesi pending)
        await repo.enqueue(taskId: 'force-a', filePath: fakeFilePath);

        // Snapshot al (task-a dahil)
        await controller.forceUploadOnce();

        // Snapshot SONRASI task-b eklendi — snapshot'a girmemeli
        await repo.enqueue(taskId: 'force-b', filePath: fakeFilePath);

        repo.watchTasks(statuses: {UploadStatus.completed}).listen((tasks) {
          if (tasks.any((t) => t.taskId == 'force-a') &&
              !aCompletedCompleter.isCompleted) {
            aCompletedCompleter.complete();
          }
        });

        await aCompletedCompleter.future.timeout(const Duration(seconds: 3));

        // task-a tamamlandı
        expect(repo.taskFor('force-a')?.status, UploadStatus.completed);

        // task-b hâlâ pending: snapshot dışında, wifi bekliyor
        await Future.delayed(const Duration(milliseconds: 150));
        expect(
          repo.taskFor('force-b')?.status,
          UploadStatus.pending,
          reason:
              'Snapshot sonrası eklenen task, cellular\'da wifi bekliyor olmalı',
        );

        await controller.dispose();
      },
    );
  });

  // ── §8. Auth Expiry ───────────────────────────────────────────────────────

  group('§8 Auth Expiry', () {
    // §8.1
    test(
      '8.1 authExpired → onAuthExpired başarılı → task re-queued ve tamamlanıyor',
      () async {
        var authCallCount = 0;
        final completedCompleter = Completer<void>();

        final adapter = MockUploadAdapter([
          UploadResult.failure(FailureType.authExpired),
          const UploadResult.success(),
        ]);

        final controller = makeController(
          adapter: adapter,
          monitor: monitor,
          repo: repo,
          maxAttempts: 3,
          onAuthExpired: () async {
            authCallCount++;
            // Token yenilendi — başarılı
          },
        );
        await controller.init();

        await repo.enqueue(taskId: 'auth-ok', filePath: fakeFilePath);
        repo.watchTasks(statuses: {UploadStatus.completed}).listen((tasks) {
          if (tasks.any((t) => t.taskId == 'auth-ok') &&
              !completedCompleter.isCompleted) {
            completedCompleter.complete();
          }
        });
        controller.triggerWorkerForTesting();

        await completedCompleter.future.timeout(const Duration(seconds: 3));

        expect(repo.taskFor('auth-ok')?.status, UploadStatus.completed);
        expect(
          authCallCount,
          1,
          reason: 'onAuthExpired bir kez çağrılmış olmalı',
        );

        await controller.dispose();
      },
    );

    // §8.2
    test(
      '8.2 onAuthExpired authTimeout\'u aşarsa → failed/backoff akışına düşer',
      () async {
        final failedCompleter = Completer<void>();

        final adapter = MockUploadAdapter.alwaysFailure(
          FailureType.authExpired,
        );

        final controller = makeController(
          adapter: adapter,
          monitor: monitor,
          repo: repo,
          maxAttempts: 6,
          onAuthExpired: () async {
            // 60 saniye bekler — kısa authTimeout ile timeout alır
            await Future.delayed(const Duration(seconds: 60));
          },
          authTimeout: const Duration(milliseconds: 10),
        );
        await controller.init();

        await repo.enqueue(taskId: 'auth-timeout', filePath: fakeFilePath);
        repo.watchTasks(statuses: {UploadStatus.failed}).listen((tasks) {
          if (tasks.any((t) => t.taskId == 'auth-timeout') &&
              !failedCompleter.isCompleted) {
            failedCompleter.complete();
          }
        });
        controller.triggerWorkerForTesting();

        await failedCompleter.future.timeout(const Duration(seconds: 3));

        // authExpired kalıcı değil → backoff ile failed
        expect(repo.taskFor('auth-timeout')?.status, UploadStatus.failed);
        expect(
          repo.taskFor('auth-timeout')?.failureType,
          FailureType.authExpired,
        );

        await controller.dispose();
      },
    );

    // §8.3
    test(
      '8.3 onAuthExpired exception fırlatırsa → failed/backoff, uygulama crash yok',
      () async {
        final failedCompleter = Completer<void>();

        final adapter = MockUploadAdapter.alwaysFailure(
          FailureType.authExpired,
        );

        final controller = makeController(
          adapter: adapter,
          monitor: monitor,
          repo: repo,
          maxAttempts: 6,
          onAuthExpired: () async {
            throw Exception('Auth sunucusuna ulaşılamıyor');
          },
        );
        await controller.init();

        await repo.enqueue(taskId: 'auth-throw', filePath: fakeFilePath);
        repo.watchTasks(statuses: {UploadStatus.failed}).listen((tasks) {
          if (tasks.any((t) => t.taskId == 'auth-throw') &&
              !failedCompleter.isCompleted) {
            failedCompleter.complete();
          }
        });
        controller.triggerWorkerForTesting();

        // Exception fırlatılsa bile test crash olmamalı
        await expectLater(
          failedCompleter.future.timeout(const Duration(seconds: 3)),
          completes,
        );

        expect(repo.taskFor('auth-throw')?.status, UploadStatus.failed);
        expect(
          repo.taskFor('auth-throw')?.failureType,
          FailureType.authExpired,
        );

        await controller.dispose();
      },
    );

    // §8.4
    test(
      '8.4 İki task aynı anda 401 → onAuthExpired iki kez çağrılır (coalesce yok — belgeleme testi)',
      () async {
        // Davranışı belgeler: mevcut implementasyon coalesce/dedupe YAPMAZ
        // Her authExpired failure için ayrıca çağrılır.
        var authCallCount = 0;

        // Adapter sırayla: authExpired, authExpired, success, success
        final adapter = MockUploadAdapter([
          UploadResult.failure(FailureType.authExpired),
          UploadResult.failure(FailureType.authExpired),
          const UploadResult.success(),
          const UploadResult.success(),
        ]);

        final controller = makeController(
          adapter: adapter,
          monitor: monitor,
          repo: repo,
          maxAttempts: 6,
          backoff: BackoffStrategy.fixed(const Duration(milliseconds: 5)),
          onAuthExpired: () async {
            authCallCount++;
          },
        );
        await controller.init();

        await repo.enqueue(taskId: 'auth-a', filePath: fakeFilePath);
        await repo.enqueue(taskId: 'auth-b', filePath: fakeFilePath);

        final bothCompleted = Completer<void>();
        repo.watchSummary().listen((s) {
          if (s.completed >= 2 && !bothCompleted.isCompleted) {
            bothCompleted.complete();
          }
        });
        controller.triggerWorkerForTesting();

        await bothCompleted.future.timeout(const Duration(seconds: 5));

        // Mevcut davranış: her task kendi authExpired'ını ayrı çağırıyor
        // Bu test bu davranışı kilitler (regresyon guard)
        expect(
          authCallCount,
          2,
          reason:
              'Mevcut implementasyonda coalesce yok — her task için ayrı çağrı',
        );

        await controller.dispose();
      },
    );

    // §8.5
    test(
      '8.5 Token yenilendikten sonra ikinci 401 → maxAttempts sınırına saygı gösterir',
      () async {
        var authCallCount = 0;
        // Her denemede authExpired dönüyor
        final adapter = MockUploadAdapter.alwaysFailure(
          FailureType.authExpired,
        );

        final pfCompleter = Completer<void>();

        final controller = makeController(
          adapter: adapter,
          monitor: monitor,
          repo: repo,
          maxAttempts: 3, // 3 denemede permanentlyFailed
          backoff: BackoffStrategy.fixed(const Duration(milliseconds: 5)),
          onAuthExpired: () async {
            authCallCount++;
            // Her seferinde "yenilendi" ama tekrar 401 geliyor
          },
        );
        await controller.init();

        await repo.enqueue(taskId: 'auth-loop', filePath: fakeFilePath);
        repo.watchTasks(statuses: {UploadStatus.permanentlyFailed}).listen((
          tasks,
        ) {
          if (tasks.any((t) => t.taskId == 'auth-loop') &&
              !pfCompleter.isCompleted) {
            pfCompleter.complete();
          }
        });
        controller.triggerWorkerForTesting();

        await pfCompleter.future.timeout(const Duration(seconds: 5));

        // maxAttempts=3 geçildikten sonra permanentlyFailed olmalı
        expect(
          repo.taskFor('auth-loop')?.status,
          UploadStatus.permanentlyFailed,
        );
        // Sonsuz döngüye girmemeli
        expect(authCallCount, lessThanOrEqualTo(3));

        await controller.dispose();
      },
    );
  });

  // ── §10. Yaşam Döngüsü / API Sözleşmesi ──────────────────────────────────

  group('§10 Yaşam Döngüsü', () {
    // §10.3
    test(
      '10.3 dispose() sonrası enqueue/retry/cancel → StateError fırlatılır',
      () async {
        final controller = makeController(
          adapter: MockUploadAdapter.alwaysSuccess(),
          monitor: monitor,
          repo: repo,
        );
        await controller.init();
        await controller.dispose();

        // dispose sonrası tüm mutasyon metodları StateError fırlatmalı
        await expectLater(
          () => controller.enqueue(filePath: fakeFilePath),
          throwsStateError,
        );
        await expectLater(() => controller.retry('any-id'), throwsStateError);
        await expectLater(() => controller.cancel('any-id'), throwsStateError);
      },
    );

    // §10.5
    test(
      '10.5 pause() in-memory: dispose/restart sonrası isPaused sıfırlanıyor',
      () async {
        final controller1 = makeController(
          adapter: MockUploadAdapter.alwaysSuccess(),
          monitor: monitor,
          repo: repo,
        );
        await controller1.init();
        controller1.pause();

        final summary1 = await controller1.watchSummary().first;
        expect(summary1.isPaused, isTrue);

        await controller1.dispose();
        QueueController.resetForTesting('test');

        // Aynı repo üzerinde yeni controller (restart simülasyonu)
        final controller2 = makeController(
          adapter: MockUploadAdapter.alwaysSuccess(),
          monitor: monitor,
          repo: repo,
        );
        await controller2.init();

        final summary2 = await controller2.watchSummary().first;
        expect(
          summary2.isPaused,
          isFalse,
          reason: 'pause() in-memory; restart sonrası sıfırlanmalı',
        );

        await controller2.dispose();
      },
    );
  });

  // ── §11. Reaktif Stream'ler ───────────────────────────────────────────────

  group('§11 Reaktif Streamler', () {
    // §11.3
    test(
      '11.3 watchProgress: InMemoryRepo üzerinde 0.0→1.0 artan değerler',
      () async {
        final values = <double>[];
        final doneCompleter = Completer<void>();
        final freshRepo = InMemoryPersistenceRepository();

        await freshRepo.enqueue(taskId: 'prog-task', filePath: fakeFilePath);

        final sub = freshRepo.watchProgress('prog-task').listen((p) {
          values.add(p);
          if (values.length >= 4) doneCompleter.complete();
        });

        // Sıralı progress güncellemeleri
        freshRepo.updateProgress('prog-task', 0.25);
        freshRepo.updateProgress('prog-task', 0.50);
        freshRepo.updateProgress('prog-task', 0.75);
        freshRepo.updateProgress('prog-task', 1.0);

        await doneCompleter.future.timeout(const Duration(seconds: 2));
        await sub.cancel();

        expect(values, equals([0.25, 0.50, 0.75, 1.0]));

        // Monoton artış
        for (var i = 1; i < values.length; i++) {
          expect(
            values[i],
            greaterThanOrEqualTo(values[i - 1]),
            reason: 'Progress geri gitmemeli',
          );
        }

        await freshRepo.dispose();
      },
    );

    // §11.4
    test(
      '11.4 watchProgress var olmayan task → boş stream (değer yayınlanmaz)',
      () async {
        final freshRepo = InMemoryPersistenceRepository();

        final received = <double>[];
        final sub = freshRepo
            .watchProgress('nonexistent-task')
            .listen(received.add);

        await Future.delayed(const Duration(milliseconds: 100));
        await sub.cancel();

        expect(
          received,
          isEmpty,
          reason: 'Var olmayan task için değer yayınlanmamalı',
        );

        await freshRepo.dispose();
      },
    );

    // §11.5
    test(
      '11.5 watchSummary: birden fazla dinleyici aynı eventleri alıyor (broadcast)',
      () async {
        final freshRepo = InMemoryPersistenceRepository();
        final events1 = <QueueSummary>[];
        final events2 = <QueueSummary>[];

        final sub1 = freshRepo.watchSummary().listen(events1.add);
        final sub2 = freshRepo.watchSummary().listen(events2.add);

        // İki enqueue → her stream'e 2 ek event gitmeli
        await freshRepo.enqueue(taskId: 't-a', filePath: fakeFilePath);
        await freshRepo.enqueue(taskId: 't-b', filePath: fakeFilePath);

        // Microtask queue'nun boşalması için bekle
        await Future.delayed(const Duration(milliseconds: 50));

        await sub1.cancel();
        await sub2.cancel();

        expect(events1, isNotEmpty);
        expect(
          events1.length,
          equals(events2.length),
          reason: 'Her iki dinleyici aynı sayıda event almalı',
        );
        expect(
          events1.last.pending,
          equals(events2.last.pending),
          reason: 'Son değerler tutarlı olmalı',
        );
        expect(events1.last.pending, 2);

        await freshRepo.dispose();
      },
    );
  });
}
