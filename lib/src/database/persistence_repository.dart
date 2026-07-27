import '../models/queue_summary.dart';
import '../models/upload_status.dart';
import '../models/upload_task.dart';

/// Kalıcı depolama katmanının soyutlaması.
///
/// `QueueController` (worker) yalnızca bu arayüz üzerinden DB'ye erişir.
/// Bu ayrım, state machine'in tüm birim testlerinin gerçek Drift/SQLite
/// olmadan, `InMemoryPersistenceRepository` gibi bir mock üzerinden
/// koşabilmesini sağlar.
///
/// ## İmplementasyonlar
///
/// - [DriftPersistenceRepository]: Gerçek SQLite (production)
/// - `InMemoryPersistenceRepository` (`test/helpers/`): Birim testler için
abstract class PersistenceRepository {
  /// Depolamayı başlatır ve crash recovery yapar.
  ///
  /// `uploading` durumundaki görevleri `pending`'e döndürür ve
  /// `nextRetryAt = null` yapar (backoff beklemeden hemen alınabilir olsun).
  Future<void> init();

  /// Yeni bir görev kuyruğa ekler ve oluşturulan [UploadTask]'ı döner.
  ///
  /// [filePath] dosya yolu.
  /// [metadata] JSON serileştirilebilir anahtar-değer çiftleri.
  /// [fileSizeBytes] dosyanın bayt cinsinden boyutu (`stat()` ile doldurulur).
  /// [sequenceNumber] kuyruktaki mantıksal sıra.
  /// [taskId] UUID idempotency anahtarı.
  Future<UploadTask> enqueue({
    required String taskId,
    required String filePath,
    required int sequenceNumber,
    int? fileSizeBytes,
    Map<String, dynamic>? metadata,
  });

  /// Sıradaki işlenebilir görevi döner.
  ///
  /// `status = pending` VE (`nextRetryAt IS NULL` VEYA `nextRetryAt <= now`)
  /// koşuluna uyan, `sequenceNumber ASC` sıralı ilk görevi döner.
  /// Yoksa `null` döner.
  Future<UploadTask?> getNextPending(DateTime now);

  /// Görevi `uploading` durumuna geçirir.
  Future<void> markUploading(String taskId);

  /// Görevi `completed` durumuna geçirir ve checksum kaydeder.
  Future<void> markCompleted(String taskId, {String? checksum});

  /// Görevi `failed` durumuna geçirir ve bir sonraki deneme zamanını ayarlar.
  ///
  /// [nextRetryAt] `null` ise görev backoff beklemeden hemen alınabilir.
  Future<void> markFailed(
    String taskId, {
    required FailureType failureType,
    String? errorMessage,
    DateTime? nextRetryAt,
  });

  /// Görevi `permanentlyFailed` durumuna geçirir.
  Future<void> markPermanentlyFailed(
    String taskId, {
    required FailureType failureType,
    String? errorMessage,
  });

  /// Görevi `cancelled` durumuna geçirir.
  Future<void> markCancelled(String taskId);

  /// Görevi `pending` durumuna geri döndürür (manuel retry için).
  ///
  /// `retryCount` ve `nextRetryAt` sıfırlanır — görev ilk kez deneniyormuş
  /// gibi kuyruğun başına eklenir.
  Future<void> markPending(String taskId);

  /// Bir sonraki güvenli sekans numarasını döner.
  ///
  /// `MAX(sequenceNumber) + 1` sorgusuna dayanır; tablo boşsa `1` döner.
  /// `enqueue()` her çağrıldığında bu değer monoton artar.
  Future<int> getNextSequenceNumber();

  /// Görevin checksum'ını kaydeder (`uploading` sırasında hesaplanır).
  Future<void> updateChecksum(String taskId, String checksum);

  /// Worker heartbeat zamanını günceller.
  ///
  /// [ownerId]: worker/isolate kimliği (debug amaçlı).
  Future<void> updateHeartbeat(String ownerId, DateTime acquiredAt);

  /// Worker kilidini serbest bırakır.
  Future<void> releaseLock();

  /// `uploading` durumundaki tüm görevleri `pending`'e döndürür (recovery).
  Future<void> recoverStuckUploads();

  /// Kuyruğun anlık özetini yayınlayan reactive stream.
  ///
  /// `UploadTasks` tablosundaki **herhangi bir yazım** sonrası otomatik
  /// yeni bir [QueueSummary] yayınlar.
  Stream<QueueSummary> watchSummary({
    bool isPaused = false,
    bool pausedDueToAuth = false,
  });

  /// Filtrelenmiş görev listesini yayınlayan reactive stream.
  ///
  /// `statuses` null ise tüm durumları döner. [limit] ve [offset] ile
  /// sayfalama desteklenir.
  Stream<List<UploadTask>> watchTasks({
    Set<UploadStatus>? statuses,
    int limit = 50,
    int offset = 0,
  });

  /// Tek bir görevin upload ilerleme oranını (0.0–1.0) yayınlayan stream.
  ///
  /// Yalnızca `uploading` sırasında anlamlı değerler yayınlar.
  /// `QueueController`, `onProgress` callback'inden gelen byte oranlarını
  /// bu stream'e aktarır.
  Stream<double> watchProgress(String taskId);

  /// Upload ilerleme değerini günceller (`QueueController` tarafından çağrılır).
  void updateProgress(String taskId, double ratio);

  /// Tek bir görevi ve varsa sandbox kopyasını kalıcı olarak siler.
  ///
  /// Yalnızca `permanentlyFailed` veya `cancelled` durumundaki görevler
  /// silinebilir.
  Future<void> purge(String taskId);

  /// Tüm `permanentlyFailed` görevleri ve ilişkili sandbox kopyalarını siler.
  Future<void> purgeAllFailed();

  /// Tüm `cancelled` görevleri ve ilişkili sandbox kopyalarını siler.
  Future<void> purgeAllCancelled();

  /// Tüm `completed` görevlerin DB kayıtlarını siler.
  ///
  /// Sandbox kopyaları `completed` anında zaten silinmiştir;
  /// bu yalnızca DB satırlarının büyümesini önler.
  Future<void> purgeAllCompleted();

  /// Kaynakları serbest bırakır. [QueueController.dispose()] tarafından çağrılır.
  Future<void> dispose();
}
