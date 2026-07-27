import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../database/persistence_repository.dart';
import '../models/queue_summary.dart';
import '../models/upload_status.dart';
import '../models/upload_task.dart';
import '../network/connectivity_monitor.dart';
import '../network/upload_adapter.dart';
import 'retry_policy.dart';
import 'upload_queue_options.dart';

/// Worker orkestrasyonu ve kuyruk kontrolü.
///
/// `UploadQueue` (public facade) bu sınıfı sarmalar. Doğrudan kullanım
/// önerilmez; `UploadQueue` üzerinden erişin.
///
/// ## Worker Döngüsü
///
/// 1. `ConnectivityMonitor.statusStream`'i dinle
/// 2. `wifiOnly: true` iken yalnızca WiFi bağlantısında çalış
/// 3. `pause()` bayrağı kontrol et
/// 4. `getNextPending(now)` — yoksa idle bekle
/// 5. `markUploading` → checksum hesapla → `uploadFile` çağır
/// 6. Sonucu `RetryPolicy` ile işle
/// 7. Heartbeat timer'ı güncelle
class QueueController {
  final PersistenceRepository _repo;
  final UploadAdapter _adapter;
  final RetryPolicy _retryPolicy;
  final ConnectivityMonitor _connectivityMonitor;
  final bool _wifiOnly;
  final bool _verifyChecksum;
  final bool _copyToSandbox;
  final String _boxName;
  final Future<void> Function()? _onAuthExpired;
  final Duration _authTimeout;
  final UploadQueueAdvancedOptions _advanced;

  // ── Singleton guard: aynı isolate içinde aynı boxName iki kez init() edilemez
  // (farklı isolate'ler arası çakışma DB kilit mekanizmasıyla çözülür — bkz. §7)
  static final _activeBoxNames = <String>{};

  // ── Worker state ──────────────────────────────────────────────────────────
  bool _paused = false;
  bool _pausedDueToAuth = false;
  bool _disposed = false;
  bool _lockAcquired = false;
  final _activeTokens = <String, UploadCancelToken>{};
  DateTime? _backgroundDeadline;

  // forceUploadOnce snapshot: bu taskId'ler wifiOnly bypass ile işlenebilir
  final _forceUploadSnapshot = <String>{};

  // ── Connectivity ──────────────────────────────────────────────────────────
  ConnectivityStatus _lastStatus = ConnectivityStatus.none;
  StreamSubscription<ConnectivityStatus>? _connectivitySub;

  // ── Heartbeat ─────────────────────────────────────────────────────────────
  Timer? _heartbeatTimer;
  final String _workerId = const Uuid().v4();

  // ── Worker trigger ────────────────────────────────────────────────────────────
  final _triggerController = StreamController<void>.broadcast();

  // Progress stream controller referansları (hasListener kontrolü için)
  final _progressControllers = <String, StreamController<double>>{};

  QueueController({
    required PersistenceRepository repository,
    required UploadAdapter adapter,
    required RetryPolicy retryPolicy,
    required ConnectivityMonitor connectivityMonitor,
    required bool wifiOnly,
    required bool verifyChecksum,
    required bool copyToSandbox,
    required String boxName,
    Future<void> Function()? onAuthExpired,
    Duration authTimeout = const Duration(seconds: 30),
    UploadQueueAdvancedOptions advanced = const UploadQueueAdvancedOptions(),
  })  : _repo = repository,
        _adapter = adapter,
        _retryPolicy = retryPolicy,
        _connectivityMonitor = connectivityMonitor,
        _wifiOnly = wifiOnly,
        _verifyChecksum = verifyChecksum,
        _copyToSandbox = copyToSandbox,
        _boxName = boxName,
        _onAuthExpired = onAuthExpired,
        _authTimeout = authTimeout,
        _advanced = advanced;

  // ── Init ──────────────────────────────────────────────────────────────────

  /// Başlatır: argüman doğrulaması, crash recovery, kilit alma, bağlantı izleme, worker döngüsü.
  Future<void> init() async {
    _assertDisposed();

    // ── Singleton guard: aynı isolate içinde aynı boxName'i iki kez init() edilemez
    if (_activeBoxNames.contains(_boxName)) {
      throw StateError(
        'UploadQueue with boxName "$_boxName" is already initialized in this '
        'isolate. Reuse the existing instance instead of calling init() twice. '
        'Call dispose() first if you want to reinitialize.',
      );
    }

    // Argüman doğrulaması (bkz. plan Bölüm 8)
    if (_retryPolicy.maxAttempts < 1) {
      throw ArgumentError.value(
        _retryPolicy.maxAttempts,
        'maxAttempts',
        'maxAttempts en az 1 olmalı — en az bir deneme yapılmadan '
            'bir görev asla completed/permanentlyFailed olamaz',
      );
    }
    final staleMs = _advanced.staleLockThreshold.inMilliseconds;
    final heartbeatMs = _advanced.heartbeatInterval.inMilliseconds;
    if (staleMs < heartbeatMs * 3) {
      throw ArgumentError(
        'staleLockThreshold (${_advanced.staleLockThreshold}) en az '
        'heartbeatInterval * 3 (${_advanced.heartbeatInterval * 3}) olmalı',
      );
    }
    // Aşırı büyük staleLockThreshold uyarısı (bkz. §7 — sert hata değil, log)
    if (_advanced.staleLockThreshold > const Duration(minutes: 30)) {
      _log(
        'staleLockThreshold ${_advanced.staleLockThreshold} gibi yüksek bir '
        'değere ayarlandı; çökmüş bir worker kilidi bu süre boyunca devralınamaz.',
        level: LogLevel.warning,
      );
    }

    // Crash recovery: uploading → pending + kilit temizliği (bkz. §4 Kritik kural #3)
    await _repo.init();

    // ── Kilit alma (bkz. §7 — atomik koşullu UPDATE)
    // staleLockThreshold kadar yeni heartbeat'e sahip bir lock varsa geri çekil
    // ve heartbeat aralığıyla periyodik olarak tekrar dene.
    await _acquireLockWithRetry();

    // Başarıyla init edildi — boxName'i sete ekle
    _activeBoxNames.add(_boxName);

    // İlk bağlantı durumunu al
    _lastStatus = await _connectivityMonitor.checkStatus();

    // Bağlantı değişikliklerini izle
    _connectivitySub = _connectivityMonitor.statusStream.listen((status) {
      _lastStatus = status;
      _triggerWorker();
    });

    // Heartbeat timer'ı başlat
    _startHeartbeat();

    // Worker döngüsünü başlat
    unawaited(_runWorkerLoop());

    // İlk çalışmayı tetikle
    _triggerWorker();
  }

  /// Kilidi alana kadar heartbeat aralığında bekleyerek dener.
  ///
  /// Aktif bir worker varsa, o worker ya kapanır ya da staleLockThreshold
  /// dolunca stale sayılır ve bu worker kilidi devralır.
  Future<void> _acquireLockWithRetry() async {
    // İlk deneme
    _lockAcquired = await _repo.tryAcquireLock(
      _workerId,
      _advanced.staleLockThreshold,
    );

    if (_lockAcquired) return;

    _log(
      'Worker kilidi başka bir instance tarafından tutuluyor. '
      'staleLockThreshold (${_advanced.staleLockThreshold}) dolana kadar bekleniyor...',
      level: LogLevel.warning,
    );

    // Kilit stale olana kadar heartbeat aralığında tekrar dene
    while (!_lockAcquired && !_disposed) {
      await Future<void>.delayed(_advanced.heartbeatInterval);
      if (_disposed) return;
      _lockAcquired = await _repo.tryAcquireLock(
        _workerId,
        _advanced.staleLockThreshold,
      );
    }

    if (_lockAcquired) {
      _log('Worker kilidi devralındı.', level: LogLevel.warning);
    }
  }

  // ── Public API ────────────────────────────────────────────────────────────

  /// Yeni bir dosyayı kuyruğa ekler ve `taskId` döner.
  Future<String> enqueue({
    required String filePath,
    Map<String, dynamic>? metadata,
  }) async {
    _assertDisposed();

    // 1. metadata doğrulaması — gerçek jsonEncode (§3 sözleşmesi)
    if (metadata != null) {
      try {
        jsonEncode(metadata);
      } catch (e) {
        throw ArgumentError(
          'metadata yalnızca JSON serileştirilebilir tipler içerebilir '
          '(String, num, bool, null, List, Map): $e',
        );
      }
    }

    // 2. filePath varlık kontrolü — enqueue anında (§3 sözleşmesi)
    if (!File(filePath).existsSync()) {
      throw ArgumentError('filePath mevcut değil: $filePath');
    }

    // 3. Sandbox kopyalama (copyToSandbox: true ise)
    final taskId = const Uuid().v4();
    final actualPath =
        _copyToSandbox ? await _copyToSandboxDir(filePath, taskId) : filePath;

    // 4. fileSizeBytes — stat() (sandbox kopyası üzerinde)
    final fileSizeBytes = await _statFile(actualPath);

    // 5. Sekans numarası — DB'den güvenli monoton değer
    final sequenceNumber = await _repo.getNextSequenceNumber();

    // 6. DB'ye INSERT (yalnızca 1-5 başarılıysa)
    await _repo.enqueue(
      taskId: taskId,
      filePath: actualPath,
      sequenceNumber: sequenceNumber,
      fileSizeBytes: fileSizeBytes,
      metadata: metadata,
    );

    _triggerWorker();
    return taskId;
  }

  /// Görevi `pending`'e döndürür (manuel retry).
  Future<void> retry(String taskId) async {
    _assertDisposed();
    await _repo.markPending(taskId);
    _triggerWorker();
  }

  /// Görevi iptal eder. Aktif upload varsa keser.
  Future<void> cancel(String taskId) async {
    _assertDisposed();
    _activeTokens[taskId]?.cancel();
    await _repo.markCancelled(taskId);
  }

  /// Worker'ı geçici durdurur (in-memory, kalıcı değil).
  void pause() {
    _paused = true;
  }

  /// Worker'ı yeniden başlatır.
  void resume() {
    _paused = false;
    _triggerWorker();
  }

  /// `wifiOnly: true` iken çağrı anındaki tüm `pending` görevleri mevcut
  /// bağlantı üzerinden işlemeye çalışır (tek seferlik snapshot bypass).
  Future<void> forceUploadOnce() async {
    _assertDisposed();
    if (_paused) return; // pause() > forceUploadOnce()

    final pending = await _repo.watchTasks(
      statuses: {UploadStatus.pending},
      limit: 1000,
      offset: 0,
    ).first;

    _forceUploadSnapshot.addAll(pending.map((t) => t.taskId));
    _triggerWorker();
  }

  /// Kuyruğun anlık özetini yayınlayan stream.
  ///
  /// `isPaused` ve `pausedDueToAuth` değerleri her yayında güncel
  /// in-memory durumu yansıtır.
  Stream<QueueSummary> watchSummary() {
    // flatMap: her repo değişikliğinde güncel _paused/_pausedDueToAuth ile
    // taze bir QueueSummary üretilir
    return _repo
        .watchSummary(
          isPaused: _paused,
          pausedDueToAuth: _pausedDueToAuth,
        )
        .map((s) => s.copyWith(
              isPaused: _paused,
              pausedDueToAuth: _pausedDueToAuth,
            ));
  }

  /// Filtrelenmiş görev listesini yayınlayan stream.
  Stream<List<UploadTask>> watchTasks({
    Set<UploadStatus>? statuses,
    int limit = 50,
    int offset = 0,
  }) {
    return _repo.watchTasks(statuses: statuses, limit: limit, offset: offset);
  }

  /// Tek bir görevin upload ilerleme oranını (0.0–1.0) yayınlayan stream.
  Stream<double> watchProgress(String taskId) {
    return _repo.watchProgress(taskId);
  }

  /// Tek bir görevi ve sandbox kopyasını kalıcı olarak siler.
  Future<void> purge(String taskId) => _repo.purge(taskId);

  /// Tüm `permanentlyFailed` görevleri siler.
  Future<void> purgeAllFailed() => _repo.purgeAllFailed();

  /// Tüm `cancelled` görevleri siler.
  Future<void> purgeAllCancelled() => _repo.purgeAllCancelled();

  /// Tüm `completed` DB kayıtlarını siler.
  Future<void> purgeAllCompleted() => _repo.purgeAllCompleted();

  // ── Worker Loop ───────────────────────────────────────────────────────────

  Future<void> _runWorkerLoop() async {
    await for (final _ in _triggerController.stream) {
      if (_disposed) break;
      await _processNext();
    }
  }

  Future<void> _processNext() async {
    if (_disposed || _paused) return;
    if (!_canProcess()) return;

    final task = await _repo.getNextPending(DateTime.now());
    if (task == null) return;

    // wifiOnly: force snapshot dışındaki görevler wifi gerektiriyor
    if (_wifiOnly &&
        _lastStatus != ConnectivityStatus.wifi &&
        !_forceUploadSnapshot.contains(task.taskId)) {
      return;
    }
    _forceUploadSnapshot.remove(task.taskId);

    await _uploadTask(task);

    // Sırada daha görev olabilir — hemen tekrar kontrol et
    _triggerWorker();
  }

  bool _canProcess() {
    if (_lastStatus == ConnectivityStatus.none) return false;
    return true;
  }

  void _triggerWorker() {
    if (!_triggerController.isClosed) _triggerController.add(null);
  }

  // ── Upload ────────────────────────────────────────────────────────────────

  Future<void> _uploadTask(UploadTask task) async {
    await _repo.markUploading(task.taskId);

    // Checksum hesapla
    String checksum;
    try {
      checksum = await _computeChecksum(task.filePath);
    } catch (e) {
      // Dosya okunamıyor — kısa retry mekanizması (3 deneme, bkz. Bölüm 3)
      if (task.retryCount < 2) {
        _log('Checksum hatası (deneme ${task.retryCount + 1}/3): $e',
            level: LogLevel.warning);
        await _repo.markFailed(
          task.taskId,
          failureType: FailureType.network,
          errorMessage: 'Checksum hesaplanamadı: $e',
          nextRetryAt: _retryPolicy.nextRetryAt(
            retryCount: task.retryCount,
            failureType: FailureType.network,
          ),
        );
      } else {
        _log(
            'Dosya okunamıyor, corruptFile olarak işaretleniyor: ${task.taskId}',
            level: LogLevel.warning);
        await _repo.markPermanentlyFailed(
          task.taskId,
          failureType: FailureType.corruptFile,
          errorMessage: 'Dosya 3 denemede okunamadı: $e',
        );
      }
      return;
    }

    await _repo.updateChecksum(task.taskId, checksum);

    // Upload
    final cancelToken = UploadCancelToken();
    _activeTokens[task.taskId] = cancelToken;

    // Progress aktarımı
    final progressController = _progressControllers[task.taskId];
    final hasProgressListener =
        progressController != null && progressController.hasListener;

    UploadResult result;
    try {
      result = await _adapter.uploadFile(
        taskId: task.taskId,
        filePath: task.filePath,
        metadata: task.metadata ?? {},
        checksum: checksum,
        onProgress: hasProgressListener
            ? (sent, total) {
                if (total > 0) {
                  _repo.updateProgress(task.taskId, sent / total);
                }
              }
            : null,
        cancelToken: cancelToken,
      );
    } catch (e) {
      // İptal — sessizce pending'e bırak (cancel() zaten markCancelled yaptı)
      if (cancelToken.isCancelled) {
        _activeTokens.remove(task.taskId);
        return;
      }
      result = UploadResult.failure(FailureType.network);
    }

    _activeTokens.remove(task.taskId);

    if (result.success) {
      await _handleSuccess(task, checksum, result.remoteChecksum);
    } else {
      await _handleFailure(task, result);
    }
  }

  Future<void> _handleSuccess(
    UploadTask task,
    String localChecksum,
    String? remoteChecksum,
  ) async {
    // Checksum doğrulama
    if (_verifyChecksum &&
        remoteChecksum != null &&
        remoteChecksum != localChecksum) {
      _log(
          'Checksum uyuşmazlığı: ${task.taskId} — yerel: $localChecksum, uzak: $remoteChecksum',
          level: LogLevel.warning);
      await _handleFailure(
        task,
        UploadResult.failure(FailureType.network),
      );
      return;
    }

    await _repo.markCompleted(task.taskId, checksum: localChecksum);

    // completed → sandbox dosyasını sil
    if (_copyToSandbox) {
      try {
        final file = File(task.filePath);
        if (await file.exists()) await file.delete();
      } catch (e) {
        _log('Sandbox dosyası silinemedi: ${task.filePath}: $e',
            level: LogLevel.warning);
      }
    }
  }

  Future<void> _handleFailure(UploadTask task, UploadResult result) async {
    final failureType = result.failureType ?? FailureType.unknown;

    // authExpired → onAuthExpired callback
    final authCallback = _onAuthExpired;
    if (failureType == FailureType.authExpired && authCallback != null) {
      _pausedDueToAuth = true;
      try {
        var effectiveTimeout = _authTimeout;
        if (_backgroundDeadline != null) {
          final remaining = _backgroundDeadline!.difference(DateTime.now());
          if (remaining < effectiveTimeout) {
            effectiveTimeout = remaining.isNegative ? Duration.zero : remaining;
          }
        }
        await authCallback().timeout(effectiveTimeout);
        _pausedDueToAuth = false;
        // Auth yenilendi — görevi pending'e al ve tekrar dene
        await _repo.markPending(task.taskId);
        _triggerWorker();
        return;
      } catch (e) {
        _pausedDueToAuth = false;
        _log('Auth callback başarısız veya timeout: $e', level: LogLevel.warning);
        // Normal failed/backoff akışına düş (aşağıda devam eder)
      }
    }

    // Kalıcı hata kontrolü
    if (_retryPolicy.isPermanent(failureType)) {
      await _repo.markPermanentlyFailed(
        task.taskId,
        failureType: failureType,
        errorMessage: 'Kalıcı hata: $failureType',
      );
      return;
    }

    // maxAttempts aşımı
    if (_retryPolicy.shouldPermanentlyFail(task.retryCount)) {
      await _repo.markPermanentlyFailed(
        task.taskId,
        failureType: failureType,
        errorMessage:
            'maxAttempts (${_retryPolicy.maxAttempts}) aşıldı — son hata: $failureType',
      );
      return;
    }

    // Geçici hata → backoff
    final nextRetry = _retryPolicy.nextRetryAt(
      retryCount: task.retryCount,
      failureType: failureType,
      retryAfter: result.retryAfter,
    );
    await _repo.markFailed(
      task.taskId,
      failureType: failureType,
      nextRetryAt: nextRetry,
    );

    // Backoff bittikten sonra tekrar tetikle
    if (nextRetry != null) {
      final delay = nextRetry.difference(DateTime.now());
      if (delay > Duration.zero) {
        Timer(delay, _triggerWorker);
      }
    }
  }

  // ── Heartbeat ─────────────────────────────────────────────────────────────

  void _startHeartbeat() {
    _heartbeatTimer = Timer.periodic(_advanced.heartbeatInterval, (_) async {
      if (_disposed) return;

      // Yalnızca kilidin sahibi olan worker heartbeat gönderir (bkz. §7)
      // _lockAcquired false ise _acquireLockWithRetry hâlâ bekliyor demektir;
      // o döngü kendi sıklığıyla denemeye devam eder, burada tekrar denemeyiz.
      if (!_lockAcquired) return;

      await _repo.updateHeartbeat(_workerId, DateTime.now());

      // Disk kullanım uyarısı
      final warningBytes = _advanced.diskUsageWarningBytes;
      if (warningBytes != null && _advanced.onDiskUsageWarning != null) {
        final summary = await _repo.watchSummary().first;
        if (summary.estimatedDiskUsageBytes > warningBytes) {
          _advanced.onDiskUsageWarning!(
            summary.estimatedDiskUsageBytes,
            warningBytes,
          );
        }
      }
    });
  }


  // ── Dispose ───────────────────────────────────────────────────────────────

  /// Kaynakları serbest bırakır.
  ///
  /// Aktif upload varsa token'ı iptal eder, görevi `pending`'e döndürür
  /// (`cancelled`'a değil — bkz. §8 "dispose() sırasında aktif worker").
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;

    // Heartbeat durdur
    _heartbeatTimer?.cancel();

    // Bağlantı izlemeyi durdur
    await _connectivitySub?.cancel();

    // Aktif upload'ları iptal et ve pending'e döndür (cancelled değil!)
    // bkz. §8 — dispose() görevi cancelled'a almaz, sonraki init()'te
    // backoff beklemeden tekrar alınabilir olsun diye pending'e döner.
    for (final entry in _activeTokens.entries) {
      entry.value.cancel();
      try {
        await _repo.markPending(entry.key);
      } catch (_) {}
    }
    _activeTokens.clear();

    // Worker trigger stream'ini kapat
    await _triggerController.close();

    // Kilidin sahibi bu worker ise serbest bırak
    // (stale bekleme sırasında _lockAcquired false olabilir)
    if (_lockAcquired) {
      await _repo.releaseLock();
    }

    // boxName'i singleton set'ten çıkar — aynı boxName tekrar init() edilebilsin
    _activeBoxNames.remove(_boxName);

    // Repo'yu kapat
    await _repo.dispose();
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  Future<String> _computeChecksum(String filePath) async {
    final file = File(filePath);
    final bytes = await file.readAsBytes();
    return sha256.convert(bytes).toString();
  }

  Future<int?> _statFile(String filePath) async {
    try {
      final stat = await File(filePath).stat();
      return stat.size;
    } catch (_) {
      return null;
    }
  }

  Future<String> _copyToSandboxDir(String sourcePath, String taskId) async {
    // Basit byte-kopyalama (v1.0 — hardlink v2 adayı)
    final source = File(sourcePath);
    final ext = sourcePath.contains('.') ? sourcePath.split('.').last : '';
    final destDir = await _getSandboxDir();
    final destPath = '${destDir.path}/$taskId${ext.isNotEmpty ? '.$ext' : ''}';
    await source.copy(destPath);
    return destPath;
  }

  Future<Directory> _getSandboxDir() async {
    final base = await getApplicationSupportDirectory();
    final dir = Directory('${base.path}/$_boxName/sandbox');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  void _log(String message, {required LogLevel level}) {
    _advanced.onLog?.call(message, level: level);
  }

  void _assertDisposed() {
    if (_disposed) {
      throw StateError('QueueController.dispose() çağrıldıktan sonra kullanılamaz');
    }
  }

  void setBackgroundDeadline(DateTime? deadline) {
    _backgroundDeadline = deadline;
  }

  /// **Yalnızca test ortamında kullanın.**
  ///
  /// `_activeBoxNames` setinden [boxName]'i zorla çıkarır. Bu, `dispose()`
  /// çağrısını unuttuğunuz test senaryolarında aynı `boxName` ile yeni bir
  /// `init()` yapabilmenizi sağlar (bkz. §10, madde 8 — hot-restart senaryosu).
  ///
  /// Production kodunda **asla çağrılmamalı** — yalnızca `test/helpers/` altında.
  @visibleForTesting
  static void resetForTesting(String boxName) {
    _activeBoxNames.remove(boxName);
  }
}
