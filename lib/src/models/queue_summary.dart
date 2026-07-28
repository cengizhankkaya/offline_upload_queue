/// Kuyruğun anlık özeti — `watchSummary()` stream'i bu nesneyi yayınlar.
///
/// Tüm `UploadStatus` sayaçlarını, duraklama bayraklarını ve tahmini disk
/// kullanımını içerir. `watchSummary()`, sembast'ın `onSnapshots()` stream'ine
/// dayandığı için `UploadTasks` store'undaki **herhangi bir yazım** sonrası
/// otomatik yeni bir `QueueSummary` yayınlar.
///
/// ## Örnek
///
/// ```dart
/// queue.watchSummary().listen((s) {
///   print('${s.pending} bekliyor, ${s.completed} tamamlandı');
///   print('Tahmini disk: ${s.estimatedDiskUsageBytes} byte');
/// });
/// ```
class QueueSummary {
  /// `UploadStatus.pending` durumundaki görev sayısı.
  final int pending;

  /// `UploadStatus.uploading` durumundaki görev sayısı.
  final int uploading;

  /// `UploadStatus.completed` durumundaki görev sayısı.
  final int completed;

  /// `UploadStatus.failed` (geçici hata, backoff bekliyor) görev sayısı.
  final int failed;

  /// `UploadStatus.permanentlyFailed` (kalıcı hata, otomatik retry yok) görev sayısı.
  final int permanentlyFailed;

  /// `UploadStatus.cancelled` (kullanıcı tarafından iptal edildi) görev sayısı.
  final int cancelled;

  /// Kullanıcının `pause()` çağrısının anlık durumu.
  ///
  /// `true` iken worker yeni görev almaz. `pause()` yalnızca in-memory'dir;
  /// uygulama yeniden başlatılırsa `false` ile başlar.
  final bool isPaused;

  /// Yalnızca `onAuthExpired` callback'i çalışırken `true`.
  ///
  /// Bu bayrak `true` iken worker `authExpired` görevi için callback'in
  /// sonucunu beklemektedir; diğer görevler normal şekilde işlenir.
  final bool pausedDueToAuth;

  /// `fileSizeBytes` kolonunun toplamı — dosya sistemine dokunmadan hesaplanır.
  ///
  /// `completed` görevlerin sandbox kopyaları silindiğinden bu hesaplamaya
  /// dahil değildir; `pending`, `uploading`, `failed`, `permanentlyFailed`
  /// ve `cancelled` durumlarındaki görevlerin boyutlarının toplamıdır.
  final int estimatedDiskUsageBytes;

  const QueueSummary({
    required this.pending,
    required this.uploading,
    required this.completed,
    required this.failed,
    required this.permanentlyFailed,
    required this.cancelled,
    required this.isPaused,
    required this.pausedDueToAuth,
    required this.estimatedDiskUsageBytes,
  });

  /// Tüm durumların toplamı.
  int get total =>
      pending + uploading + completed + failed + permanentlyFailed + cancelled;

  /// Aktif olarak işlenmekte olan veya bekleyen görev sayısı.
  int get activeCount => pending + uploading + failed;

  /// Kısmi kopyalama — yalnızca değiştirmek istenen alanlar verilir.
  QueueSummary copyWith({
    int? pending,
    int? uploading,
    int? completed,
    int? failed,
    int? permanentlyFailed,
    int? cancelled,
    bool? isPaused,
    bool? pausedDueToAuth,
    int? estimatedDiskUsageBytes,
  }) {
    return QueueSummary(
      pending: pending ?? this.pending,
      uploading: uploading ?? this.uploading,
      completed: completed ?? this.completed,
      failed: failed ?? this.failed,
      permanentlyFailed: permanentlyFailed ?? this.permanentlyFailed,
      cancelled: cancelled ?? this.cancelled,
      isPaused: isPaused ?? this.isPaused,
      pausedDueToAuth: pausedDueToAuth ?? this.pausedDueToAuth,
      estimatedDiskUsageBytes:
          estimatedDiskUsageBytes ?? this.estimatedDiskUsageBytes,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is QueueSummary &&
          runtimeType == other.runtimeType &&
          pending == other.pending &&
          uploading == other.uploading &&
          completed == other.completed &&
          failed == other.failed &&
          permanentlyFailed == other.permanentlyFailed &&
          cancelled == other.cancelled &&
          isPaused == other.isPaused &&
          pausedDueToAuth == other.pausedDueToAuth &&
          estimatedDiskUsageBytes == other.estimatedDiskUsageBytes;

  @override
  int get hashCode => Object.hash(
    pending,
    uploading,
    completed,
    failed,
    permanentlyFailed,
    cancelled,
    isPaused,
    pausedDueToAuth,
    estimatedDiskUsageBytes,
  );

  @override
  String toString() =>
      'QueueSummary(pending: $pending, uploading: $uploading, '
      'completed: $completed, failed: $failed, '
      'permanentlyFailed: $permanentlyFailed, cancelled: $cancelled, '
      'isPaused: $isPaused, disk: $estimatedDiskUsageBytes B)';
}
