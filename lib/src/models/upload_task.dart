import 'upload_status.dart';

const Object _copyWithUnset = Object();

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
  ///
  /// Nullable alanları (`failureType`, `nextRetryAt`, `errorMessage`,
  /// `checksum`, `metadata`) açıkça `null` yapmak için ilgili parametreyi
  /// `null` geçin.
  UploadTask copyWith({
    String? taskId,
    String? filePath,
    int? sequenceNumber,
    UploadStatus? status,
    Object? failureType = _copyWithUnset,
    int? retryCount,
    Object? metadata = _copyWithUnset,
    Object? checksum = _copyWithUnset,
    Object? fileSizeBytes = _copyWithUnset,
    Object? errorMessage = _copyWithUnset,
    DateTime? createdAt,
    Object? nextRetryAt = _copyWithUnset,
    int? priority,
  }) {
    return UploadTask(
      taskId: taskId ?? this.taskId,
      filePath: filePath ?? this.filePath,
      sequenceNumber: sequenceNumber ?? this.sequenceNumber,
      status: status ?? this.status,
      failureType: identical(failureType, _copyWithUnset)
          ? this.failureType
          : failureType as FailureType?,
      retryCount: retryCount ?? this.retryCount,
      metadata: identical(metadata, _copyWithUnset)
          ? this.metadata
          : metadata as Map<String, dynamic>?,
      checksum: identical(checksum, _copyWithUnset)
          ? this.checksum
          : checksum as String?,
      fileSizeBytes: identical(fileSizeBytes, _copyWithUnset)
          ? this.fileSizeBytes
          : fileSizeBytes as int?,
      errorMessage: identical(errorMessage, _copyWithUnset)
          ? this.errorMessage
          : errorMessage as String?,
      createdAt: createdAt ?? this.createdAt,
      nextRetryAt: identical(nextRetryAt, _copyWithUnset)
          ? this.nextRetryAt
          : nextRetryAt as DateTime?,
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
