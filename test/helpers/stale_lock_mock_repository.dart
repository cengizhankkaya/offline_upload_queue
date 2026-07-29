import 'dart:async';

import 'in_memory_persistence_repository.dart';

/// Kilit davranışını kontrol edebilen test `PersistenceRepository`.
///
/// `InMemoryPersistenceRepository`'yi genişletir; yalnızca
/// `tryAcquireLock()` ve `watchLockUpdates()` davranışı değiştirilir.
///
/// ## Kullanım
///
/// ```dart
/// // İlk 1 çağrıda false, sonrasında true döner (stale lock simülasyonu)
/// final repo = StaleLockMockRepository(callsBeforeSuccess: 1);
///
/// // İlk false döndüğünde otomatik olarak watchLockUpdates'e event emit et
/// // (lockReleaseCompleter timeout'dan önce çözülsün)
/// ```
class StaleLockMockRepository extends InMemoryPersistenceRepository {
  int _acquireCallCount = 0;

  /// İlk kaç `tryAcquireLock()` çağrısında `false` dönülecek.
  final int callsBeforeSuccess;

  /// İlk `false` dönüşünden sonra lock update event'i ne kadar gecikmeli gönderilsin.
  final Duration releaseDelay;

  final _lockController = StreamController<void>.broadcast();

  StaleLockMockRepository({
    this.callsBeforeSuccess = 1,
    this.releaseDelay = const Duration(milliseconds: 15),
  });

  /// Toplam `tryAcquireLock` çağrı sayısı.
  int get acquireCallCount => _acquireCallCount;

  /// Lock update stream'ine manuel olarak event gönderir.
  void simulateLockRelease() {
    if (!_lockController.isClosed) _lockController.add(null);
  }

  @override
  Future<bool> tryAcquireLock(
    String ownerId,
    Duration staleLockThreshold,
  ) async {
    _acquireCallCount++;
    if (_acquireCallCount <= callsBeforeSuccess) {
      // Kilit başka bir worker'da — belirli süre sonra "serbest bırakıldı" sinyali gönder
      Future<void>.delayed(releaseDelay, simulateLockRelease);
      return false;
    }
    return true;
  }

  @override
  Stream<void> watchLockUpdates() => _lockController.stream;

  @override
  Future<void> dispose() async {
    if (!_lockController.isClosed) await _lockController.close();
    await super.dispose();
  }
}

/// Her zaman `false` döndüren lock mock'u — lock hiç alınamaz.
///
/// `init()` sırasında kilit alınamama senaryolarını test etmek için kullanılır.
class NeverAcquiresLockRepository extends InMemoryPersistenceRepository {
  int _acquireCallCount = 0;

  int get acquireCallCount => _acquireCallCount;

  @override
  Future<bool> tryAcquireLock(
    String ownerId,
    Duration staleLockThreshold,
  ) async {
    _acquireCallCount++;
    return false; // Asla kilidi alamaz
  }

  @override
  Stream<void> watchLockUpdates() => const Stream.empty();
}
