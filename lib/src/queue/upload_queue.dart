import '../database/database.dart';
import '../database/drift_persistence_repository.dart';
import '../models/queue_summary.dart';
import '../models/upload_status.dart';
import '../models/upload_task.dart';
import '../network/connectivity_monitor.dart';
import '../network/upload_adapter.dart';
import 'queue_controller.dart';
import 'retry_policy.dart';
import 'upload_queue_options.dart';

/// Offline image upload kuyruğunun public facade'ı.
///
/// ## Temel Kullanım
///
/// ```dart
/// final queue = UploadQueue(
///   adapter: RestUploadAdapter(baseUrl: 'https://api.example.com/uploads'),
/// );
/// await queue.init();
///
/// final taskId = await queue.enqueue(
///   filePath: photo.path,
///   metadata: {'siteId': '42'},
/// );
///
/// queue.watchSummary().listen((s) {
///   print('${s.pending} bekliyor, ${s.completed} tamamlandı');
/// });
/// ```
///
/// ## Bağımsız Birden Fazla Kuyruk
///
/// ```dart
/// final photoQueue = UploadQueue(adapter: ..., boxName: 'photos');
/// final docQueue   = UploadQueue(adapter: ..., boxName: 'documents');
/// ```
///
/// Her `boxName` bağımsız bir SQLite veritabanı kullanır.
///
/// ## wifiOnly
///
/// `wifiOnly: true` iken worker yalnızca Wi-Fi bağlantısında görev alır.
/// Cellular üzerinden manuel yükleme için `forceUploadOnce()` kullanın.
///
/// ```dart
/// final queue = UploadQueue(adapter: ..., wifiOnly: true);
/// await queue.init();
/// await queue.forceUploadOnce(); // cellular'da bile çalışır (tek seferlik)
/// ```
class UploadQueue {
  late final QueueController _controller;
  bool _initialized = false;

  /// Upload işlemi yapacak adapter (ör. [RestUploadAdapter]).
  final UploadAdapter adapter;

  /// Toplam maksimum deneme sayısı (ilk deneme dahil). Varsayılan: 6.
  ///
  /// `maxAttempts: 1` → retry yok; ilk denemede başarısız olursa doğrudan `permanentlyFailed`.
  /// `maxAttempts < 1` → `init()` `ArgumentError` fırlatır.
  final int maxAttempts;

  /// Denemeler arası bekleme stratejisi.
  ///
  /// `null` bırakılırsa `exponential(base: 2s, max: 10min)` kullanılır.
  final BackoffStrategy? backoff;

  /// `true` ise backend'in döndürdüğü `remoteChecksum` yerel checksum ile
  /// karşılaştırılır. Backend checksum döndürmezse (`null`) doğrulama atlanır.
  /// Varsayılan: `true`.
  final bool verifyChecksum;

  /// Birden fazla bağımsız kuyruğu ayırt eden ad. Varsayılan: `'default'`.
  ///
  /// Her `boxName` bağımsız bir SQLite veritabanı dosyası kullanır.
  final String boxName;

  /// `true` ise dosya kuyruğa alındığında paketin kendi sandbox dizinine
  /// kopyalanır; orijinal dosya silinse bile upload güvenli devam eder.
  /// Varsayılan: `true`.
  final bool copyToSandbox;

  /// `true` ise worker yalnızca Wi-Fi bağlantısında görev alır.
  /// Cellular'da yüklemek için `forceUploadOnce()` kullanın.
  /// Varsayılan: `false`.
  final bool wifiOnly;

  /// Bağlantı izleme implementasyonu.
  ///
  /// `null` bırakılırsa `DefaultConnectivityMonitor()` kullanılır.
  /// Testlerde veya özel reachability mantığı için mock enjekte edin.
  final ConnectivityMonitor? connectivityMonitor;

  /// `authExpired` hatasında token yenileme callback'i.
  ///
  /// `null` ise `authExpired` hataları normal `failed`/backoff akışına girer.
  /// Callback reject ederse veya [authTimeout] aşılırsa aynı akışa düşer.
  final Future<void> Function()? onAuthExpired;

  /// `onAuthExpired` callback'i için maksimum bekleme süresi. Varsayılan: 30 saniye.
  final Duration authTimeout;

  /// Nadiren değiştirilen ileri düzey ayarlar.
  ///
  /// Çoğu kullanıcının bu parametreye dokunmasına gerek yoktur.
  final UploadQueueAdvancedOptions advanced;

  UploadQueue({
    required this.adapter,
    this.maxAttempts = 6,
    this.backoff,
    this.verifyChecksum = true,
    this.boxName = 'default',
    this.copyToSandbox = true,
    this.wifiOnly = false,
    this.connectivityMonitor,
    this.onAuthExpired,
    this.authTimeout = const Duration(seconds: 30),
    this.advanced = const UploadQueueAdvancedOptions(),
  });

  // ── Init ──────────────────────────────────────────────────────────────────

  /// Kuyruğu başlatır.
  ///
  /// `init()` çağrılmadan hiçbir metot kullanılamaz.
  ///
  /// ## Yapılanlar
  ///
  /// - Argüman doğrulaması (`maxAttempts`, `staleLockThreshold >= heartbeatInterval * 3`)
  /// - Crash recovery: `uploading → pending` geçişi
  /// - Bağlantı izlemeyi başlatır
  /// - Worker döngüsünü başlatır
  Future<void> init() async {
    if (_initialized) return;

    final effectiveBackoff = backoff ??
        BackoffStrategy.exponential(
          base: const Duration(seconds: 2),
          max: const Duration(minutes: 10),
        );

    final effectiveMonitor = connectivityMonitor ?? DefaultConnectivityMonitor();
    final db = QueueDatabase();
    final repo = DriftPersistenceRepository(db);

    _controller = QueueController(
      repository: repo,
      adapter: adapter,
      retryPolicy: RetryPolicy(
        maxAttempts: maxAttempts,
        backoff: effectiveBackoff,
      ),
      connectivityMonitor: effectiveMonitor,
      wifiOnly: wifiOnly,
      verifyChecksum: verifyChecksum,
      copyToSandbox: copyToSandbox,
      boxName: boxName,
      onAuthExpired: onAuthExpired,
      authTimeout: authTimeout,
      advanced: advanced,
    );

    await _controller.init();
    _initialized = true;
  }

  // ── Enqueue ───────────────────────────────────────────────────────────────

  /// Dosyayı kuyruğa ekler ve `taskId` (UUID) döner.
  ///
  /// [metadata] yalnızca JSON serileştirilebilir tipler içerebilir
  /// (String, num, bool, null, List, Map). Geçersiz tip varsa senkron
  /// `ArgumentError` fırlatılır.
  Future<String> enqueue({
    required String filePath,
    Map<String, dynamic>? metadata,
  }) {
    _assertInitialized();
    return _controller.enqueue(filePath: filePath, metadata: metadata);
  }

  // ── Control ───────────────────────────────────────────────────────────────

  /// `permanentlyFailed` veya `cancelled` görevi tekrar `pending`'e alır.
  ///
  /// `retryCount` ve `nextRetryAt` sıfırlanır — görev ilk kez deneniyormuş
  /// gibi kuyruğun en önüne eklenir.
  ///
  /// Throws [StateError] if `init()` has not been called.
  Future<void> retry(String taskId) {
    _assertInitialized();
    return _controller.retry(taskId);
  }

  /// Görevi iptal eder. Aktif upload varsa HTTP isteğini keser.
  ///
  /// Görev `cancelled` durumuna geçirilir. İlişkili sandbox kopyası
  /// silinmez — `purge()` veya `purgeAllCancelled()` ile temizlenmelidir.
  ///
  /// Throws [StateError] if `init()` has not been called.
  Future<void> cancel(String taskId) {
    _assertInitialized();
    return _controller.cancel(taskId);
  }

  /// Worker'ı geçici durdurur (in-memory; uygulama yeniden başlatılırsa sıfırlanır).
  ///
  /// Devam eden upload'ı kesmez — yalnızca yeni görev almayı engeller.
  /// `watchSummary()` üzerinden `isPaused: true` olarak yansır.
  void pause() {
    _assertInitialized();
    _controller.pause();
  }

  /// Duraklatılmış worker'ı yeniden başlatır.
  ///
  /// `pause()` aktif değilse no-op. `watchSummary()` üzerinden
  /// `isPaused: false` olarak yansır.
  Future<void> resume() async {
    _assertInitialized();
    _controller.resume();
  }

  /// `wifiOnly: true` iken çağrı anındaki tüm `pending` görevleri mevcut
  /// bağlantı üzerinden işlemeye çalışır (tek seferlik bypass).
  ///
  /// `pause()` aktifse no-op döner (`pause() > forceUploadOnce()`).
  Future<void> forceUploadOnce() {
    _assertInitialized();
    return _controller.forceUploadOnce();
  }

  // ── Observe ───────────────────────────────────────────────────────────────

  /// Kuyruğun anlık özetini yayınlayan reaktif stream.
  ///
  /// `UploadTasks` tablosundaki herhangi bir değişiklik sonrası otomatik
  /// yeni bir [QueueSummary] yayınlar.
  Stream<QueueSummary> watchSummary() {
    _assertInitialized();
    return _controller.watchSummary();
  }

  /// Filtrelenmiş görev listesini yayınlayan reaktif stream.
  ///
  /// `UploadTasks` tablosundaki herhangi bir değişiklik sonrası otomatik
  /// yeni bir liste yayınlar.
  ///
  /// ## Önemli
  ///
  /// `sequenceNumber` kullanıcıya gösterilecek bir sıra sayacı değildir;
  /// yalnızca worker'ın işleme sırasını belirler. UI'da "N. sıradaki fotoğraf"
  /// göstermek için liste index'ini (0, 1, 2 …) kullanın.
  ///
  /// Filtre veya sayfa değiştiğinde eski aboneliği iptal edip yenisini açın.
  ///
  /// ```dart
  /// final sub = queue.watchTasks(
  ///   statuses: {UploadStatus.pending, UploadStatus.failed},
  ///   limit: 20,
  /// ).listen((tasks) {
  ///   for (final (i, t) in tasks.indexed) {
  ///     print('${i + 1}. sıra: ${t.taskId}');
  ///   }
  /// });
  /// // ...
  /// await sub.cancel(); // Filtre değiştiğinde
  /// ```
  Stream<List<UploadTask>> watchTasks({
    Set<UploadStatus>? statuses,
    int limit = 50,
    int offset = 0,
  }) {
    _assertInitialized();
    return _controller.watchTasks(
        statuses: statuses, limit: limit, offset: offset);
  }

  /// Tek bir görevin upload ilerleme oranını (0.0–1.0) yayınlayan stream.
  ///
  /// Yalnızca `uploading` sırasında anlamlı değerler yayınlar; görev
  /// `completed` veya `failed`'e düştüğünde stream kapanmaz, yeni değer
  /// yayınlamaz.
  ///
  /// **Performans:** Listener yokken `onProgress` callback'i adapter'a hiç
  /// geçirilmez — gereksiz chunk başına closure maliyeti yoktur.
  Stream<double> watchProgress(String taskId) {
    _assertInitialized();
    return _controller.watchProgress(taskId);
  }

  // ── Purge ─────────────────────────────────────────────────────────────────

  /// Tek bir görevi ve varsa sandbox kopyasını kalıcı olarak siler.
  ///
  /// Yalnızca `permanentlyFailed` veya `cancelled` durumundaki görevler
  /// silinebilir. Aktif (`pending`, `uploading`, `failed`) görevlere uygulamak
  /// için önce `cancel()` çağırın.
  Future<void> purge(String taskId) {
    _assertInitialized();
    return _controller.purge(taskId);
  }

  /// Tüm `permanentlyFailed` görevleri ve sandbox kopyalarını siler.
  ///
  /// Tipik kullanım: kullanıcıya "N görev kalıcı hatayla başarısız oldu —
  /// temizlemek istiyor musunuz?" sorusu ardından.
  Future<void> purgeAllFailed() {
    _assertInitialized();
    return _controller.purgeAllFailed();
  }

  /// Tüm `cancelled` görevleri ve sandbox kopyalarını siler.
  Future<void> purgeAllCancelled() {
    _assertInitialized();
    return _controller.purgeAllCancelled();
  }

  /// Tüm `completed` görevlerin DB kayıtlarını siler.
  ///
  /// Sandbox kopyaları zaten `completed` anında silinmiştir;
  /// bu çağrı yalnızca DB satırlarının birikmesini önler.
  Future<void> purgeAllCompleted() {
    _assertInitialized();
    return _controller.purgeAllCompleted();
  }

  // ── Dispose ───────────────────────────────────────────────────────────────

  /// Kaynakları serbest bırakır.
  ///
  /// Aktif upload varsa token iptal edilir ve görev `pending`'e döndürülür.
  /// Aynı `boxName` ile sonradan yeniden `init()` çağrılabilir.
  Future<void> dispose() async {
    if (!_initialized) return;
    await _controller.dispose();
    _initialized = false;
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  /// Arka plan görev süre sınırını bildirir.
  ///
  /// iOS `BGTaskScheduler` ve Android Workmanager gibi arka plan ortamlarında
  /// OS'un kalan bütçesi içinde `authTimeout`'un taşmasını önlemek için
  /// [BackgroundTaskRunner] tarafından otomatik olarak çağrılır.
  ///
  /// `deadline` `null` geçilirse sınır kaldırılır.
  /// Doğrudan çağırmanız gerekmez — [BackgroundTaskRunner.run] bunu yönetir.
  void setBackgroundDeadline(DateTime? deadline) {
    if (_initialized) {
      _controller.setBackgroundDeadline(deadline);
    }
  }

  void _assertInitialized() {
    if (!_initialized) {
      throw StateError(
        'UploadQueue.init() çağrılmadan kullanılamaz. '
        'await queue.init() ile başlatın.',
      );
    }
  }
}
