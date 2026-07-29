/// §3 Concurrency / Yarış Durumu testleri.
///
/// Upload'lar `ControllableUploadAdapter` ile askıya alınır; bu sayede
/// `cancel()` / `dispose()` / çift çağrı gibi yarış senaryoları
/// deterministic olarak test edilir.
///
/// CI filtreleme: `flutter test test/concurrency_test.dart`
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:offline_upload_queue/offline_upload_queue.dart';
import 'package:offline_upload_queue/src/queue/queue_controller.dart';

import 'helpers/controllable_upload_adapter.dart';
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
      '${Directory.systemTemp.path}/cc_${DateTime.now().microsecondsSinceEpoch}.jpg',
    )..writeAsBytesSync([0xFF, 0xD8, 0xFF]); // minimal JPEG
    fakeFilePath = fakeFile.path;
  });

  tearDown(() async {
    QueueController.resetForTesting('test');
    await repo.dispose();
    monitor.dispose();
    if (fakeFile.existsSync()) fakeFile.deleteSync();
  });

  // ── §3.2 ──────────────────────────────────────────────────────────────────

  test(
    '3.2 cancel() upload esnasında → task cancelled durumuna geçer',
    () async {
      final adapter = ControllableUploadAdapter(pauseOnCall: true);
      final uploadStarted = Completer<void>();

      final controller = makeController(
        adapter: adapter,
        monitor: monitor,
        repo: repo,
        maxAttempts: 3,
        backoff: BackoffStrategy.fixed(const Duration(milliseconds: 5)),
      );
      await controller.init();

      // controller.enqueue() → gerçek dosya kontrolü yapar
      final taskId = await controller.enqueue(filePath: fakeFilePath);

      // Upload başladığında (uploading durumu) Completer'ı çöz
      repo.watchTasks(statuses: {UploadStatus.uploading}).listen((tasks) {
        if (tasks.any((t) => t.taskId == taskId) && !uploadStarted.isCompleted) {
          uploadStarted.complete();
        }
      });

      await uploadStarted.future.timeout(const Duration(seconds: 2));

      // Upload yürütülürken iptal et
      await controller.cancel(taskId);

      // Adapter'ın completer'ı error ile kapandı (cancelToken tetikledi)
      // Kısa bekleme ile state'in settle etmesini sağla
      await Future.delayed(const Duration(milliseconds: 100));

      expect(
        repo.taskFor(taskId)?.status,
        UploadStatus.cancelled,
        reason: 'Cancel çağrısı sonrası task cancelled olmalı',
      );

      await controller.dispose();
    },
  );

  // ── §3.3 ──────────────────────────────────────────────────────────────────

  test(
    '3.3 dispose() aktif upload sırasında → task pending\'e döner (cancelled değil)',
    () async {
      print('--- 3.3 test started ---');
      final adapter = ControllableUploadAdapter(pauseOnCall: true);
      final uploadStarted = Completer<void>();

      final controller = makeController(
        adapter: adapter,
        monitor: monitor,
        repo: repo,
        maxAttempts: 3,
        backoff: BackoffStrategy.fixed(const Duration(milliseconds: 5)),
      );
      await controller.init();
      print('--- controller initialized ---');

      final taskId = await controller.enqueue(filePath: fakeFilePath);
      print('--- task enqueued ---');

      repo.watchTasks(statuses: {UploadStatus.uploading}).listen((tasks) {
        if (tasks.any((t) => t.taskId == taskId) && !uploadStarted.isCompleted) {
          uploadStarted.complete();
        }
      });
      await uploadStarted.future.timeout(const Duration(seconds: 2));
      print('--- upload started confirmed ---');

      // Aktif upload sırasında dispose
      print('--- calling controller.dispose() ---');
      await controller.dispose();
      print('--- controller.dispose() returned ---');

      // Tasarım kararı: dispose() task'ı pending'e alır, cancelled'a DEĞİL
      // Sonraki init()'te backoff beklemeden hemen alınabilsin diye
      expect(
        repo.taskFor(taskId)?.status,
        UploadStatus.pending,
        reason: 'dispose() sonrası task pending olmalı (cancelled değil!)',
      );
      print('--- 3.3 test finished ---');
    },
  );

  // ── §3.4 ──────────────────────────────────────────────────────────────────

  test(
    '3.4 dispose() sonrası "gecikmiş" adapter response → state bozulmuyor',
    () async {
      final adapter = ControllableUploadAdapter(pauseOnCall: true);
      final uploadStarted = Completer<void>();

      final controller = makeController(
        adapter: adapter,
        monitor: monitor,
        repo: repo,
        maxAttempts: 3,
        backoff: BackoffStrategy.fixed(const Duration(milliseconds: 5)),
      );
      await controller.init();

      final taskId = await controller.enqueue(filePath: fakeFilePath);

      repo.watchTasks(statuses: {UploadStatus.uploading}).listen((tasks) {
        if (tasks.any((t) => t.taskId == taskId) && !uploadStarted.isCompleted) {
          uploadStarted.complete();
        }
      });
      await uploadStarted.future.timeout(const Duration(seconds: 2));

      // dispose() → cancelToken.cancel() → completer error ile kapanıyor
      await controller.dispose();

      // Gecikmiş response: adapter'ı tamamlamaya çalış
      // (cancelToken zaten iptal edildiği için completer tamamlanmış; bu no-op)
      adapter.resumeAll(result: const UploadResult.success());

      await Future.delayed(const Duration(milliseconds: 150));

      // State bozulmamalı: task hâlâ pending (dispose'un markPending'inden)
      expect(
        repo.taskFor(taskId)?.status,
        UploadStatus.pending,
        reason: 'Dispose sonrası gecikmiş response state bozmamalı',
      );
    },
  );

  // ── §3.5 ──────────────────────────────────────────────────────────────────

  test(
    '3.5 cancel() iki kez art arda → no-op, exception fırlatılmıyor',
    () async {
      final adapter = ControllableUploadAdapter(pauseOnCall: true);
      final uploadStarted = Completer<void>();

      final controller = makeController(
        adapter: adapter,
        monitor: monitor,
        repo: repo,
        maxAttempts: 3,
        backoff: BackoffStrategy.fixed(const Duration(milliseconds: 5)),
      );
      await controller.init();

      final taskId = await controller.enqueue(filePath: fakeFilePath);

      repo.watchTasks(statuses: {UploadStatus.uploading}).listen((tasks) {
        if (tasks.any((t) => t.taskId == taskId) && !uploadStarted.isCompleted) {
          uploadStarted.complete();
        }
      });
      await uploadStarted.future.timeout(const Duration(seconds: 2));

      // İlk cancel
      await controller.cancel(taskId);

      // İkinci cancel → no-op, exception olmamalı
      await expectLater(controller.cancel(taskId), completes);

      expect(repo.taskFor(taskId)?.status, UploadStatus.cancelled);

      await controller.dispose();
    },
  );

  // ── §3.1 (ek doğrulama) ───────────────────────────────────────────────────

  test(
    '3.1 Eşzamanlı enqueue çağrıları benzersiz taskId ve artan sequenceNumber üretir',
    () async {
      final adapter = MockUploadAdapter.alwaysSuccess();
      final controller = makeController(
        adapter: adapter,
        monitor: monitor,
        repo: repo,
        maxAttempts: 3,
      );
      await controller.init();

      // 10 eşzamanlı enqueue (controller üzerinden → dosya varlık kontrolü geçiyor)
      final ids = await Future.wait([
        for (var i = 0; i < 10; i++)
          controller.enqueue(filePath: fakeFilePath),
      ]);

      // Tüm taskId'ler benzersiz
      expect(ids.toSet().length, 10, reason: 'TaskId\'ler benzersiz olmalı');

      // Tüm sequence numaraları benzersiz ve monoton
      final seqs =
          repo.allTasks.map((t) => t.sequenceNumber).toList()..sort();
      expect(seqs.toSet().length, 10, reason: 'Sequence numaraları benzersiz olmalı');
      for (var i = 1; i < seqs.length; i++) {
        expect(seqs[i], greaterThan(seqs[i - 1]));
      }

      await controller.dispose();
    },
  );
}
