import '../models/queue_summary.dart';
import '../models/upload_status.dart';
import '../models/upload_task.dart';

/// Kalıcı depolama katmanının soyutlaması.
///
/// `QueueController` (worker) yalnızca bu arayüz üzerinden DB'ye erişir.
/// Bu ayrım, state machine'in tüm birim testlerinin gerçek sembast
/// olmadan, `InMemoryPersistenceRepository` gibi bir mock üzerinden
/// koşabilmesini sağlar.
///
/// ## İmplementasyonlar
///
/// - [SembastPersistenceRepository]: Gerçek sembast dosya store'u (production)
/// - `InMemoryPersistenceRepository` (`test/helpers/`): Birim testler için
abstract class PersistenceRepository {
  /// Depolamayı açar (dosya/DB bağlantısı).
  ///
  /// Crash recovery ([recoverStuckUploads]) bu metotta **yapılmaz** —
  /// worker kilidi alındıktan sonra [QueueController] tarafından çağrılır.
  /// Böylece başka bir worker aktif yükleme yapıyorken görevler elinden
  /// alınmaz.
  Future<void> init();

  /// Yeni bir görev kuyruğa ekler ve oluşturulan [UploadTask]'ı döner.
  ///
  /// [filePath] dosya yolu.
  /// [metadata] JSON serileştirilebilir anahtar-değer çiftleri.
  /// [fileSizeBytes] dosyanın bayt cinsinden boyutu (`stat()` ile doldurulur).
  /// [taskId] UUID idempotency anahtarı.
  ///
  /// Sequence numarası repository tarafından atomik olarak üretilir
  /// (transaction içinde MAX+1). Dışarıdan geçilmesi gerekmiyor.
  Future<UploadTask> enqueue({
    required String taskId,
    required String filePath,
    int? fileSizeBytes,
    Map<String, dynamic>? metadata,
    int priority = 0,
  });

  /// Sıradaki işlenebilir görevi döner.
  ///
  /// `status = pending|failed` VE (`nextRetryAt IS NULL` VEYA `nextRetryAt <= now`)
  /// koşuluna uyan, `priority DESC, sequenceNumber ASC` sıralı ilk görevi döner.
  /// Yoksa `null` döner.
  ///
  /// [onlyTaskIds] verilirse yalnızca bu kimlikler arasından seçilir
  /// (`forceUploadOnce` wifiOnly bypass için).
  Future<UploadTask?> getNextPending(
    DateTime now, {
    Set<String>? onlyTaskIds,
  });

  /// Tek bir görevi kimliğine göre döner; yoksa `null`.
  Future<UploadTask?> getTask(String taskId);

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
  /// Yalnızca kilidin mevcut [ownerId] sahibi için yazılmalıdır;
  /// sahiplik uyuşmuyorsa no-op.
  Future<void> updateHeartbeat(String ownerId, DateTime acquiredAt);

  /// Atomik koşullu UPDATE ile worker kilidini almayı dener.
  ///
  /// Kilit yoksa veya stale ise ([staleLockThreshold]'dan eski `acquiredAt`)
  /// kilidi [ownerId]'ye aktarır ve `true` döner.
  /// Başka bir worker kilidi tazeliyorsa `false` döner.
  ///
  /// Sembast'ta bu işlem `.transaction()` bloğu içinde yapılır —
  /// aynı Dart process içindeki concurrent Future'lar serialize edilir
  /// (bkz. §7 ve OQ-1 Alternatif A).
  Future<bool> tryAcquireLock(String ownerId, Duration staleLockThreshold);

  /// Worker kilidi tablosundaki değişiklikleri yayınlayan stream.
  /// Kilit devralma sırasındaki polling'i azaltmak için kullanılır.
  Stream<void> watchLockUpdates();

  /// Worker kilidini serbest bırakır.
  Future<void> releaseLock();

  /// `uploading` durumundaki tüm görevleri `pending`'e döndürür (recovery).
  Future<void> recoverStuckUploads();

  /// Kuyruğun anlık özetini yayınlayan reactive stream.
  ///
  /// `tasks` store'undaki **herhangi bir yazım** sonrası otomatik
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

  /// [watchProgress] stream'inin aktif dinleyicisi var mı?
  ///
  /// `true` ise adapter'a `onProgress` callback'i geçirilmelidir.
  bool hasProgressListener(String taskId);

  /// Tek bir görevi ve varsa sandbox kopyasını kalıcı olarak siler.
  ///
  /// Yalnızca `permanentlyFailed` veya `cancelled` durumundaki görevler
  /// silinebilir. Diğer durumlarda [StateError] fırlatılır.
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

  /// Kuyruktaki belirli durumdaki tüm görevleri temizler.
  ///
  /// Varsayılan olarak `permanentlyFailed`, `cancelled` ve `completed` durumlarını kapsar.
  /// `includePending: true` ise `pending` görevler de silinir.
  /// (Aktif `uploading` görevlere dokunulmaz — önce iptal edilmeleri gerekir).
  Future<void> purgeAll({bool includePending = false});

  /// Kaynakları serbest bırakır. UploadQueue.dispose() tarafından çağrılır.
  Future<void> dispose();
}
