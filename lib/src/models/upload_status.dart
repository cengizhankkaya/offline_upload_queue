/// Upload durumu ve hata tipi enum'ları.
///
/// ⚠️ **Kritik:** Sembast'ta integer (index) olarak veritabanına
/// kaydedilir. Mevcut değerlerin sırası kesinlikle değiştirilmemeli;
/// yeni değerler yalnızca **sona** eklenmeli. Aksi hâlde var olan
/// kayıtların anlamı kayar ve sessiz veri bozulması oluşur.
///
/// Yükleme işlemleri için durum yönetimi ve hata sınıflandırması sağlar.
library;

/// Bir yükleme görevinin anlık durumu.
enum UploadStatus {
  /// Kuyrukta bekliyor, henüz işlenmedi.
  /// Bu durumdaki görevler worker tarafından `sequenceNumber ASC` sırasıyla alınır.
  pending,

  /// Worker tarafından alındı, yükleme devam ediyor.
  uploading,

  /// Sunucuya başarıyla yüklendi.
  completed,

  /// Geçici hata — backoff sonrası tekrar denenecek.
  failed,

  /// Kalıcı hata — otomatik retry yok.
  /// Manuel [UploadQueue.retry] çağrısıyla tekrar [pending]'e alınabilir.
  permanentlyFailed,

  /// [UploadQueue.cancel] ile kullanıcı tarafından iptal edildi.
  /// Manuel [UploadQueue.retry] çağrısıyla tekrar [pending]'e alınabilir.
  cancelled,
}

/// Bir yükleme hatasının tipi.
///
/// [RetryPolicy] bu bilgiyi kullanarak hatanın geçici mi kalıcı mı
/// olduğuna karar verir.
///
/// ⚠️ Sıra sabittir — yeni değer yalnızca sona ekle.
enum FailureType {
  /// Geçici ağ hatası — retry mantıklı.
  network,

  /// 5xx sunucu hatası — geçici, retry mantıklı.
  serverError,

  /// 429 Too Many Requests — `Retry-After` header'a göre bekle.
  rateLimited,

  /// Token süresi doldu — retry öncesi yenilenmeli.
  authExpired,

  /// Dosya artık yok veya erişilemiyor — kalıcı hata.
  fileNotFound,

  /// Dosya okunamıyor / bozuk — kalıcı hata.
  /// Worker, bu karara varmadan önce 3 kısa deneme yapar (bkz. §3).
  corruptFile,

  /// Dosya sunucunun kabul ettiği boyut sınırını aşıyor — kalıcı hata.
  payloadTooLarge,

  /// 4xx (auth hariç) — kalıcı hata.
  badRequest,

  /// Sınıflandırılamayan hata.
  unknown,
}
