import '../models/upload_status.dart';

/// Bir yükleme işleminin sonucu.
class UploadResult {
  /// İşlem başarılı mı?
  final bool success;

  /// Hata tipi. [success] `true` ise `null`.
  final FailureType? failureType;

  /// 429 yanıtında backend'in verdiği bekleme süresi.
  final Duration? retryAfter;

  /// Sunucunun döndürdüğü checksum (opsiyonel).
  ///
  /// Worker, yerel checksum ile karşılaştırır:
  /// - Eşleşmiyorsa: `FailureType.network` (geçici, retry edilir)
  /// - Yerel dosya okunamazsa: `FailureType.corruptFile` (kalıcı)
  final String? remoteChecksum;

  const UploadResult.success({this.remoteChecksum})
    : success = true,
      failureType = null,
      retryAfter = null;

  const UploadResult.failure(this.failureType, {this.retryAfter})
    : success = false,
      remoteChecksum = null;
}

/// Paketin kendi adapter-agnostic iptal sinyali.
///
/// `QueueController`, her `uploadFile()` çağrısı için bir token oluşturur
/// ve `queue.cancel(taskId)` çağrıldığında bu token üzerinden `cancel()`
/// çağırır.
///
/// `RestUploadAdapter` (dio tabanlı), `uploadFile()` başında
/// `cancelToken?.registerOnCancel(dioCancelToken.cancel)` çağırarak
/// kendi iptal mekanizmasını bu token'a bağlar.
///
/// Adapter iptal desteği yoksa `isCancelled` periyodik kontrol
/// edilebilir; ya da callback yok sayılabilir — bu durumda `cancel()`
/// yalnızca DB durumunu `cancelled` yapar, HTTP isteği tamamlanana
/// kadar devam eder (bkz. §4 Kritik kural #5).
class UploadCancelToken {
  bool _cancelled = false;

  /// Token iptal edildi mi?
  bool get isCancelled => _cancelled;

  void Function()? _onCancelCallback;

  /// Adapter'ın iptal anında haberdar olabilmesi için callback kaydeder.
  ///
  /// Bir token başına tek callback tutulur — `uploadFile()` her
  /// çağrıldığında yeniden kaydedilir, önceki üzerine yazılır.
  void registerOnCancel(void Function() callback) {
    _onCancelCallback = callback;
    if (_cancelled) {
      callback();
    }
  }

  /// Token'ı iptal eder ve kayıtlı callback'i çağırır.
  void cancel() {
    _cancelled = true;
    _onCancelCallback?.call();
  }
}

/// Yükleme motorunun ağ katmanına karşı soyutlaması.
///
/// Özel bir backend kullanmak için bu arayüzü implement edin.
///
/// ## Önemli Notlar
/// - `cancelToken` nullable — iptal desteklemeyen adapter'lar parametreyi
///   yok sayabilir; bu durumda `cancel()` HTTP isteğini kesmez.
/// - `onProgress` nullable — dinleyici yoksa `null` geçirilmeli (bkz. §11.4
///   performans notu: `StreamController` listener kontrolü `QueueController`
///   tarafında yapılır).
/// - v2'de chunked/resumable upload için `uploadChunk()` bu arayüze
///   **ek** bir metot olarak eklenebilir — `uploadFile()` değişmez,
///   mevcut implementasyonlar kırılmaz.
abstract class UploadAdapter {
  /// Dosyayı sunucuya yükler ve sonucu döner.
  ///
  /// [taskId] — idempotency key (UUID); backend tekrar eden isteği ayırt etmek için kullanır.
  /// [filePath] — yüklenecek dosyanın yerel yolu.
  /// [metadata] — `jsonEncode` ile kodlanabilir anahtar-değer çiftleri.
  /// [checksum] — SHA-256, sunucu tarafı doğrulama için.
  /// [onProgress] — `(bytesSent, totalBytes)` callback; `null` ise hiç çağrılmaz.
  /// [cancelToken] — iptal sinyali; `null` ise adapter iptal desteği sunmaz.
  Future<UploadResult> uploadFile({
    required String taskId,
    required String filePath,
    required Map<String, dynamic> metadata,
    required String checksum,
    void Function(int sent, int total)? onProgress,
    UploadCancelToken? cancelToken,
  });
}
