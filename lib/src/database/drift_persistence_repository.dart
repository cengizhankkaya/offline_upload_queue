import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';

import '../models/metadata_codec.dart';
import '../models/queue_summary.dart';
import '../models/upload_status.dart';
import '../models/upload_task.dart' as model;
import 'database.dart';
import 'persistence_repository.dart';

/// [PersistenceRepository]'nin Drift/SQLite üzerinde çalışan gerçek implementasyonu.
///
/// Production kullanımı için [QueueController] tarafından oluşturulur.
/// Birim testler için [InMemoryPersistenceRepository] kullanın.
class DriftPersistenceRepository implements PersistenceRepository {
  final QueueDatabase _db;
  final MetadataCodec? _metadataCodec;

  /// Progress stream'leri: taskId → controller
  final _progressControllers = <String, StreamController<double>>{};

  DriftPersistenceRepository(this._db, {MetadataCodec? metadataCodec})
    : _metadataCodec = metadataCodec;

  // ── Init & Recovery ──────────────────────────────────────────────────────

  /// Depolamayı başlatır: `uploading` durumundaki görevleri `pending`'e döndürür
  /// (crash recovery).
  @override
  Future<void> init() async {
    await recoverStuckUploads();
  }

  /// `uploading` durumundaki tüm görevleri `pending`'e alır ve
  /// `nextRetryAt`'ı null yapar — backoff beklemeden hemen alınabilir olsunlar.
  @override
  Future<void> recoverStuckUploads() async {
    await (_db.update(
      _db.uploadTasks,
    )..where((t) => t.status.equalsValue(UploadStatus.uploading))).write(
      const UploadTasksCompanion(
        status: Value(UploadStatus.pending),
        nextRetryAt: Value(null),
      ),
    );
  }

  // ── Enqueue ───────────────────────────────────────────────────────────────

  /// Yeni bir görev oluşturur, DB'ye INSERT eder ve döndürür.
  @override
  Future<model.UploadTask> enqueue({
    required String taskId,
    required String filePath,
    required int sequenceNumber,
    int? fileSizeBytes,
    Map<String, dynamic>? metadata,
    int priority = 0,
  }) async {
    final now = DateTime.now();
    final companion = UploadTasksCompanion.insert(
      taskId: taskId,
      filePath: filePath,
      sequenceNumber: sequenceNumber,
      status: UploadStatus.pending,
      createdAt: now,
      priority: Value(priority),
      fileSizeBytes: Value(fileSizeBytes),
      metadataJson: Value(
        metadata != null
            ? (_metadataCodec?.encode(jsonEncode(metadata)) ??
                  jsonEncode(metadata))
            : null,
      ),
    );
    await _db.into(_db.uploadTasks).insert(companion);
    return model.UploadTask(
      taskId: taskId,
      filePath: filePath,
      sequenceNumber: sequenceNumber,
      status: UploadStatus.pending,
      retryCount: 0,
      createdAt: now,
      priority: priority,
      fileSizeBytes: fileSizeBytes,
      metadata: metadata,
    );
  }

  // ── Query ─────────────────────────────────────────────────────────────────

  /// `status = pending` VE `(nextRetryAt IS NULL OR nextRetryAt <= now)` koşuluna
  /// uyan, `sequenceNumber ASC` sıralı ilk görevi döner. Yoksa `null` döner.
  @override
  Future<model.UploadTask?> getNextPending(DateTime now) async {
    final query = _db.select(_db.uploadTasks)
      ..where(
        (t) =>
            t.status.equalsValue(UploadStatus.pending) &
            (t.nextRetryAt.isNull() | t.nextRetryAt.isSmallerOrEqualValue(now)),
      )
      ..orderBy([
        (t) => OrderingTerm.desc(t.priority),
        (t) => OrderingTerm.asc(t.sequenceNumber),
      ])
      ..limit(1);
    final row = await query.getSingleOrNull();
    return row == null ? null : _rowToTask(row);
  }

  // ── State transitions ─────────────────────────────────────────────────────

  /// Görevi `uploading` durumuna geçirir.
  @override
  Future<void> markUploading(String taskId) async {
    await (_db.update(
      _db.uploadTasks,
    )..where((t) => t.taskId.equals(taskId))).write(
      const UploadTasksCompanion(status: Value(UploadStatus.uploading)),
    );
  }

  /// Görevi `completed` durumuna geçirir ve checksum kaydeder.
  @override
  Future<void> markCompleted(String taskId, {String? checksum}) async {
    await (_db.update(
      _db.uploadTasks,
    )..where((t) => t.taskId.equals(taskId))).write(
      UploadTasksCompanion(
        status: const Value(UploadStatus.completed),
        checksum: Value(checksum),
      ),
    );
  }

  /// Görevi `failed` durumuna geçirir, `retryCount`'ı bir artırır ve
  /// bir sonraki deneme zamanını [nextRetryAt] olarak kaydeder.
  @override
  Future<void> markFailed(
    String taskId, {
    required FailureType failureType,
    String? errorMessage,
    DateTime? nextRetryAt,
  }) async {
    await _db.transaction(() async {
      // retryCount'u artır
      final current = await (_db.select(
        _db.uploadTasks,
      )..where((t) => t.taskId.equals(taskId))).getSingleOrNull();
      if (current == null) return;

      await (_db.update(
        _db.uploadTasks,
      )..where((t) => t.taskId.equals(taskId))).write(
        UploadTasksCompanion(
          status: const Value(UploadStatus.failed),
          failureType: Value(failureType),
          errorMessage: Value(errorMessage),
          nextRetryAt: Value(nextRetryAt),
          retryCount: Value(current.retryCount + 1),
        ),
      );
    });
  }

  /// Görevi `permanentlyFailed` durumuna geçirir — otomatik retry yok.
  @override
  Future<void> markPermanentlyFailed(
    String taskId, {
    required FailureType failureType,
    String? errorMessage,
  }) async {
    await (_db.update(
      _db.uploadTasks,
    )..where((t) => t.taskId.equals(taskId))).write(
      UploadTasksCompanion(
        status: const Value(UploadStatus.permanentlyFailed),
        failureType: Value(failureType),
        errorMessage: Value(errorMessage),
      ),
    );
  }

  /// Görevi `cancelled` durumuna geçirir ve `nextRetryAt`'ı null yapar.
  @override
  Future<void> markCancelled(String taskId) async {
    // nextRetryAt da null yapılır: §4 Kritik kural #5 — iptal edilen görev
    // backoff zaman damgası taşımamalı (DB tutarlılığı)
    await (_db.update(
      _db.uploadTasks,
    )..where((t) => t.taskId.equals(taskId))).write(
      const UploadTasksCompanion(
        status: Value(UploadStatus.cancelled),
        nextRetryAt: Value(null),
      ),
    );
  }

  /// Görevi `pending` durumuna döndürür; `retryCount`, `nextRetryAt`,
  /// `failureType`, `errorMessage` ve `checksum` sıfırlanır.
  @override
  Future<void> markPending(String taskId) async {
    await (_db.update(
      _db.uploadTasks,
    )..where((t) => t.taskId.equals(taskId))).write(
      const UploadTasksCompanion(
        status: Value(UploadStatus.pending),
        retryCount: Value(0),
        nextRetryAt: Value(null),
        failureType: Value(null),
        errorMessage: Value(null),
        checksum: Value(null),
      ),
    );
  }

  /// Görevin SHA-256 checksum değerini kaydeder (`uploading` sırasında
  /// hesaplanarak çağrılır).
  @override
  Future<void> updateChecksum(String taskId, String checksum) async {
    await (_db.update(_db.uploadTasks)..where((t) => t.taskId.equals(taskId)))
        .write(UploadTasksCompanion(checksum: Value(checksum)));
  }

  // ── Sequence Number ───────────────────────────────────────────────────────

  /// `MAX(sequenceNumber) + 1` sorgusunu döner; tablo boşsa `1` döner.
  @override
  Future<int> getNextSequenceNumber() async {
    final result = await _db
        .customSelect(
          'SELECT COALESCE(MAX(sequence_number), 0) + 1 AS next_seq FROM upload_tasks',
          readsFrom: {_db.uploadTasks},
        )
        .getSingle();
    return result.read<int>('next_seq');
  }

  // ── Lock / Heartbeat ──────────────────────────────────────────────────────

  /// Atomik koşullu UPDATE ile worker kilidi almayı dener.
  ///
  /// `staleLockThreshold`'dan eski bir kilit varsa devralır ve `true` döner;
  /// aktif bir başka worker kilidi tutuyorsa `false` döner.
  @override
  Future<bool> tryAcquireLock(
    String ownerId,
    Duration staleLockThreshold,
  ) async {
    final staleThreshold = DateTime.now().subtract(staleLockThreshold);
    final now = DateTime.now();

    // 1. Kilit satırı yoksa oluştur — varsa dokunma (IGNORE).
    //    Çok eski bir acquiredAt ile başlatılır; böylece ilk worker
    //    hemen stale olarak değerlendirip kilidi alabilir.
    await _db.customStatement(
      'INSERT OR IGNORE INTO active_worker_lock (id, acquired_at, owner_id) '
      'VALUES (0, ?, NULL)',
      [DateTime.fromMillisecondsSinceEpoch(0).toIso8601String()],
    );

    // 2. Atomik koşullu UPDATE: acquired_at < staleThreshold ise devral.
    //    SQLite'ın tek yazar garantisi sayesinde iki worker aynı anda
    //    bu UPDATE'ten rowsAffected==1 alamaz (bkz. §7).
    final updated = await _db.customUpdate(
      'UPDATE active_worker_lock '
      'SET acquired_at = ?, owner_id = ? '
      'WHERE id = 0 AND acquired_at < ?',
      variables: [
        Variable.withDateTime(now),
        Variable.withString(ownerId),
        Variable.withDateTime(staleThreshold),
      ],
      updates: {_db.activeWorkerLock},
    );

    return updated == 1;
  }

  /// Worker heartbeat zamanını günceller — kilidin stale sayılmasını engeller.
  @override
  Future<void> updateHeartbeat(String ownerId, DateTime acquiredAt) async {
    await _db.customUpdate(
      'UPDATE active_worker_lock SET acquired_at = ?, owner_id = ? WHERE id = 0',
      variables: [
        Variable.withDateTime(acquiredAt),
        Variable.withString(ownerId),
      ],
      updates: {_db.activeWorkerLock},
    );
  }

  /// Worker kilidini serbest bırakır (`dispose()` tarafından çağrılır).
  @override
  Future<void> releaseLock() async {
    await (_db.delete(_db.activeWorkerLock)..where((t) => t.id.equals(0))).go();
  }

  /// Worker kilidi tablosundaki değişiklikleri yayınlayan stream.
  @override
  Stream<void> watchLockUpdates() {
    return _db.tableUpdates(TableUpdateQuery.onTable(_db.activeWorkerLock));
  }

  // ── Reactive Streams ──────────────────────────────────────────────────────

  /// Kuyruğun anlık özetini yayınlayan reaktif stream.
  ///
  /// `UploadTasks` tablosundaki herhangi bir yazım sonrası otomatik
  /// yeni bir [QueueSummary] yayınlar.
  @override
  Stream<QueueSummary> watchSummary({
    bool isPaused = false,
    bool pausedDueToAuth = false,
  }) {
    // Durum sayıları: GROUP BY status ile her durum için COUNT ve SUM
    // Disk kullanımı: completed hariç tüm durumlar (dosyaları zaten silinmiş)
    final query = _db.customSelect(
      '''
      SELECT
        SUM(CASE WHEN status = ${UploadStatus.pending.index} THEN 1 ELSE 0 END) AS cnt_pending,
        SUM(CASE WHEN status = ${UploadStatus.uploading.index} THEN 1 ELSE 0 END) AS cnt_uploading,
        SUM(CASE WHEN status = ${UploadStatus.completed.index} THEN 1 ELSE 0 END) AS cnt_completed,
        SUM(CASE WHEN status = ${UploadStatus.failed.index} THEN 1 ELSE 0 END) AS cnt_failed,
        SUM(CASE WHEN status = ${UploadStatus.permanentlyFailed.index} THEN 1 ELSE 0 END) AS cnt_permanently_failed,
        SUM(CASE WHEN status = ${UploadStatus.cancelled.index} THEN 1 ELSE 0 END) AS cnt_cancelled,
        SUM(CASE WHEN status != ${UploadStatus.completed.index} THEN COALESCE(file_size_bytes, 0) ELSE 0 END) AS disk_bytes
      FROM upload_tasks
      ''',
      readsFrom: {_db.uploadTasks},
    );

    return query.watch().map((rows) {
      if (rows.isEmpty) {
        return QueueSummary(
          pending: 0,
          uploading: 0,
          completed: 0,
          failed: 0,
          permanentlyFailed: 0,
          cancelled: 0,
          isPaused: isPaused,
          pausedDueToAuth: pausedDueToAuth,
          estimatedDiskUsageBytes: 0,
        );
      }
      final row = rows.first;
      return QueueSummary(
        pending: row.read<int>('cnt_pending'),
        uploading: row.read<int>('cnt_uploading'),
        completed: row.read<int>('cnt_completed'),
        failed: row.read<int>('cnt_failed'),
        permanentlyFailed: row.read<int>('cnt_permanently_failed'),
        cancelled: row.read<int>('cnt_cancelled'),
        isPaused: isPaused,
        pausedDueToAuth: pausedDueToAuth,
        estimatedDiskUsageBytes: row.read<int?>('disk_bytes') ?? 0,
      );
    });
  }

  /// Filtrelenmiş görev listesini yayınlayan reaktif stream.
  ///
  /// [statuses] null ise tüm durumları döner. [limit]/[offset] ile
  /// sayfalama desteklenir.
  @override
  Stream<List<model.UploadTask>> watchTasks({
    Set<UploadStatus>? statuses,
    int limit = 50,
    int offset = 0,
  }) {
    final query = _db.select(_db.uploadTasks);

    if (statuses != null && statuses.isNotEmpty) {
      query.where((t) => t.status.isIn(statuses.map((s) => s.index).toList()));
    }

    query
      ..orderBy([
        (t) => OrderingTerm.desc(t.priority),
        (t) => OrderingTerm.asc(t.sequenceNumber),
      ])
      ..limit(limit, offset: offset);

    return query.watch().map((rows) => rows.map(_rowToTask).toList());
  }

  /// Tek bir görevin upload ilerleme oranını (0.0–1.0) yayınlayan stream.
  @override
  Stream<double> watchProgress(String taskId) {
    return _progressControllers
        .putIfAbsent(taskId, () => StreamController<double>.broadcast())
        .stream;
  }

  /// Upload ilerleme değerini stream'e yazar ([QueueController] tarafından
  /// çağrılır).
  @override
  void updateProgress(String taskId, double ratio) {
    _progressControllers[taskId]?.add(ratio);
  }

  // ── Purge ─────────────────────────────────────────────────────────────────

  /// Görevi ve varsa sandbox kopyasını kalıcı olarak siler.
  @override
  Future<void> purge(String taskId) async {
    final task = await (_db.select(
      _db.uploadTasks,
    )..where((t) => t.taskId.equals(taskId))).getSingleOrNull();
    if (task == null) return;

    await _deleteSandboxFile(task.filePath);
    await (_db.delete(
      _db.uploadTasks,
    )..where((t) => t.taskId.equals(taskId))).go();
  }

  /// Tüm `permanentlyFailed` görevleri ve sandbox kopyalarını siler.
  @override
  Future<void> purgeAllFailed() async {
    await _purgeByStatus(UploadStatus.permanentlyFailed);
  }

  /// Tüm `cancelled` görevleri ve sandbox kopyalarını siler.
  @override
  Future<void> purgeAllCancelled() async {
    await _purgeByStatus(UploadStatus.cancelled);
  }

  /// Tüm `completed` görevlerin DB kayıtlarını siler.
  ///
  /// Sandbox kopyaları zaten `completed` anında silinmiştir.
  @override
  Future<void> purgeAllCompleted() async {
    // Completed görevlerin sandbox dosyaları zaten silinmiş — yalnızca DB kaydı
    await (_db.delete(
      _db.uploadTasks,
    )..where((t) => t.status.equalsValue(UploadStatus.completed))).go();
  }

  @override
  Future<void> purgeAll({bool includePending = false}) async {
    await purgeAllFailed();
    await purgeAllCancelled();
    await purgeAllCompleted();

    if (includePending) {
      await _purgeByStatus(UploadStatus.pending);
    }
  }

  Future<void> _purgeByStatus(UploadStatus status) async {
    final rows = await (_db.select(
      _db.uploadTasks,
    )..where((t) => t.status.equalsValue(status))).get();

    for (final row in rows) {
      await _deleteSandboxFile(row.filePath);
    }

    await (_db.delete(
      _db.uploadTasks,
    )..where((t) => t.status.equalsValue(status))).go();
  }

  Future<void> _deleteSandboxFile(String filePath) async {
    try {
      final file = File(filePath);
      if (await file.exists()) await file.delete();
    } catch (_) {
      // Dosya silme hatası DB işlemini engellemez
    }
  }

  // ── Dispose ───────────────────────────────────────────────────────────────

  /// Progress stream controller'larını kapatır ve DB bağlantısını serbest
  /// bırakır.
  @override
  Future<void> dispose() async {
    for (final c in _progressControllers.values) {
      await c.close();
    }
    _progressControllers.clear();
    await _db.close();
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  model.UploadTask _rowToTask(UploadTaskData row) {
    Map<String, dynamic>? metadata;
    if (row.metadataJson != null) {
      final plainJson =
          _metadataCodec?.decode(row.metadataJson!) ?? row.metadataJson!;
      metadata = jsonDecode(plainJson) as Map<String, dynamic>;
    }
    return model.UploadTask(
      taskId: row.taskId,
      filePath: row.filePath,
      sequenceNumber: row.sequenceNumber,
      status: row.status,
      failureType: row.failureType,
      retryCount: row.retryCount,
      metadata: metadata,
      checksum: row.checksum,
      fileSizeBytes: row.fileSizeBytes,
      errorMessage: row.errorMessage,
      createdAt: row.createdAt,
      nextRetryAt: row.nextRetryAt,
      priority: row.priority,
    );
  }
}
