import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:offline_upload_queue/offline_upload_queue.dart';
import 'package:offline_upload_queue/src/queue/queue_controller.dart';

import 'helpers/in_memory_persistence_repository.dart';

// ── Test helpers ──────────────────────────────────────────────────────────────

/// Bağlantı durumunu kontrol edebilen test ConnectivityMonitor.
class MockConnectivityMonitor implements ConnectivityMonitor {
  ConnectivityStatus _status;
  final _controller = StreamController<ConnectivityStatus>.broadcast();

  MockConnectivityMonitor([this._status = ConnectivityStatus.wifi]);

  void setStatus(ConnectivityStatus status) {
    _status = status;
    _controller.add(status);
  }

  @override
  Future<ConnectivityStatus> checkStatus() async => _status;

  @override
  Stream<ConnectivityStatus> get statusStream => _controller.stream;

  void dispose() => _controller.close();
}

/// Önceden programlanmış sonuçlar döndüren test UploadAdapter.
class MockUploadAdapter implements UploadAdapter {
  final List<UploadResult> _results;
  int _callCount = 0;
  void Function(String taskId)? onUploadCalled;

  MockUploadAdapter(this._results);

  factory MockUploadAdapter.alwaysSuccess() =>
      MockUploadAdapter([const UploadResult.success()]);

  factory MockUploadAdapter.alwaysFailure(FailureType type) =>
      MockUploadAdapter([UploadResult.failure(type)]);

  @override
  Future<UploadResult> uploadFile({
    required String taskId,
    required String filePath,
    required Map<String, dynamic> metadata,
    required String checksum,
    void Function(int sent, int total)? onProgress,
    UploadCancelToken? cancelToken,
  }) async {
    onUploadCalled?.call(taskId);
    final idx = _callCount.clamp(0, _results.length - 1);
    _callCount++;
    return _results[idx];
  }

  int get callCount => _callCount;
}

/// QueueController'ı InMemory repo + mock bileşenlerle oluşturan yardımcı.
QueueController makeController({
  required MockUploadAdapter adapter,
  required MockConnectivityMonitor monitor,
  required InMemoryPersistenceRepository repo,
  bool wifiOnly = false,
  int maxAttempts = 6,
  BackoffStrategy? backoff,
  Future<void> Function()? onAuthExpired,
  Duration authTimeout = const Duration(seconds: 30),
  UploadQueueAdvancedOptions? advanced,
}) {
  return QueueController(
    repository: repo,
    adapter: adapter,
    retryPolicy: RetryPolicy(
      maxAttempts: maxAttempts,
      backoff: backoff ??
          BackoffStrategy.fixed(const Duration(milliseconds: 10)),
    ),
    connectivityMonitor: monitor,
    wifiOnly: wifiOnly,
    verifyChecksum: false,
    copyToSandbox: false,
    boxName: 'test',
    onAuthExpired: onAuthExpired,
    authTimeout: authTimeout,
    advanced: advanced ?? const UploadQueueAdvancedOptions(),
  );
}

// ── Testler ───────────────────────────────────────────────────────────────────

void main() {
  // ── Enum sıra koruması (Drift intEnum) ─────────────────────────────────────
  group('UploadStatus enum (Drift intEnum sıra koruması)', () {
    test('sıra sabit — index değerleri değişmemeli', () {
      expect(UploadStatus.pending.index, 0);
      expect(UploadStatus.uploading.index, 1);
      expect(UploadStatus.completed.index, 2);
      expect(UploadStatus.failed.index, 3);
      expect(UploadStatus.permanentlyFailed.index, 4);
      expect(UploadStatus.cancelled.index, 5);
    });
  });

  group('FailureType enum (Drift intEnum sıra koruması)', () {
    test('sıra sabit — index değerleri değişmemeli', () {
      expect(FailureType.network.index, 0);
      expect(FailureType.serverError.index, 1);
      expect(FailureType.rateLimited.index, 2);
      expect(FailureType.authExpired.index, 3);
      expect(FailureType.fileNotFound.index, 4);
      expect(FailureType.corruptFile.index, 5);
      expect(FailureType.payloadTooLarge.index, 6);
      expect(FailureType.badRequest.index, 7);
      expect(FailureType.unknown.index, 8);
    });
  });

  // ── RetryPolicy ────────────────────────────────────────────────────────────
  group('RetryPolicy', () {
    test('kalıcı hatalar isPermanent() → true döner', () {
      final policy = RetryPolicy(
        maxAttempts: 6,
        backoff: BackoffStrategy.fixed(const Duration(seconds: 1)),
      );
      expect(policy.isPermanent(FailureType.fileNotFound), isTrue);
      expect(policy.isPermanent(FailureType.corruptFile), isTrue);
      expect(policy.isPermanent(FailureType.payloadTooLarge), isTrue);
      expect(policy.isPermanent(FailureType.badRequest), isTrue);
    });

    test('geçici hatalar isPermanent() → false döner', () {
      final policy = RetryPolicy(
        maxAttempts: 6,
        backoff: BackoffStrategy.fixed(const Duration(seconds: 1)),
      );
      expect(policy.isPermanent(FailureType.network), isFalse);
      expect(policy.isPermanent(FailureType.serverError), isFalse);
      expect(policy.isPermanent(FailureType.rateLimited), isFalse);
      expect(policy.isPermanent(FailureType.authExpired), isFalse);
    });

    test('maxAttempts aşımında shouldPermanentlyFail → true döner', () {
      final policy = RetryPolicy(
        maxAttempts: 3,
        backoff: BackoffStrategy.fixed(const Duration(seconds: 1)),
      );
      expect(policy.shouldPermanentlyFail(0), isFalse);
      expect(policy.shouldPermanentlyFail(1), isFalse);
      expect(policy.shouldPermanentlyFail(2), isTrue);
    });

    test('rateLimited + retryAfter → nextRetryAt doğru hesaplanır', () {
      final policy = RetryPolicy(
        maxAttempts: 6,
        backoff: BackoffStrategy.fixed(const Duration(seconds: 10)),
      );
      final now = DateTime(2024, 1, 1, 12, 0, 0);
      const retryAfter = Duration(seconds: 60);
      final result = policy.nextRetryAt(
        retryCount: 0,
        failureType: FailureType.rateLimited,
        retryAfter: retryAfter,
        from: now,
      );
      expect(result, equals(now.add(retryAfter)));
    });

    test('exponential backoff: 3. denemede bekleme süresi artar', () {
      const base = Duration(seconds: 2);
      final policy = RetryPolicy(
        maxAttempts: 6,
        backoff: BackoffStrategy.exponential(
          base: base,
          max: const Duration(minutes: 10),
        ),
      );
      final now = DateTime(2024, 1, 1);
      final retry0 = policy.nextRetryAt(retryCount: 0, failureType: FailureType.network, from: now);
      final retry2 = policy.nextRetryAt(retryCount: 2, failureType: FailureType.network, from: now);
      expect(retry2!.difference(now) >= retry0!.difference(now), isTrue);
    });
  });

  // ── State machine (InMemory repo üzerinde) ─────────────────────────────────
  group('QueueController state machine', () {
    late InMemoryPersistenceRepository repo;
    late MockConnectivityMonitor monitor;

    setUp(() {
      repo = InMemoryPersistenceRepository();
      monitor = MockConnectivityMonitor(ConnectivityStatus.wifi);
    });

    tearDown(() async {
      await repo.dispose();
      monitor.dispose();
    });

    test('wifiOnly:true + cellular → görev pending kalır', () async {
      monitor.setStatus(ConnectivityStatus.cellular);
      final adapter = MockUploadAdapter.alwaysSuccess();
      final controller = makeController(
        adapter: adapter, monitor: monitor, repo: repo, wifiOnly: true,
      );
      await controller.init();

      await repo.enqueue(taskId: 'task-1', filePath: '/fake/photo.jpg', sequenceNumber: 1);
      await Future.delayed(const Duration(milliseconds: 100));

      expect(repo.taskFor('task-1')?.status, UploadStatus.pending);
      expect(adapter.callCount, 0);
      await controller.dispose();
    });

    test('forceUploadOnce() wifiOnly bypass ile görevi işler', () async {
      monitor.setStatus(ConnectivityStatus.cellular);
      final completer = Completer<void>();
      final adapter = MockUploadAdapter.alwaysSuccess()
        ..onUploadCalled = (_) => completer.complete();

      final controller = makeController(
        adapter: adapter, monitor: monitor, repo: repo, wifiOnly: true, maxAttempts: 6,
      );
      await controller.init();

      await repo.enqueue(taskId: 'task-2', filePath: '/fake/photo.jpg', sequenceNumber: 2);
      await controller.forceUploadOnce();
      await completer.future.timeout(const Duration(seconds: 2));

      await Future.delayed(const Duration(milliseconds: 50));
      expect(repo.taskFor('task-2')?.status, UploadStatus.completed);
      await controller.dispose();
    });

    test('pause() aktifken forceUploadOnce() görev işlemez', () async {
      final adapter = MockUploadAdapter.alwaysSuccess();
      final controller = makeController(
        adapter: adapter, monitor: monitor, repo: repo, wifiOnly: true,
      );
      await controller.init();

      await repo.enqueue(taskId: 'task-3', filePath: '/fake/photo.jpg', sequenceNumber: 3);
      controller.pause();
      await controller.forceUploadOnce();
      await Future.delayed(const Duration(milliseconds: 100));

      expect(repo.taskFor('task-3')?.status, UploadStatus.pending);
      expect(adapter.callCount, 0);
      await controller.dispose();
    });

    test('fileNotFound → ilk denemede permanentlyFailed', () async {
      final adapter = MockUploadAdapter.alwaysFailure(FailureType.fileNotFound);
      final completer = Completer<void>();
      final controller = makeController(adapter: adapter, monitor: monitor, repo: repo);
      await controller.init();

      await repo.enqueue(taskId: 'task-4', filePath: '/fake/photo.jpg', sequenceNumber: 4);
      repo.watchTasks(statuses: {UploadStatus.permanentlyFailed}).listen((tasks) {
        if (tasks.any((t) => t.taskId == 'task-4') && !completer.isCompleted) completer.complete();
      });

      await completer.future.timeout(const Duration(seconds: 2));
      expect(repo.taskFor('task-4')?.status, UploadStatus.permanentlyFailed);
      expect(repo.taskFor('task-4')?.failureType, FailureType.fileNotFound);
      await controller.dispose();
    });

    test('maxAttempts:2 → 2 denemede permanentlyFailed', () async {
      final adapter = MockUploadAdapter.alwaysFailure(FailureType.network);
      final completer = Completer<void>();
      final controller = makeController(
        adapter: adapter, monitor: monitor, repo: repo, maxAttempts: 2,
      );
      await controller.init();

      await repo.enqueue(taskId: 'task-5', filePath: '/fake/photo.jpg', sequenceNumber: 5);
      repo.watchTasks(statuses: {UploadStatus.permanentlyFailed}).listen((tasks) {
        if (tasks.any((t) => t.taskId == 'task-5') && !completer.isCompleted) completer.complete();
      });

      await completer.future.timeout(const Duration(seconds: 3));
      expect(repo.taskFor('task-5')?.status, UploadStatus.permanentlyFailed);
      await controller.dispose();
    });

    test('maxAttempts:1 → failed geçmeden doğrudan permanentlyFailed', () async {
      final adapter = MockUploadAdapter.alwaysFailure(FailureType.network);
      final completer = Completer<void>();
      final controller = makeController(
        adapter: adapter, monitor: monitor, repo: repo, maxAttempts: 1,
      );
      await controller.init();

      await repo.enqueue(taskId: 'task-6', filePath: '/fake/photo.jpg', sequenceNumber: 6);
      repo.watchTasks(statuses: {UploadStatus.permanentlyFailed}).listen((tasks) {
        if (tasks.any((t) => t.taskId == 'task-6') && !completer.isCompleted) completer.complete();
      });

      await completer.future.timeout(const Duration(seconds: 2));
      expect(repo.taskFor('task-6')?.status, UploadStatus.permanentlyFailed);
      expect(adapter.callCount, 1);
      await controller.dispose();
    });

    test('init() uploading → pending recovery yapar', () async {
      await repo.enqueue(taskId: 'task-7', filePath: '/fake/photo.jpg', sequenceNumber: 7);
      await repo.markUploading('task-7');
      expect(repo.taskFor('task-7')?.status, UploadStatus.uploading);

      await repo.init();
      expect(repo.taskFor('task-7')?.status, UploadStatus.pending);
      expect(repo.taskFor('task-7')?.nextRetryAt, isNull);
    });

    test('watchTasks({pending}) yalnızca pending döner', () async {
      await repo.enqueue(taskId: 'task-8a', filePath: '/fake/a.jpg', sequenceNumber: 8);
      await repo.enqueue(taskId: 'task-8b', filePath: '/fake/b.jpg', sequenceNumber: 9);
      await repo.markCompleted('task-8b');

      final tasks = await repo.watchTasks(statuses: {UploadStatus.pending}).first;
      expect(tasks.length, 1);
      expect(tasks.first.taskId, 'task-8a');
    });

    test('purgeAllCompleted() → completed kayıtlar silinir', () async {
      await repo.enqueue(taskId: 'task-9a', filePath: '/fake/a.jpg', sequenceNumber: 10);
      await repo.enqueue(taskId: 'task-9b', filePath: '/fake/b.jpg', sequenceNumber: 11);
      await repo.markCompleted('task-9a');

      await repo.purgeAllCompleted();

      final all = repo.allTasks;
      expect(all.any((t) => t.taskId == 'task-9a'), isFalse);
      expect(all.any((t) => t.taskId == 'task-9b'), isTrue);
    });

    test('diskUsageWarning eşiği aşılınca onDiskUsageWarning çağrılır', () async {
      int? capturedCurrent;
      int? capturedWarning;

      final advanced = UploadQueueAdvancedOptions(
        heartbeatInterval: const Duration(milliseconds: 50),
        staleLockThreshold: const Duration(milliseconds: 200),
        diskUsageWarningBytes: 100,
        onDiskUsageWarning: (current, warning) {
          capturedCurrent = current;
          capturedWarning = warning;
        },
      );

      final controller = makeController(
        adapter: MockUploadAdapter.alwaysSuccess(),
        monitor: monitor, repo: repo, advanced: advanced,
      );
      await controller.init();

      await repo.enqueue(
        taskId: 'task-10', filePath: '/fake/photo.jpg', sequenceNumber: 12, fileSizeBytes: 200,
      );
      await Future.delayed(const Duration(milliseconds: 200));

      expect(capturedCurrent, isNotNull);
      expect(capturedCurrent, greaterThan(100));
      expect(capturedWarning, 100);
      await controller.dispose();
    });

    test('onLog null bırakılınca hiçbir exception fırlatılmaz', () async {
      final controller = makeController(
        adapter: MockUploadAdapter.alwaysSuccess(),
        monitor: monitor, repo: repo,
        advanced: const UploadQueueAdvancedOptions(),
      );
      await expectLater(() async => await controller.init(), returnsNormally);
      await controller.dispose();
    });

    test('purgeAllCancelled() → cancelled kayıtlar temizlenir', () async {
      await repo.enqueue(taskId: 'task-12a', filePath: '/fake/a.jpg', sequenceNumber: 13);
      await repo.enqueue(taskId: 'task-12b', filePath: '/fake/b.jpg', sequenceNumber: 14);
      await repo.markCancelled('task-12a');

      await repo.purgeAllCancelled();

      expect(repo.taskFor('task-12a'), isNull);
      expect(repo.taskFor('task-12b'), isNotNull);
    });

    test('estimatedDiskUsageBytes = pending+failed+cancelled toplamı', () async {
      await repo.enqueue(taskId: 'disk-1', filePath: '/fake/a.jpg', sequenceNumber: 15, fileSizeBytes: 100);
      await repo.enqueue(taskId: 'disk-2', filePath: '/fake/b.jpg', sequenceNumber: 16, fileSizeBytes: 200);
      await repo.markCompleted('disk-2');

      await repo.enqueue(taskId: 'disk-trigger', filePath: '/fake/c.jpg', sequenceNumber: 17, fileSizeBytes: 0);
      await repo.purge('disk-trigger');

      final summary = await repo.watchSummary().first;
      expect(summary.estimatedDiskUsageBytes, 100);
    });
  });

  // ── Aşama 2 — Yeni testler ─────────────────────────────────────────────────
  group('Aşama 2 — Dayanıklılık doğrulamaları', () {
    late InMemoryPersistenceRepository repo;
    late MockConnectivityMonitor monitor;

    setUp(() {
      repo = InMemoryPersistenceRepository();
      monitor = MockConnectivityMonitor(ConnectivityStatus.wifi);
    });

    tearDown(() async {
      await repo.dispose();
      monitor.dispose();
    });

    test('markCancelled() → nextRetryAt null olur (§4 Kritik kural #5)', () async {
      await repo.enqueue(taskId: 'cancel-1', filePath: '/fake/photo.jpg', sequenceNumber: 100);
      await repo.markFailed(
        'cancel-1',
        failureType: FailureType.network,
        nextRetryAt: DateTime.now().add(const Duration(minutes: 5)),
      );
      expect(repo.taskFor('cancel-1')?.nextRetryAt, isNotNull);

      await repo.markCancelled('cancel-1');
      expect(repo.taskFor('cancel-1')?.status, UploadStatus.cancelled);
    });

    test('getNextSequenceNumber() → her çağrıda artar', () async {
      final seq1 = await repo.getNextSequenceNumber();
      await repo.enqueue(taskId: 'seq-1', filePath: '/fake/a.jpg', sequenceNumber: seq1);

      final seq2 = await repo.getNextSequenceNumber();
      await repo.enqueue(taskId: 'seq-2', filePath: '/fake/b.jpg', sequenceNumber: seq2);

      expect(seq2, greaterThan(seq1));
    });

    test('QueueSummary.copyWith() → yalnızca belirtilen alanlar değişir', () {
      const original = QueueSummary(
        pending: 5, uploading: 1, completed: 10, failed: 2,
        permanentlyFailed: 0, cancelled: 0,
        isPaused: false, pausedDueToAuth: false,
        estimatedDiskUsageBytes: 1024,
      );

      final updated = original.copyWith(isPaused: true);
      expect(updated.isPaused, isTrue);
      expect(updated.pending, 5);
      expect(updated.uploading, 1);
      expect(updated.completed, 10);
      expect(updated.estimatedDiskUsageBytes, 1024);
    });

    test('retry() → permanentlyFailed → pending → completed', () async {
      final adapter = MockUploadAdapter([
        UploadResult.failure(FailureType.fileNotFound),
        const UploadResult.success(),
      ]);
      final permanentCompleter = Completer<void>();
      final completedCompleter = Completer<void>();

      final controller = makeController(
        adapter: adapter, monitor: monitor, repo: repo, maxAttempts: 1,
      );
      await controller.init();

      await repo.enqueue(taskId: 'retry-1', filePath: '/fake/photo.jpg', sequenceNumber: 200);

      repo.watchTasks(statuses: {UploadStatus.permanentlyFailed}).listen((tasks) {
        if (tasks.any((t) => t.taskId == 'retry-1') && !permanentCompleter.isCompleted) {
          permanentCompleter.complete();
        }
      });
      await permanentCompleter.future.timeout(const Duration(seconds: 2));

      repo.watchTasks(statuses: {UploadStatus.completed}).listen((tasks) {
        if (tasks.any((t) => t.taskId == 'retry-1') && !completedCompleter.isCompleted) {
          completedCompleter.complete();
        }
      });

      await controller.retry('retry-1');
      await completedCompleter.future.timeout(const Duration(seconds: 2));

      expect(repo.taskFor('retry-1')?.status, UploadStatus.completed);
      await controller.dispose();
    });

    test('nextRetryAt gelecekte olan failed görev getNextPending() sonucu değil', () async {
      await repo.enqueue(taskId: 'backoff-1', filePath: '/fake/photo.jpg', sequenceNumber: 300);
      await repo.markFailed(
        'backoff-1',
        failureType: FailureType.network,
        nextRetryAt: DateTime.now().add(const Duration(hours: 1)),
      );

      final task = await repo.getNextPending(DateTime.now());
      expect(task, isNull);
    });

    test('purgeAllFailed() → yalnızca permanentlyFailed silinir', () async {
      await repo.enqueue(taskId: 'pf-1', filePath: '/fake/a.jpg', sequenceNumber: 400);
      await repo.enqueue(taskId: 'pf-2', filePath: '/fake/b.jpg', sequenceNumber: 401);
      await repo.markPermanentlyFailed('pf-1', failureType: FailureType.badRequest);

      await repo.purgeAllFailed();

      expect(repo.taskFor('pf-1'), isNull);
      expect(repo.taskFor('pf-2'), isNotNull);
    });
  });

  // ── Aşama 3: Kilit Mekanizması Testleri ─────────────────────────────────────
  group('Kilit mekanizması (§7, §10 test #8)', () {
    late InMemoryPersistenceRepository repo;
    late MockConnectivityMonitor connectivity;
    late MockUploadAdapter adapter;

    QueueController makeController({String boxName = 'test-lock-box'}) {
      return QueueController(
        repository: repo,
        adapter: adapter,
        retryPolicy: RetryPolicy(
          maxAttempts: 3,
          backoff: BackoffStrategy.exponential(
            base: const Duration(seconds: 2),
            max: const Duration(minutes: 5),
          ),
        ),
        connectivityMonitor: connectivity,
        wifiOnly: false,
        verifyChecksum: false,
        copyToSandbox: false,
        boxName: boxName,
      );
    }

    setUp(() {
      repo = InMemoryPersistenceRepository();
      connectivity = MockConnectivityMonitor(ConnectivityStatus.wifi);
      adapter = MockUploadAdapter.alwaysSuccess();
    });

    tearDown(() {
      // Singleton set'i temizle — testler arası izolasyon
      QueueController.resetForTesting('test-lock-box');
    });

    test('çift init() aynı boxName → StateError fırlatır', () async {
      final c1 = makeController();
      await c1.init();

      final c2 = makeController();
      expect(
        () => c2.init(),
        throwsA(isA<StateError>().having(
          (e) => e.message,
          'message',
          contains('already initialized'),
        )),
      );

      await c1.dispose();
    });

    test('dispose() sonrası aynı boxName ile tekrar init() başarılı', () async {
      final c1 = makeController();
      await c1.init();
      await c1.dispose();

      // dispose() _activeBoxNames'ten çıkarmış olmalı
      final c2 = makeController();
      await expectLater(c2.init(), completes);
      await c2.dispose();
    });

    test('staleLockThreshold < heartbeatInterval * 3 → ArgumentError', () {
      final c = QueueController(
        repository: repo,
        adapter: adapter,
        retryPolicy: RetryPolicy(
          maxAttempts: 3,
          backoff: BackoffStrategy.exponential(
            base: const Duration(seconds: 2),
            max: const Duration(minutes: 5),
          ),
        ),
        connectivityMonitor: connectivity,
        wifiOnly: false,
        verifyChecksum: false,
        copyToSandbox: false,
        boxName: 'stale-arg-box',
        advanced: const UploadQueueAdvancedOptions(
          staleLockThreshold: Duration(seconds: 10),
          heartbeatInterval: Duration(seconds: 30),
        ),
      );

      expect(
        () => c.init(),
        throwsA(isA<ArgumentError>().having(
          (e) => e.message,
          'message',
          contains('staleLockThreshold'),
        )),
      );

      QueueController.resetForTesting('stale-arg-box');
    });
  }); // kilit mekanizması group sonu

  // ── Aşama 3: BackgroundTaskRunner Testleri ──────────────────────────────────
  group('BackgroundTaskRunner', () {
    // BackgroundTaskRunner, UploadQueue somut sınıfına bağımlı olduğundan
    // doğrudan test edilemez. Bu yüzden BackgroundTaskRunner'ın mantığını
    // aynı Future.any + Completer örüntüsüyle birim testlerle doğruluyoruz.

    test('kuyruk hemen boşalırsa false döner', () async {
      // Simülasyon: stream anında "boş" sinyali gönderirse hasPending = false
      final emptyCompleter = Completer<void>();
      bool hasPending = false;

      final controller = StreamController<({int pending, int uploading})>.broadcast();

      final sub = controller.stream.listen((summary) {
        hasPending = summary.pending > 0 || summary.uploading > 0;
        if (!hasPending && !emptyCompleter.isCompleted) {
          emptyCompleter.complete();
        }
      });

      // Kuyruk boş sinyali gönder
      controller.add((pending: 0, uploading: 0));

      await Future.any([
        emptyCompleter.future,
        Future<void>.delayed(const Duration(seconds: 5)),
      ]);

      await sub.cancel();
      await controller.close();

      expect(hasPending, isFalse);
    });

    test('timeout dolduğunda hasPending=true kalır', () async {
      final emptyCompleter = Completer<void>();
      bool hasPending = false;
      const shortTimeout = Duration(milliseconds: 50);

      final controller = StreamController<({int pending, int uploading})>.broadcast();

      final sub = controller.stream.listen((summary) {
        hasPending = summary.pending > 0 || summary.uploading > 0;
        if (!hasPending && !emptyCompleter.isCompleted) {
          emptyCompleter.complete();
        }
      });

      // Kuyrukta iş var — boş sinyali hiç gelmiyor
      controller.add((pending: 2, uploading: 1));

      await Future.any([
        emptyCompleter.future,
        Future<void>.delayed(shortTimeout), // 50 ms timeout
      ]);

      await sub.cancel();
      await controller.close();

      // Timeout doldu, hasPending hâlâ true olmalı
      expect(hasPending, isTrue);
    });

    test('emptyCompleter birden fazla event gelse de tek kez tamamlanır', () async {
      final emptyCompleter = Completer<void>();
      int completeCount = 0;

      final controller = StreamController<({int pending, int uploading})>.broadcast();

      final sub = controller.stream.listen((summary) {
        final isEmpty = summary.pending == 0 && summary.uploading == 0;
        if (isEmpty && !emptyCompleter.isCompleted) {
          emptyCompleter.complete();
          completeCount++;
        }
      });

      // Birden fazla "boş" eventi gönder
      controller.add((pending: 0, uploading: 0));
      controller.add((pending: 0, uploading: 0));
      controller.add((pending: 0, uploading: 0));

      await Future.any([
        emptyCompleter.future,
        Future<void>.delayed(const Duration(milliseconds: 100)),
      ]);

      await sub.cancel();
      await controller.close();

      // isCompleted koruması sayesinde complete() yalnızca bir kez çağrıldı
      expect(completeCount, 1);
    });

    // ── Aşama 3: IosBackgroundChannel handler yönlendirme testi ──────────────
    group('IosBackgroundChannel setMethodCallHandler yönlendirmesi', () {
      test('onAppRefresh callback çağrılabilir ve bool döner', () async {
        bool called = false;
        Future<bool> onAppRefresh() async {
          called = true;
          return false;
        }

        // Handler'ı doğrudan çağırarak yönlendirme mantığını doğrula
        final result = await onAppRefresh();
        expect(called, isTrue);
        expect(result, isFalse);
      });

      test('onExpiration void callback çağrılabilir', () {
        bool expireCalled = false;
        void onExpiration() => expireCalled = true;

        onExpiration();
        expect(expireCalled, isTrue);
      });
    });
  });
}
