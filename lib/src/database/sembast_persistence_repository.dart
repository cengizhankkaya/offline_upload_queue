import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sembast/sembast_io.dart';

import '../models/metadata_codec.dart';
import '../models/queue_summary.dart';
import '../models/upload_status.dart';
import '../models/upload_task.dart';
import 'persistence_repository.dart';
import 'sembast_codec.dart';

/// [PersistenceRepository]'nin sembast (pure-Dart) üzerinde çalışan implementasyonu.
///
/// ## Şifreleme Uyarısı
///
/// `encryptionKey` verildiğinde sembast'ın örnek codec'i (Salsa20+SHA256)
/// kullanılır. Bu codec sembast kaynak deposundaki **denetlenmemiş örnek
/// koddur** — bağımsız güvenlik denetiminden geçmemiştir. HIPAA, GDPR veya
/// benzeri compliance gerektiren senaryolar için bağımsız denetlenmiş bir
/// şifreleme çözümü kullanın.
///
/// ## Cross-Isolate Erişim
///
/// Sembast'ın cooperator mekanizması single-Dart-process içinde çalışır.
/// Aynı `.db` dosyasına iki ayrı Dart isolate/engine'den eşzamanlı erişim
/// **güvenli değildir**. BackgroundTaskRunner bu sınıfı `init()` ile açıp
/// `dispose()` ile kapatır; ana UploadQueue worker'ı bu sürede çalışmaz
/// (her biri kendi isolate'inde bağımsız init/dispose yapar).
///
/// ## Veri Modeli
///
/// - `taskStore`: `StoreRef<String, Map<String, Object?>>` — key = taskId
/// - `lockStore`: `StoreRef<String, Map<String, Object?>>` — key = `'lock'`
/// - DateTime: ISO 8601 string olarak saklanır
/// - Enum'lar: `.index` (int) olarak saklanır
/// - metadata: doğrudan nested Map — JSON encode/decode adımı yok
///   (MetadataCodec varsa JSON string üzerinden encode/decode yapılır)
class SembastPersistenceRepository implements PersistenceRepository {
  final String boxName;
  final String? encryptionKey;
  final MetadataCodec? _metadataCodec;

  late Database _db;

  /// Görev kayıtları — key = taskId
  final _taskStore = stringMapStoreFactory.store('tasks');

  /// Worker kilidi — tek kayıt, key = 'lock'
  final _lockStore = stringMapStoreFactory.store('worker_lock');

  /// Progress stream controller'ları: taskId → controller
  final _progressControllers = <String, StreamController<double>>{};

  SembastPersistenceRepository({
    this.boxName = 'default',
    this.encryptionKey,
    MetadataCodec? metadataCodec,
  }) : _metadataCodec = metadataCodec;

  // ── Init & Recovery ──────────────────────────────────────────────────────

  /// Veritabanını açar ve crash recovery yapar.
  ///
  /// `uploading` durumundaki görevleri `pending`'e döndürür ve
  /// `nextRetryAt`'ı null yapar.
  @override
  Future<void> init() async {
    final dbFolder = await getApplicationSupportDirectory();
    final dbPath = p.join(dbFolder.path, '$boxName.db');

    final codec = encryptionKey != null
        ? getEncryptSembastCodec(password: encryptionKey!)
        : null;

    _db = await databaseFactoryIo.openDatabase(dbPath, codec: codec);

    await recoverStuckUploads();
  }

  /// `uploading` durumundaki tüm görevleri `pending`'e döndürür.
  @override
  Future<void> recoverStuckUploads() async {
    final finder = Finder(
      filter: Filter.equals('status', UploadStatus.uploading.index),
    );
    final stuck = await _taskStore.find(_db, finder: finder);

    for (final snapshot in stuck) {
      final updated = Map<String, Object?>.from(snapshot.value)
        ..['status'] = UploadStatus.pending.index
        ..['nextRetryAt'] = null;
      await _taskStore.record(snapshot.key).put(_db, updated);
    }
  }

  // ── Enqueue ───────────────────────────────────────────────────────────────

  /// Yeni bir görevi atomik olarak oluşturur, DB'ye yazar ve döndürür.
  ///
  /// Sequence numarası sembast transaction içinde MAX+1 olarak atomik üretilir.
  /// Dışarıdan geçilen [sequenceNumber] yoksayılır; transaction garantili
  /// değer kullanılır.
  @override
  Future<UploadTask> enqueue({
    required String taskId,
    required String filePath,
    required int sequenceNumber,
    int? fileSizeBytes,
    Map<String, dynamic>? metadata,
    int priority = 0,
  }) async {
    final now = DateTime.now();
    late UploadTask result;

    // Sequence numarası ve insert tek atomik transaction içinde:
    // Aynı process'teki concurrent Future'ların interleave etmesini engeller.
    await _db.transaction((txn) async {
      // MAX(sequenceNumber) + 1 — sembast transactional read garantili
      final allSnapshots = await _taskStore.find(txn);
      final nextSeq = allSnapshots.isEmpty
          ? 1
          : allSnapshots
                    .map((s) => (s.value['sequenceNumber'] as int?) ?? 0)
                    .reduce((a, b) => a > b ? a : b) +
                1;

      // metadata: MetadataCodec varsa JSON string üzerinden encode, yoksa direkt Map
      Object? storedMetadata;
      bool isEncoded = false;
      if (metadata != null) {
        if (_metadataCodec != null) {
          final jsonStr = jsonEncode(metadata);
          storedMetadata = _metadataCodec.encode(jsonStr);
          isEncoded = true;
        } else {
          storedMetadata = metadata;
        }
      }

      final record = <String, Object?>{
        'filePath': filePath,
        'sequenceNumber': nextSeq,
        'status': UploadStatus.pending.index,
        'failureType': null,
        'retryCount': 0,
        'metadata': storedMetadata,
        'metadataEncoded': isEncoded,
        'checksum': null,
        'fileSizeBytes': fileSizeBytes,
        'errorMessage': null,
        'createdAt': now.toIso8601String(),
        'nextRetryAt': null,
        'priority': priority,
      };

      await _taskStore.record(taskId).put(txn, record);

      result = UploadTask(
        taskId: taskId,
        filePath: filePath,
        sequenceNumber: nextSeq,
        status: UploadStatus.pending,
        retryCount: 0,
        createdAt: now,
        priority: priority,
        fileSizeBytes: fileSizeBytes,
        metadata: metadata,
      );
    });

    return result;
  }

  // ── Query ─────────────────────────────────────────────────────────────────

  /// `status = pending` VE (`nextRetryAt IS NULL` VEYA `nextRetryAt <= now`)
  /// koşuluna uyan, `priority DESC, sequenceNumber ASC` sıralı ilk görevi döner.
  @override
  Future<UploadTask?> getNextPending(DateTime now) async {
    final allPending = await _taskStore.find(
      _db,
      finder: Finder(
        filter: Filter.equals('status', UploadStatus.pending.index),
      ),
    );

    final candidates =
        allPending.where((s) {
          final nextRetryAtStr = s.value['nextRetryAt'] as String?;
          if (nextRetryAtStr == null) return true;
          return !DateTime.parse(nextRetryAtStr).isAfter(now);
        }).toList()..sort((a, b) {
          final pa = (a.value['priority'] as int?) ?? 0;
          final pb = (b.value['priority'] as int?) ?? 0;
          final cmp = pb.compareTo(pa); // DESC
          if (cmp != 0) return cmp;
          final sa = (a.value['sequenceNumber'] as int?) ?? 0;
          final sb = (b.value['sequenceNumber'] as int?) ?? 0;
          return sa.compareTo(sb); // ASC
        });

    if (candidates.isEmpty) return null;
    return _snapshotToTask(candidates.first.key, candidates.first.value);
  }

  // ── State transitions ─────────────────────────────────────────────────────

  @override
  Future<void> markUploading(String taskId) async {
    await _updateTask(taskId, {'status': UploadStatus.uploading.index});
  }

  @override
  Future<void> markCompleted(String taskId, {String? checksum}) async {
    final fields = <String, Object?>{'status': UploadStatus.completed.index};
    if (checksum != null) fields['checksum'] = checksum;
    await _updateTask(taskId, fields);
  }

  @override
  Future<void> markFailed(
    String taskId, {
    required FailureType failureType,
    String? errorMessage,
    DateTime? nextRetryAt,
  }) async {
    // retryCount atomik artış: mevcut değeri oku, 1 ekle
    await _db.transaction((txn) async {
      final record = await _taskStore.record(taskId).get(txn);
      if (record == null) return;
      final current = Map<String, Object?>.from(record);
      current['status'] = UploadStatus.failed.index;
      current['failureType'] = failureType.index;
      current['errorMessage'] = errorMessage;
      current['nextRetryAt'] = nextRetryAt?.toIso8601String();
      current['retryCount'] = ((current['retryCount'] as int?) ?? 0) + 1;
      await _taskStore.record(taskId).put(txn, current);
    });
  }

  @override
  Future<void> markPermanentlyFailed(
    String taskId, {
    required FailureType failureType,
    String? errorMessage,
  }) async {
    await _updateTask(taskId, {
      'status': UploadStatus.permanentlyFailed.index,
      'failureType': failureType.index,
      'errorMessage': errorMessage,
    });
  }

  @override
  Future<void> markCancelled(String taskId) async {
    // nextRetryAt da null yapılır: §4 Kritik kural #5 — iptal edilen görev
    // backoff zaman damgası taşımamalı (DB tutarlılığı)
    await _updateTask(taskId, {
      'status': UploadStatus.cancelled.index,
      'nextRetryAt': null,
    });
  }

  @override
  Future<void> markPending(String taskId) async {
    // retryCount, nextRetryAt, failureType, errorMessage, checksum sıfırlanır
    await _updateTask(taskId, {
      'status': UploadStatus.pending.index,
      'retryCount': 0,
      'nextRetryAt': null,
      'failureType': null,
      'errorMessage': null,
      'checksum': null,
    });
  }

  @override
  Future<void> updateChecksum(String taskId, String checksum) async {
    await _updateTask(taskId, {'checksum': checksum});
  }

  // ── Sequence Number ───────────────────────────────────────────────────────

  /// Bir sonraki tahmini sequence numarasını döner.
  ///
  /// Not: Asıl atomik sequence üretimi `enqueue()` içindeki transaction'da
  /// yapılır. Bu metot QueueController'a bir ipucu değeri sağlar; gerçek
  /// depolanan değer `enqueue()` transaction'ı tarafından belirlenir.
  @override
  Future<int> getNextSequenceNumber() async {
    final all = await _taskStore.find(_db);
    if (all.isEmpty) return 1;
    return all
            .map((s) => (s.value['sequenceNumber'] as int?) ?? 0)
            .reduce((a, b) => a > b ? a : b) +
        1;
  }

  // ── Lock / Heartbeat ──────────────────────────────────────────────────────

  /// Atomik koşullu UPDATE ile worker kilidi almayı dener.
  ///
  /// Kilit yoksa veya stale ise ([staleLockThreshold]'dan eski `acquiredAt`)
  /// kilidi [ownerId]'ye aktarır ve `true` döner.
  ///
  /// **Kapsam:** Bu garanti yalnızca aynı Dart process içindeki concurrent
  /// Future'lar için geçerlidir. Sembast transaction serialize mekanizması
  /// iki async görevi sıraya sokar. Farklı isolate/engine'ler bu kilidi
  /// paylaşamaz — mimari olarak OQ-1 Alternatif A ile ele alınmıştır
  /// (arka plan isolate init yaparken ana taraf zaten dispose edilmiş olur).
  @override
  Future<bool> tryAcquireLock(
    String ownerId,
    Duration staleLockThreshold,
  ) async {
    bool acquired = false;
    final staleThreshold = DateTime.now().subtract(staleLockThreshold);
    final now = DateTime.now();

    await _db.transaction((txn) async {
      final existing = await _lockStore.record('lock').get(txn);

      final bool shouldAcquire;
      if (existing == null) {
        shouldAcquire = true;
      } else {
        final acquiredAt = DateTime.parse(existing['acquiredAt'] as String);
        shouldAcquire = acquiredAt.isBefore(staleThreshold);
      }

      if (shouldAcquire) {
        await _lockStore.record('lock').put(txn, {
          'acquiredAt': now.toIso8601String(),
          'ownerId': ownerId,
        });
        acquired = true;
      }
    });

    return acquired;
  }

  @override
  Future<void> updateHeartbeat(String ownerId, DateTime acquiredAt) async {
    await _lockStore.record('lock').put(_db, {
      'acquiredAt': acquiredAt.toIso8601String(),
      'ownerId': ownerId,
    });
  }

  @override
  Future<void> releaseLock() async {
    await _lockStore.record('lock').delete(_db);
  }

  @override
  Stream<void> watchLockUpdates() {
    return _lockStore.query().onSnapshots(_db).map((_) {});
  }

  // ── Reactive Streams ──────────────────────────────────────────────────────

  @override
  Stream<QueueSummary> watchSummary({
    bool isPaused = false,
    bool pausedDueToAuth = false,
  }) {
    return _taskStore.query().onSnapshots(_db).map((snapshots) {
      int pending = 0,
          uploading = 0,
          completed = 0,
          failed = 0,
          permanentlyFailed = 0,
          cancelled = 0,
          diskBytes = 0;

      for (final s in snapshots) {
        final statusIdx = (s.value['status'] as int?) ?? 0;
        final status = UploadStatus.values[statusIdx];
        final sizeBytes = (s.value['fileSizeBytes'] as int?) ?? 0;

        switch (status) {
          case UploadStatus.pending:
            pending++;
            diskBytes += sizeBytes;
          case UploadStatus.uploading:
            uploading++;
            diskBytes += sizeBytes;
          case UploadStatus.completed:
            completed++;
          // completed dosyaların sandbox kopyaları zaten silinmiş
          case UploadStatus.failed:
            failed++;
            diskBytes += sizeBytes;
          case UploadStatus.permanentlyFailed:
            permanentlyFailed++;
            diskBytes += sizeBytes;
          case UploadStatus.cancelled:
            cancelled++;
            diskBytes += sizeBytes;
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
        estimatedDiskUsageBytes: diskBytes,
      );
    });
  }

  @override
  Stream<List<UploadTask>> watchTasks({
    Set<UploadStatus>? statuses,
    int limit = 50,
    int offset = 0,
  }) {
    Filter? filter;
    if (statuses != null && statuses.isNotEmpty) {
      filter = Filter.or(
        statuses.map((s) => Filter.equals('status', s.index)).toList(),
      );
    }

    // Sembast'ın Finder sıralaması: priority DESC, sequenceNumber ASC
    final finder = Finder(
      filter: filter,
      sortOrders: [
        SortOrder('priority', false), // false = descending
        SortOrder('sequenceNumber'),
      ],
      limit: limit,
      offset: offset,
    );

    return _taskStore
        .query(finder: finder)
        .onSnapshots(_db)
        .map(
          (snapshots) =>
              snapshots.map((s) => _snapshotToTask(s.key, s.value)).toList(),
        );
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

  // ── Purge ─────────────────────────────────────────────────────────────────

  @override
  Future<void> purge(String taskId) async {
    final record = await _taskStore.record(taskId).get(_db);
    if (record == null) return;

    await _deleteSandboxFile(record['filePath'] as String?);
    await _taskStore.record(taskId).delete(_db);
  }

  @override
  Future<void> purgeAllFailed() async {
    await _purgeByStatus(UploadStatus.permanentlyFailed);
  }

  @override
  Future<void> purgeAllCancelled() async {
    await _purgeByStatus(UploadStatus.cancelled);
  }

  @override
  Future<void> purgeAllCompleted() async {
    // Completed görevlerin sandbox dosyaları zaten silinmiş — yalnızca DB kaydı
    await _taskStore.delete(
      _db,
      finder: Finder(
        filter: Filter.equals('status', UploadStatus.completed.index),
      ),
    );
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
    final rows = await _taskStore.find(
      _db,
      finder: Finder(filter: Filter.equals('status', status.index)),
    );

    for (final row in rows) {
      await _deleteSandboxFile(row.value['filePath'] as String?);
    }

    await _taskStore.delete(
      _db,
      finder: Finder(filter: Filter.equals('status', status.index)),
    );
  }

  Future<void> _deleteSandboxFile(String? filePath) async {
    if (filePath == null) return;
    try {
      final file = File(filePath);
      if (await file.exists()) await file.delete();
    } catch (_) {
      // Dosya silme hatası DB işlemini engellemez
    }
  }

  // ── Dispose ───────────────────────────────────────────────────────────────

  @override
  Future<void> dispose() async {
    for (final c in _progressControllers.values) {
      await c.close();
    }
    _progressControllers.clear();
    await _db.close();
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  /// Sembast record'unu [UploadTask] modeline dönüştürür.
  UploadTask _snapshotToTask(String taskId, Map<String, Object?> value) {
    final statusIdx = (value['status'] as int?) ?? 0;
    final failureTypeIdx = value['failureType'] as int?;
    final nextRetryAtStr = value['nextRetryAt'] as String?;
    final createdAtStr = value['createdAt'] as String?;

    // Metadata: MetadataCodec varsa JSON string üzerinden decode, yoksa direkt Map
    Map<String, dynamic>? metadata;
    final rawMetadata = value['metadata'];
    final isEncoded = (value['metadataEncoded'] as bool?) ?? false;
    if (rawMetadata != null) {
      if (isEncoded && _metadataCodec != null) {
        final decoded = _metadataCodec.decode(rawMetadata as String);
        metadata = jsonDecode(decoded) as Map<String, dynamic>;
      } else {
        metadata = (rawMetadata as Map).cast<String, dynamic>();
      }
    }

    return UploadTask(
      taskId: taskId,
      filePath: (value['filePath'] as String?) ?? '',
      sequenceNumber: (value['sequenceNumber'] as int?) ?? 0,
      status: UploadStatus.values[statusIdx],
      failureType: failureTypeIdx != null
          ? FailureType.values[failureTypeIdx]
          : null,
      retryCount: (value['retryCount'] as int?) ?? 0,
      metadata: metadata,
      checksum: value['checksum'] as String?,
      fileSizeBytes: value['fileSizeBytes'] as int?,
      errorMessage: value['errorMessage'] as String?,
      createdAt: createdAtStr != null
          ? DateTime.parse(createdAtStr)
          : DateTime.now(),
      nextRetryAt: nextRetryAtStr != null
          ? DateTime.parse(nextRetryAtStr)
          : null,
      priority: (value['priority'] as int?) ?? 0,
    );
  }

  /// Mevcut bir kaydı kısmen günceller (yalnızca verilen alanları değiştirir).
  Future<void> _updateTask(String taskId, Map<String, Object?> fields) async {
    await _db.transaction((txn) async {
      final existing = await _taskStore.record(taskId).get(txn);
      if (existing == null) return;
      final updated = Map<String, Object?>.from(existing)..addAll(fields);
      await _taskStore.record(taskId).put(txn, updated);
    });
  }
}
