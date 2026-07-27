/// Enum'lardaki değer sırası Drift'in `intEnum<T>()` ile veritabanına
/// integer olarak kaydedilir. Yeni değerler yalnızca **sona** eklenmeli;
/// mevcut değerlerin sırası kesinlikle değiştirilmemeli — aksi hâlde var
/// olan kayıtların anlamı kayar ve veri bozulması oluşur.
library;

/// Bir yükleme görevinin anlık durumu.
enum UploadStatus {
  /// Kuyruğa alındı, henüz işlenmedi.
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
