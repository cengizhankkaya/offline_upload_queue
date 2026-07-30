import 'dart:async';

import '../queue/upload_queue.dart';

/// Arka plan görevleri için ortak sarmalayıcı (wrapper) ve koordinatör.
///
/// İşletim sistemleri (iOS/Android) arka plan görevlerine katı zaman sınırları
/// koyar (örn. iOS'ta ~30 saniye). Bu sınıf:
/// 1. Verilen kuyruğu (`UploadQueue`) gerekirse başlatır.
/// 2. İçsel bir zaman aşımı (20 saniye) belirler.
/// 3. Kuyruğun bekleyen (pending) işlerini işlemeye başlamasını sağlar.
/// 4. Kuyruk boşaldığında veya 20 sn dolduğunda temiz bir kapanış yapar.
///
/// ## Yaşam döngüsü
///
/// - Kuyruk henüz `init()` edilmemişse (Android Workmanager isolate'i gibi)
///   bu sınıf onu başlatır ve bitince `dispose()` eder.
/// - Kuyruk zaten açıksa (iOS'ta paylaşılan foreground kuyruğu) yalnızca
///   deadline uygular; iş bitiminde **dispose etmez**.
///
/// ## iOS Entegrasyonu
/// `onAppRefresh` / `onProcessing` içinde kullanın; `onExpiration` için
/// `queue.abortActiveUploads()` tercih edin (`dispose` değil).
///
/// ## Android Entegrasyonu
/// `workmanager` `callbackDispatcher` içinde kullanın.
class BackgroundTaskRunner {
  /// [queue] çalıştırılacak UploadQueue örneği.
  /// [timeout] görevin maksimum çalışma süresi (varsayılan 20 saniye).
  static Future<bool> run(
    UploadQueue queue, {
    Duration timeout = const Duration(seconds: 20),
  }) async {
    final deadline = DateTime.now().add(timeout);
    bool hasPending = false;
    final ownedLifecycle = !queue.isInitialized;

    // Deadline'ı init öncesi sakla (UploadQueue buffer'lar) — init sonrası da set.
    queue.setBackgroundDeadline(deadline);

    try {
      if (ownedLifecycle) {
        await queue.init();
      } else {
        // Zaten init'li kuyrukta da deadline'ı taze uygula.
        queue.setBackgroundDeadline(deadline);
      }

      // ── Deadline-aware bekleme ────────────────────────────────────────────
      // Problem: watchSummary() sonsuz bir reactive stream'dir. Eğer kuyrukta
      // pending görev varken yeni DB eventi gelmezse, `await for` içindeki
      // deadline kontrolü asla tetiklenmez → hard timeout kaçırılır.
      //
      // Çözüm: `Future.any` ile iki yarış koşulunu paralel bekle:
      //   (a) stream'den kuyruk-boş sinyali
      //   (b) bağımsız `Future.delayed` ile hard deadline
      final emptyCompleter = Completer<void>();

      final sub = queue.watchSummary().listen((summary) {
        hasPending = summary.pending > 0 || summary.uploading > 0;
        if (!hasPending && !emptyCompleter.isCompleted) {
          emptyCompleter.complete();
        }
      });

      await Future.any([emptyCompleter.future, Future<void>.delayed(timeout)]);

      await sub.cancel();
    } catch (_) {
      // Beklenmeyen hata — finally temizler
    } finally {
      queue.setBackgroundDeadline(null);
      // Yalnızca bu çağrıda açtığımız kuyruğu kapat (paylaşılan iOS kuyruğunu değil).
      if (ownedLifecycle) {
        await queue.dispose();
      }
    }

    // iOS/Android zincirleme mantığı: hâlâ bekleyen iş varsa yeniden kayıt.
    return hasPending;
  }
}
