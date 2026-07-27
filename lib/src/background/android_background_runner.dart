import 'package:workmanager/workmanager.dart';

/// Android arka plan görev tetikleme.
///
/// Kullanım (örnek uygulamanın `main()` / `Application` sınıfında):
/// ```dart
/// Workmanager().initialize(
///   callbackDispatcher,
///   isInDebugMode: kDebugMode,
/// );
/// ```
///
/// Kuyruk boş olmadığında background tetiklemesi zamanlamak için:
/// ```dart
/// AndroidBackgroundRunner.scheduleNextRun();
/// ```
///
/// ## Model
///
/// "En iyi çaba" (best-effort) modeli — bkz. plan §13, "Android Arka Plan
/// Stratejisi". Foreground service veya kalıcı bildirim **yoktur**; bunun
/// yerine `OneOffWorkRequest` zinciri kullanılır:
///
/// - Her tetiklendiğinde [taskName] işi çalışır.
/// - İş bitiminde kuyrukta hâlâ görev varsa yeni bir `OneOffWorkRequest`
///   zamanlanır (zincir devam eder).
/// - Kuyruk boşsa zincir durur — gereksiz uyanışlar önlenir.
///
/// Gerçek upload mantığı bu katmanda yoktur; bu dosya yalnızca işin
/// zamanlanmasını ve zincirin kurulmasını sağlar.
/// Paketin kullanıcısı kendi `callbackDispatcher`'ında [UploadQueue]'yu
/// başlatıp birkaç görevi drene ettikten sonra [scheduleNextRun] çağırmalıdır.
///
/// **Örnek callbackDispatcher (example/lib/main.dart):**
/// ```dart
/// @pragma('vm:entry-point')
/// void callbackDispatcher() {
///   Workmanager().executeTask((taskName, inputData) async {
///     if (taskName == AndroidBackgroundRunner.taskName) {
///       final queue = UploadQueue(...);
///       await queue.init();
///       // Birkaç görevi drene et (örn. maxItems: 3)
///       // ...
///       final hasPending = /* kuyruğu kontrol et */;
///       if (hasPending) await AndroidBackgroundRunner.scheduleNextRun();
///       await queue.dispose();
///       return true;
///     }
///     return false;
///   });
/// }
/// ```
class AndroidBackgroundRunner {
  AndroidBackgroundRunner._();

  /// workmanager'ın tanıyacağı görev adı.
  static const taskName = 'offline_upload_queue.drain';

  /// workmanager unique name — çakışan eski request varsa iptal edip
  /// yenisiyle değiştirir.
  static const _uniqueName = 'offline_upload_queue.drain.unique';

  /// Arka plan kuyruğunu drene etmek için bir sonraki çalışmayı zamanlar.
  ///
  /// [delay]: İşin başlangıcına kadar en az bekleme süresi.
  /// Varsayılan `Duration(minutes: 1)` — çok sık tekrar eden isteklerin
  /// sistemin onu "aşırı istekte bulunan" olarak işaretlemesini önler.
  ///
  /// [requiresNetwork]: `true` ise görev yalnızca ağ bağlantısı olduğunda
  /// tetiklenir (önerilen varsayılan).
  ///
  /// [requiresWifi]: `true` ise yalnızca WiFi bağlantısında tetiklenir —
  /// [UploadQueue]'nun `wifiOnly: true` ayarıyla eşleştirilmelidir.
  static Future<void> scheduleNextRun({
    Duration delay = const Duration(minutes: 1),
    bool requiresNetwork = true,
    bool requiresWifi = false,
  }) async {
    await Workmanager().registerOneOffTask(
      _uniqueName,
      taskName,
      initialDelay: delay,
      existingWorkPolicy: ExistingWorkPolicy.replace,
      constraints: Constraints(
        networkType: requiresWifi
            ? NetworkType
                  .unmetered // yalnızca WiFi (metered olmayan)
            : requiresNetwork
            ? NetworkType
                  .connected // herhangi bir ağ bağlantısı
            : NetworkType.notRequired,
      ),
    );
  }

  /// Zamanlanmış arka plan görevini iptal eder.
  ///
  /// Kuyruk boşaldığında zinciri durdurmak için çağrılır — pilde gereksiz
  /// uyanışları önler (bkz. plan §13, madde 1b).
  static Future<void> cancelScheduled() async {
    await Workmanager().cancelByUniqueName(_uniqueName);
  }
}
