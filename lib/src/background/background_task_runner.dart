import 'dart:async';

import '../queue/upload_queue.dart';

/// Arka plan görevleri için ortak sarmalayıcı (wrapper) ve koordinatör.
///
/// İşletim sistemleri (iOS/Android) arka plan görevlerine katı zaman sınırları
/// koyar (örn. iOS'ta ~30 saniye). Bu sınıf:
/// 1. Verilen kuyruğu (`UploadQueue`) başlatır.
/// 2. İçsel bir zaman aşımı (20 saniye) belirler.
/// 3. Kuyruğun bekleyen (pending) işlerini işlemeye başlamasını sağlar.
/// 4. Kuyruk boşaldığında veya 20 sn dolduğunda temiz bir kapanış (`dispose`)
///    yapar ve sonucu işletim sistemine bildirir.
///
/// ## iOS Entegrasyonu
/// `onAppRefresh` ve `onProcessing` çağrılarında bu sınıf kullanılır.
/// (Bkz. plan §13)
///
/// ## Android Entegrasyonu
/// `workmanager`'ın `callbackDispatcher` metodunda bu sınıf kullanılır.
/// (Bkz. plan §13)
class BackgroundTaskRunner {
  /// [queue] çalıştırılacak UploadQueue örneği.
  /// [timeout] görevin maksimum çalışma süresi (varsayılan 20 saniye). İşletim
  ///   sistemi görevi sonlandırmadan önce bizim kendi içimizde temiz kapanış
  ///   yapabilmemiz için bu süre OS sınırından (30sn) kısa olmalıdır.
  static Future<bool> run(
    UploadQueue queue, {
    Duration timeout = const Duration(seconds: 20),
  }) async {
    final deadline = DateTime.now().add(timeout);
    bool hasPending = false;

    // Kuyruğa arka plan deadline'ını bildir (authTimeout bütçesi için)
    queue.setBackgroundDeadline(deadline);

    try {
      await queue.init();

      // ── Deadline-aware bekleme ────────────────────────────────────────────
      // Problem: watchSummary() sonsuz bir reactive stream'dir. Eğer kuyrukta
      // pending görev varken yeni DB eventi gelmezse, `await for` içindeki
      // deadline kontrolü asla tetiklenmez → hard timeout kaçırılır.
      //
      // Çözüm: `Future.any` ile iki yarış koşulunu paralel bekle:
      //   (a) stream'den kuyruk-boş sinyali
      //   (b) bağımsız `Future.delayed` ile 20 sn hard deadline
      // Hangisi önce tamamlanırsa döngü sonlanır.
      final emptyCompleter = Completer<void>();

      final sub = queue.watchSummary().listen((summary) {
        hasPending = summary.pending > 0 || summary.uploading > 0;
        if (!hasPending && !emptyCompleter.isCompleted) {
          emptyCompleter.complete();
        }
      });

      await Future.any([emptyCompleter.future, Future<void>.delayed(timeout)]);

      await sub.cancel();
    } catch (e) {
      // Beklenmeyen hata — dispose() finally'de çalışır
    } finally {
      // Temiz kapanış — aktif yükleme varsa iptal eder ve durumu pending'e döndürür.
      await queue.dispose();
      queue.setBackgroundDeadline(null);
    }

    // iOS/Android zincirleme mantığı: Eğer hala bekleyen iş varsa OS'a
    // zincirleme yeniden kayıt yapmasını söyle (true dönerek).
    return hasPending;
  }
}
