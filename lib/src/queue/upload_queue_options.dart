/// Log seviyesi — `onLog` callback'inin parametre tipi.
///
/// ⚠️ Sıra sabittir — yeni değer yalnızca sona ekle.
enum LogLevel {
  /// Ayrıntılı debug bilgisi (geliştirme aşamasında kullanılır).
  debug,

  /// Genel bilgi — normal ama kayda değer olaylar.
  info,

  /// Beklenmeyen ama kurtarılabilir durum (ör. stale lock devralma).
  warning,

  /// Ciddi hata — müdahale gerekebilir.
  error,
}

/// Nadiren değiştirilen ileri düzey `UploadQueue` ayarları.
///
/// Çoğu kullanıcının dokunması gerekmez; varsayılanlar production için
/// uygundur. `UploadQueue` constructor'ına `advanced:` parametresiyle
/// enjekte edilir:
///
/// ```dart
/// UploadQueue(
///   adapter: ...,
///   advanced: UploadQueueAdvancedOptions(
///     heartbeatInterval: Duration(seconds: 15),
///     diskUsageWarningBytes: 100 * 1024 * 1024, // 100 MB
///     onDiskUsageWarning: (current, limit) =>
///         print('Disk uyarısı: $current byte / $limit byte'),
///   ),
/// )
/// ```
class UploadQueueAdvancedOptions {
  /// Worker kilidinin "stale" (ölü) sayılacağı eşik.
  ///
  /// Bir worker bu süre boyunca heartbeat göndermezse, bir sonraki `init()`
  /// çağrısı kilidi devralar ve `uploading → pending` recovery yapar.
  ///
  /// **Kalibrasyona dikkat:** Varsayılan `5 dakika` deneysel bir tahmindir;
  /// gerçek yazım sürelerinize göre ayarlanmalıdır. Çok kısa seçilirse
  /// yaşayan bir worker'a ait kilit yanlışlıkla devralınabilir. Çok uzun
  /// seçilirse kilitli görev uzun süre işlenmeden kalır.
  ///
  /// **Kısıt:** `staleLockThreshold >= heartbeatInterval * 3` olmalı;
  /// aksi halde `init()` `ArgumentError` fırlatır.
  final Duration staleLockThreshold;

  /// Worker'ın aktif olduğunu kanıtlamak için DB'ye heartbeat yazdığı aralık.
  ///
  /// Varsayılan: 30 saniye. Çok düşük değerler gereksiz DB yazımına,
  /// çok yüksek değerler kilid devralmanın gecikmesine yol açar.
  final Duration heartbeatInterval;

  /// Bu byte eşiğini aşan toplam disk kullanımında [onDiskUsageWarning]
  /// tetiklenir. `null` ise disk uyarısı devre dışıdır.
  ///
  /// Uyarı yalnızca bilgilendirme amaçlıdır — hiçbir görevi engellemez
  /// veya otomatik silmez (bkz. Bölüm 4, \"tam backpressure değil\").
  final int? diskUsageWarningBytes;

  /// Hardlink başarısız olduktan sonra byte-kopyalama stratejisi eşiği.
  ///
  /// `copyToSandbox` etkinken sıra her zaman: (1) hardlink (`ln`,
  /// Windows hariç), (2) başarısızsa kopya. Bu eşik yalnızca adım (2)
  /// içindir: dosya boyutu eşikten **büyükse** streaming copy, aksi
  /// halde `File.copy` kullanılır.
  ///
  /// `null` (varsayılan) → hardlink sonrası her boyutta `File.copy`
  /// (streaming yok). Büyük dosyalar için örn. `50 * 1024 * 1024`.
  final int? sandboxCopyThresholdBytes;

  /// Disk kullanımı [diskUsageWarningBytes] eşiğini her aşışında çağrılır.
  ///
  /// `currentBytes`: anlık toplam kullanım.
  /// `warningBytes`: [diskUsageWarningBytes] değeri.
  ///
  /// `null` ise (varsayılan) hiçbir ek maliyet oluşmaz.
  final void Function(int currentBytes, int warningBytes)? onDiskUsageWarning;

  /// Paketin içindeki anormal veya nadir dahili olayları dışa açan kanca.
  ///
  /// ## Ne zaman çağrılır?
  ///
  /// Yalnızca aşağıdaki gibi "sessiz" dahili olaylarda:
  /// - Stale lock devralma (`LogLevel.warning`)
  /// - Auth timeout aşımı (`LogLevel.warning`)
  /// - `corruptFile`'a düşme (`LogLevel.warning`)
  /// - Sandbox kopyalama hatası (`LogLevel.error`)
  /// - `sequenceNumber` çakışması ve otomatik retry (`LogLevel.debug`)
  ///
  /// ## Ne zaman çağrılmaz?
  ///
  /// Sıradan upload akışı (`enqueue` → `completed`) loglanmaz.
  /// Bunun için `watchSummary()` ve `watchTasks()` kullanın.
  ///
  /// ## Kullanım
  ///
  /// ```dart
  /// onLog: (message, {required level}) {
  ///   if (level == LogLevel.warning || level == LogLevel.error) {
  ///     Sentry.captureMessage(message, level: SentryLevel.warning);
  ///   }
  /// }
  /// ```
  ///
  /// `null` bırakılırsa (varsayılan) sıfır ek maliyet — paket aynı
  /// şekilde çalışmaya devam eder.
  final void Function(String message, {required LogLevel level})? onLog;

  const UploadQueueAdvancedOptions({
    this.staleLockThreshold = const Duration(minutes: 5),
    this.heartbeatInterval = const Duration(seconds: 30),
    this.diskUsageWarningBytes,
    this.sandboxCopyThresholdBytes,
    this.onDiskUsageWarning,
    this.onLog,
  });
}
