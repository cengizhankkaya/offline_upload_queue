import 'dart:async';

import 'package:offline_upload_queue/src/database/persistence_repository.dart';
import 'package:offline_upload_queue/src/models/queue_summary.dart';
import 'package:offline_upload_queue/src/models/upload_status.dart';
import 'package:offline_upload_queue/src/models/upload_task.dart';

/// Birim testler için in-memory `PersistenceRepository` implementasyonu.
///
/// Gerçek Drift/SQLite olmadan state machine'in tüm davranışını test etmeye
/// olanak tanır. `tearDown`'da `dispose()` çağırmayı unutmayın.
///
/// ```dart
/// late InMemoryPersistenceRepository repo;
///
/// setUp(() => repo = InMemoryPersistenceRepository());
/// tearDown(() => repo.dispose());
/// ```
class InMemoryPersistenceRepository implements PersistenceRepository {
  final _tasks = <String, UploadTask>{}; // taskId → UploadTask
  final _progressControllers = <String, StreamController<double>>{};
  late final StreamController<void> _changeNotifier;

  InMemoryPersistenceRepository() {
    _changeNotifier = StreamController<void>.broadcast();
  }

  void _notify() {
    if (!_changeNotifier.isClosed) _changeNotifier.add(null);
  }

  // ── Init & Recovery ──────────────────────────────────────────────────────

  @override
  Future<void> init() async {
    // DB açma eşdeğeri — recovery [recoverStuckUploads] ile yapılır.
  }

  // ── Enqueue ───────────────────────────────────────────────────────────────

  @override
  Future<UploadTask> enqueue({
    required String taskId,
    required String filePath,
    int? fileSizeBytes,
    Map<String, dynamic>? metadata,
    int priority = 0,
  }) async {
    final sequenceNumber = await getNextSequenceNumber();
    final task = UploadTask(
      taskId: taskId,
      filePath: filePath,
      sequenceNumber: sequenceNumber,
      status: UploadStatus.pending,
      retryCount: 0,
      createdAt: DateTime.now(),
      priority: priority,
      fileSizeBytes: fileSizeBytes,
      metadata: metadata,
    );
    _tasks[taskId] = task;
    _notify();
    return task;
  }

  // ── Query ─────────────────────────────────────────────────────────────────

  @override
  Future<UploadTask?> getNextPending(
    DateTime now, {
    Set<String>? onlyTaskIds,
  }) async {
    final candidates =
        _tasks.values
            .where(
              (t) =>
                  (t.status == UploadStatus.pending ||
                      t.status == UploadStatus.failed) &&
                  (onlyTaskIds == null || onlyTaskIds.contains(t.taskId)) &&
                  (t.nextRetryAt == null ||
                      t.nextRetryAt!.isBefore(now) ||
                      t.nextRetryAt == now),
            )
            .toList()
          ..sort((a, b) {
            final cmp = b.priority.compareTo(a.priority);
            if (cmp != 0) return cmp;
            return a.sequenceNumber.compareTo(b.sequenceNumber);
          });
    return candidates.isEmpty ? null : candidates.first;
  }

  @override
  Future<UploadTask?> getTask(String taskId) async => _tasks[taskId];

  // ── State transitions ─────────────────────────────────────────────────────

  @override
  Future<void> markUploading(String taskId) async {
    _update(taskId, (t) => t.copyWith(status: UploadStatus.uploading));
  }

  @override
  Future<void> markCompleted(String taskId, {String? checksum}) async {
    _update(
      taskId,
      (t) => t.copyWith(
        status: UploadStatus.completed,
        checksum: checksum ?? t.checksum,
      ),
    );
  }

  @override
  Future<void> markFailed(
    String taskId, {
    required FailureType failureType,
    String? errorMessage,
    DateTime? nextRetryAt,
  }) async {
    final existing = _tasks[taskId];
    if (existing == null) return;
    if (existing.status == UploadStatus.cancelled ||
        existing.status == UploadStatus.completed ||
        existing.status == UploadStatus.permanentlyFailed) {
      return;
    }
    _tasks[taskId] = UploadTask(
      taskId: existing.taskId,
      filePath: existing.filePath,
      sequenceNumber: existing.sequenceNumber,
      status: UploadStatus.failed,
      failureType: failureType,
      retryCount: existing.retryCount + 1,
      createdAt: existing.createdAt,
      priority: existing.priority,
      fileSizeBytes: existing.fileSizeBytes,
      metadata: existing.metadata,
      checksum: existing.checksum,
      errorMessage: errorMessage,
      nextRetryAt: nextRetryAt,
    );
    _notify();
  }

  @override
  Future<void> markPermanentlyFailed(
    String taskId, {
    required FailureType failureType,
    String? errorMessage,
  }) async {
    _update(
      taskId,
      (t) => t.copyWith(
        status: UploadStatus.permanentlyFailed,
        failureType: failureType,
        errorMessage: errorMessage,
      ),
    );
  }

  @override
  Future<void> markCancelled(String taskId) async {
    // nextRetryAt da null yapılır: §4 Kritik kural #5 (DB tutarlılığı)
    _update(
      taskId,
      (t) => UploadTask(
        taskId: t.taskId,
        filePath: t.filePath,
        sequenceNumber: t.sequenceNumber,
        status: UploadStatus.cancelled,
        retryCount: t.retryCount,
        createdAt: t.createdAt,
        fileSizeBytes: t.fileSizeBytes,
        metadata: t.metadata,
        failureType: t.failureType,
        errorMessage: t.errorMessage,
        checksum: t.checksum,
        // nextRetryAt kasıtlı olarak null — iptal edilen görev
        // backoff zaman damgası taşımamalı
      ),
    );
  }

  @override
  Future<void> markPending(String taskId) async {
    _update(
      taskId,
      (t) => UploadTask(
        taskId: t.taskId,
        filePath: t.filePath,
        sequenceNumber: t.sequenceNumber,
        status: UploadStatus.pending,
        retryCount: 0,
        createdAt: t.createdAt,
        fileSizeBytes: t.fileSizeBytes,
        metadata: t.metadata,
        // checksum, failureType, errorMessage, nextRetryAt sıfırlanır
      ),
    );
  }

  @override
  Future<void> updateChecksum(String taskId, String checksum) async {
    _update(taskId, (t) => t.copyWith(checksum: checksum));
  }

  // ── Lock / Heartbeat (in-memory no-op) ───────────────────────────────────

  @override
  Future<void> updateHeartbeat(String ownerId, DateTime acquiredAt) async {}

  @override
  Future<bool> tryAcquireLock(
    String ownerId,
    Duration staleLockThreshold,
  ) async {
    // Test ortamında tek worker varsayımı — her zaman kilidi alabilir.
    // Kilit yarışı testi için ayrı bir fixture kullanın (bkz. §10 test #10).
    return true;
  }

  @override
  Future<void> releaseLock() async {}

  @override
  Stream<void> watchLockUpdates() => const Stream.empty();

  @override
  Future<void> recoverStuckUploads() async {
    final stuck = _tasks.values
        .where((t) => t.status == UploadStatus.uploading)
        .toList();
    for (final task in stuck) {
      _tasks[task.taskId] = UploadTask(
        taskId: task.taskId,
        filePath: task.filePath,
        sequenceNumber: task.sequenceNumber,
        status: UploadStatus.pending,
        retryCount: task.retryCount,
        createdAt: task.createdAt,
        priority: task.priority,
        fileSizeBytes: task.fileSizeBytes,
        metadata: task.metadata,
        checksum: task.checksum,
        failureType: task.failureType,
        errorMessage: task.errorMessage,
        nextRetryAt: null,
      );
    }
    if (stuck.isNotEmpty) _notify();
  }

  @override
  Future<int> getNextSequenceNumber() async {
    if (_tasks.isEmpty) return 1;
    return _tasks.values
            .map((t) => t.sequenceNumber)
            .reduce((a, b) => a > b ? a : b) +
        1;
  }

  // ── Streams ───────────────────────────────────────────────────────────────

  @override
  Stream<QueueSummary> watchSummary({
    bool isPaused = false,
    bool pausedDueToAuth = false,
  }) {
    late StreamSubscription<void> sub;
    final controller = StreamController<QueueSummary>(sync: true);
    controller.onListen = () {
      controller.add(
        _buildSummary(isPaused: isPaused, pausedDueToAuth: pausedDueToAuth),
      );
      sub = _changeNotifier.stream.listen((_) {
        if (!controller.isClosed) {
          controller.add(
            _buildSummary(isPaused: isPaused, pausedDueToAuth: pausedDueToAuth),
          );
        }
      });
    };
    controller.onCancel = () => sub.cancel();
    return controller.stream;
  }

  QueueSummary _buildSummary({
    required bool isPaused,
    required bool pausedDueToAuth,
  }) {
    int pending = 0,
        uploading = 0,
        completed = 0,
        failed = 0,
        permanentlyFailed = 0,
        cancelled = 0,
        disk = 0;
    for (final t in _tasks.values) {
      switch (t.status) {
        case UploadStatus.pending:
          pending++;
          disk += t.fileSizeBytes ?? 0;
        case UploadStatus.uploading:
          uploading++;
          disk += t.fileSizeBytes ?? 0;
        case UploadStatus.completed:
          completed++;
        case UploadStatus.failed:
          failed++;
          disk += t.fileSizeBytes ?? 0;
        case UploadStatus.permanentlyFailed:
          permanentlyFailed++;
          disk += t.fileSizeBytes ?? 0;
        case UploadStatus.cancelled:
          cancelled++;
          disk += t.fileSizeBytes ?? 0;
      }
    }
    return QueueSummary(
      pending: pending,
      uploading: uploading,
      completed: completed,
      failed: failed,
      permanentlyFailed: permanentlyFailed,
      cancelled: cancelled,
      isPaused: isPaused,
      pausedDueToAuth: pausedDueToAuth,
      estimatedDiskUsageBytes: disk,
    );
  }

  @override
  Stream<List<UploadTask>> watchTasks({
    Set<UploadStatus>? statuses,
    int limit = 50,
    int offset = 0,
  }) {
    List<UploadTask> current() {
      var list = _tasks.values.toList()
        ..sort((a, b) {
          final cmp = b.priority.compareTo(a.priority);
          if (cmp != 0) return cmp;
          return a.sequenceNumber.compareTo(b.sequenceNumber);
        });
      if (statuses != null) {
        list = list.where((t) => statuses.contains(t.status)).toList();
      }
      return list.skip(offset).take(limit).toList();
    }

    late StreamSubscription<void> sub;
    final controller = StreamController<List<UploadTask>>(sync: true);
    controller.onListen = () {
      controller.add(current());
      sub = _changeNotifier.stream.listen((_) {
        if (!controller.isClosed) controller.add(current());
      });
    };
    controller.onCancel = () => sub.cancel();
    return controller.stream;
  }

  @override
  Stream<double> watchProgress(String taskId) {
    return _progressControllers
        .putIfAbsent(taskId, () => StreamController<double>.broadcast())
        .stream;
  }

  @override
  void updateProgress(String taskId, double ratio) {
    _progressControllers[taskId]?.add(ratio);
  }

  @override
  bool hasProgressListener(String taskId) {
    final ctrl = _progressControllers[taskId];
    return ctrl != null && ctrl.hasListener;
  }

  // ── Purge ─────────────────────────────────────────────────────────────────

  @override
  Future<void> purge(String taskId) async {
    final task = _tasks[taskId];
    if (task == null) return;
    if (task.status != UploadStatus.permanentlyFailed &&
        task.status != UploadStatus.cancelled) {
      throw StateError(
        'purge() yalnızca permanentlyFailed veya cancelled görevler için '
        'çağrılabilir (şu anki durum: ${task.status}).',
      );
    }
    _tasks.remove(taskId);
    _notify();
  }

  @override
  Future<void> purgeAllFailed() async {
    _tasks.removeWhere((_, t) => t.status == UploadStatus.permanentlyFailed);
    _notify();
  }

  @override
  Future<void> purgeAllCancelled() async {
    _tasks.removeWhere((_, t) => t.status == UploadStatus.cancelled);
    _notify();
  }

  @override
  Future<void> purgeAllCompleted() async {
    _tasks.removeWhere((_, t) => t.status == UploadStatus.completed);
    _notify();
  }

  @override
  Future<void> purgeAll({bool includePending = false}) async {
    await purgeAllFailed();
    await purgeAllCancelled();
    await purgeAllCompleted();
    if (includePending) {
      _tasks.removeWhere((_, t) => t.status == UploadStatus.pending);
      _notify();
    }
  }

  // ── Dispose ───────────────────────────────────────────────────────────────

  @override
  Future<void> dispose() async {
    await _changeNotifier.close();
    for (final c in _progressControllers.values) {
      await c.close();
    }
    _progressControllers.clear();
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  void _update(String taskId, UploadTask Function(UploadTask) updater) {
    final task = _tasks[taskId];
    if (task == null) return;
    _tasks[taskId] = updater(task);
    _notify();
  }

  /// Test yardımcısı: taskId'ye göre anlık göreve erişim.
  UploadTask? taskFor(String taskId) => _tasks[taskId];

  /// Test yardımcısı: tüm görevlerin listesi.
  List<UploadTask> get allTasks => _tasks.values.toList();
}
