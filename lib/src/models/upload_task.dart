import 'upload_status.dart';

/// Bir yükleme görevinin anlık görüntüsü — UI ve `watchTasks()` için dışa açılır.
///
/// Veritabanı implementasyonundan bağımsız, immutable bir
/// veri sınıfıdır. `copyWith` ile kısmi kopyalama desteklenir.
class UploadTask {
  /// Görevin UUID idempotency anahtarı. Backend'e bu değer gönderilir.
  final String taskId;

  /// Dosyanın yerel yolu (sandbox kopyası veya orijinal).
  final String filePath;

  /// Monoton artan mantıksal sıra numarası.
  ///
  /// Worker'a işleme sırasını belirler, UI'da "N. sıradaki fotoğraf" gibi
  /// bir sayı olarak gösterilmemeli. Sebebi: görev silindiğinde veya
  /// `retry()` ile tekrar eklenirken numara güncellenmez, boşluklar
  /// oluşabilir. UI sıra göstergesi için listedeki index'i (0, 1, 2 …)
  /// kullanın.
  final int sequenceNumber;

  /// Görev önceliği (daha yüksek sayı = daha önce işlenir).
  ///
  /// Varsayılan `0`. Aynı önceliğe sahip görevler FIFO (`sequenceNumber`)
  /// sırasına göre işlenir.
  final int priority;

  /// Görevin anlık durumu.
  final UploadStatus status;

  /// Son hatanın tipi; henüz hata yoksa `null`.
  final FailureType? failureType;

  /// Şimdiye kadar yapılan başarısız deneme sayısı (0-indexed).
  final int retryCount;

  /// Ek meta veri (JSON serileştirilebilir anahtar-değer çiftleri).
  final Map<String, dynamic>? metadata;

  /// SHA-256 checksum. `pending` durumunda `null`; `uploading`'e geçerken doldurulur.
  final String? checksum;

  /// Dosyanın bayt cinsinden boyutu (`enqueue()` sırasında `stat()` ile doldurulur).
  final int? fileSizeBytes;

  /// İnsan okunabilir hata mesajı (debug/UI amaçlı); hata yoksa `null`.
  final String? errorMessage;

  /// Görevin kuyruğa alındığı zaman.
  final DateTime createdAt;

  /// Backoff sonrası bir sonraki deneme zamanı; `null` ise görev hemen alınabilir.
  final DateTime? nextRetryAt;

  const UploadTask({
    required this.taskId,
    required this.filePath,
    required this.sequenceNumber,
    required this.status,
    required this.retryCount,
    required this.createdAt,
    this.priority = 0,
    this.failureType,
    this.metadata,
    this.checksum,
    this.fileSizeBytes,
    this.errorMessage,
    this.nextRetryAt,
  });

  /// Kısmi kopyalama — değiştirilmek istenmeyen alanlar orijinalden taşınır.
  UploadTask copyWith({
    String? taskId,
    String? filePath,
    int? sequenceNumber,
    UploadStatus? status,
    FailureType? failureType,
    int? retryCount,
    Map<String, dynamic>? metadata,
    String? checksum,
    int? fileSizeBytes,
    String? errorMessage,
    DateTime? createdAt,
    DateTime? nextRetryAt,
    int? priority,
  }) {
    return UploadTask(
      taskId: taskId ?? this.taskId,
      filePath: filePath ?? this.filePath,
      sequenceNumber: sequenceNumber ?? this.sequenceNumber,
      status: status ?? this.status,
      failureType: failureType ?? this.failureType,
      retryCount: retryCount ?? this.retryCount,
      metadata: metadata ?? this.metadata,
      checksum: checksum ?? this.checksum,
      fileSizeBytes: fileSizeBytes ?? this.fileSizeBytes,
      errorMessage: errorMessage ?? this.errorMessage,
      createdAt: createdAt ?? this.createdAt,
      nextRetryAt: nextRetryAt ?? this.nextRetryAt,
      priority: priority ?? this.priority,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is UploadTask &&
          runtimeType == other.runtimeType &&
          taskId == other.taskId &&
          status == other.status &&
          retryCount == other.retryCount &&
          nextRetryAt == other.nextRetryAt;

  @override
  int get hashCode => taskId.hashCode ^ status.hashCode ^ retryCount.hashCode;

  @override
  String toString() =>
      'UploadTask(taskId: $taskId, status: $status, retryCount: $retryCount)';
}
