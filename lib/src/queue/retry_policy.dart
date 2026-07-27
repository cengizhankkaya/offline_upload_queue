import 'dart:math';

import '../models/upload_status.dart';

/// Backoff stratejisi için temel arayüz.
///
/// İki somut implementasyon:
/// - [ExponentialBackoffStrategy]: `base * 2^retryCount + jitter` — varsayılan
/// - [FixedBackoffStrategy]: her denemede sabit bekleme süresi
sealed class BackoffStrategy {
  const BackoffStrategy();

  /// Exponential backoff + jitter.
  ///
  /// `base * 2^retryCount` süresine `[0, base)` arasında rastgele bir jitter
  /// eklenir. Sonuç [max]'ı geçemez.
  ///
  /// [base] başlangıç bekleme süresi (ör. `Duration(seconds: 2)`).
  /// [max] maksimum bekleme süresi (ör. `Duration(minutes: 10)`).
  const factory BackoffStrategy.exponential({
    required Duration base,
    required Duration max,
  }) = ExponentialBackoffStrategy;

  /// Her denemede sabit bekleme süresi.
  const factory BackoffStrategy.fixed(Duration duration) =
      FixedBackoffStrategy;

  /// [retryCount] denemesinden sonra beklenmesi gereken süre.
  ///
  /// [retryCount]: şimdiye kadar yapılan deneme sayısı (0'dan başlar;
  /// ilk hata sonrası `retryCount = 0`, ikinci hata sonrası `retryCount = 1` …).
  Duration compute(int retryCount);
}

/// Exponential backoff: `base * 2^retryCount + jitter(0..base)` — [BackoffStrategy.exponential] ile oluştur.
final class ExponentialBackoffStrategy extends BackoffStrategy {
  final Duration base;
  final Duration max;

  const ExponentialBackoffStrategy({required this.base, required this.max})
      : assert(
            base != Duration.zero, 'base sıfır olamaz — sonsuz döngü riski'),
        assert(max > base, 'max, base değerinden büyük olmalı');

  @override
  Duration compute(int retryCount) {
    final factor = 1 << retryCount.clamp(0, 30); // 2^retryCount, taşma korumalı
    final baseMs = base.inMilliseconds * factor;
    final jitterMs = (Random().nextDouble() * base.inMilliseconds).floor();
    final totalMs = (baseMs + jitterMs).clamp(0, max.inMilliseconds);
    return Duration(milliseconds: totalMs);
  }
}

/// Sabit bekleme süresi — [BackoffStrategy.fixed] ile oluştur.
final class FixedBackoffStrategy extends BackoffStrategy {
  final Duration duration;

  const FixedBackoffStrategy(this.duration);

  @override
  Duration compute(int retryCount) => duration;
}

/// Backoff ve retry stratejisi hesaplama.
///
/// ## Kullanım
///
/// ```dart
/// final policy = RetryPolicy(
///   maxAttempts: 6,
///   backoff: BackoffStrategy.exponential(
///     base: Duration(seconds: 2),
///     max: Duration(minutes: 10),
///   ),
/// );
///
/// final nextRetry = policy.nextRetryAt(retryCount: 2, failureType: FailureType.network);
/// if (nextRetry == null) {
///   // hemen tekrar dene
/// }
/// ```
class RetryPolicy {
  /// Toplam maksimum deneme sayısı (ilk deneme dahil).
  ///
  /// `maxAttempts: 6` → görev en fazla 6 kez denenir; 6. denemede de
  /// başarısız olursa `permanentlyFailed`'e düşer.
  ///
  /// Alt sınır: en az `1` olmalı. `QueueController.init()` bu değeri doğrular
  /// ve geçersizse `ArgumentError` fırlatır.
  final int maxAttempts;

  /// Denemeler arası bekleme stratejisi.
  final BackoffStrategy backoff;

  const RetryPolicy({
    required this.maxAttempts,
    required this.backoff,
  });

  /// Bu [failureType] kalıcı bir hata mı?
  ///
  /// `true` dönen tipler hiç backoff beklemeden anında `permanentlyFailed`'e
  /// düşer — retry yapılmaz.
  bool isPermanent(FailureType failureType) {
    return switch (failureType) {
      FailureType.fileNotFound => true,
      FailureType.corruptFile => true,
      FailureType.payloadTooLarge => true,
      FailureType.badRequest => true,
      // Geçici hatalar — retry mantıklı
      FailureType.network => false,
      FailureType.serverError => false,
      FailureType.rateLimited => false,
      FailureType.authExpired => false,
      FailureType.unknown => false,
    };
  }

  /// [retryCount] denemeden sonra artık yeniden deneme yapılmamalı mı?
  ///
  /// `retryCount` 0-indexed: 0 = ilk deneme başarısız (yani 1 deneme yapıldı).
  /// `maxAttempts - 1` veya daha fazla denemede başarısız olunmuşsa `true` döner.
  bool shouldPermanentlyFail(int retryCount) {
    return retryCount >= maxAttempts - 1;
  }

  /// Bir sonraki deneme zamanını hesaplar.
  ///
  /// `null` döndürürse görev hemen alınabilir (normalde bu yol çağrılmaz —
  /// `QueueController` sadece hata sonrasında bu metodu çağırır).
  ///
  /// [retryCount] mevcut başarısız deneme sayısı (0-indexed).
  /// [failureType] hatanın tipi — kalıcı hatalar için `null` döner çünkü
  ///   kalıcı hatalar zaten `permanentlyFailed`'e gider, retry hesabına girmez.
  /// [retryAfter] yalnızca `rateLimited` için: backend'in verdiği bekleme süresi.
  /// [from] bekleme süresinin hesaplanacağı başlangıç zamanı (varsayılan: `DateTime.now()`).
  DateTime? nextRetryAt({
    required int retryCount,
    required FailureType failureType,
    Duration? retryAfter,
    DateTime? from,
  }) {
    // Kalıcı hatalar retry beklemez — çağrılmamalı ama savunmalı kodlama
    if (isPermanent(failureType)) return null;

    final now = from ?? DateTime.now();

    // rateLimited: backend'in istediği süreye saygı göster
    if (failureType == FailureType.rateLimited && retryAfter != null) {
      return now.add(retryAfter);
    }

    return now.add(backoff.compute(retryCount));
  }
}
