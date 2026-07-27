import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';

/// Bağlantı durumunun soyut temsili.
///
/// ⚠️ Sıra sabittir — yeni değer yalnızca sona ekle.
enum ConnectivityStatus {
  /// İnternet bağlantısı yok.
  none,

  /// Hücresel (cellular/mobile) bağlantı.
  cellular,

  /// Wi-Fi bağlantısı.
  wifi,

  /// Diğer (Ethernet, VPN, vs.).
  other,
}

/// Ağ bağlantısı izleme arayüzü.
///
/// `UploadQueue` bu arayüzü kullanır; varsayılan implementasyon
/// [DefaultConnectivityMonitor]'dür. Testlerde mock enjekte edebilirsiniz:
///
/// ```dart
/// class AlwaysWifiMonitor implements ConnectivityMonitor {
///   @override
///   Future<ConnectivityStatus> checkStatus() async => ConnectivityStatus.wifi;
///   @override
///   Stream<ConnectivityStatus> get statusStream =>
///       Stream.value(ConnectivityStatus.wifi);
/// }
///
/// final queue = UploadQueue(
///   adapter: ...,
///   connectivityMonitor: AlwaysWifiMonitor(),
/// );
/// ```
abstract class ConnectivityMonitor {
  /// Anlık bağlantı durumunu döner.
  ///
  /// `wifiOnly: true` etkinken worker bu metodu çağırarak bağlantı tipini
  /// kontrol eder. Eğer [DefaultConnectivityMonitor] kullanılıyorsa gerçek
  /// bir reachability testi (HEAD isteği) yapılır — captive portal gibi
  /// "bağlı görünüp gerçekte erişilemeyen" durumları da yakalar.
  Future<ConnectivityStatus> checkStatus();

  /// Bağlantı değişikliklerini yayınlayan stream.
  ///
  /// Worker bu stream'e abone olarak bağlantı geldiğinde otomatik devreye
  /// girer. Stream hiç kapanmaz — `dispose()` çağrıldığında abonelik
  /// [QueueController] tarafından iptal edilir.
  Stream<ConnectivityStatus> get statusStream;
}

/// `connectivity_plus` + reachability testi tabanlı varsayılan implementasyon.
///
/// ## Reachability testi
///
/// `connectivity_plus` yalnızca ağ arayüzünün bağlı olup olmadığını söyler;
/// captive portal'lar (otel Wi-Fi'si, havalimanı ağı) bağlı görünür ama
/// internet erişimi olmayabilir. Bu sınıf ek olarak [reachabilityUrl]'e
/// bir HEAD isteği atarak **gerçek** erişilebilirliği doğrular.
///
/// ## Gizlilik notu
///
/// Varsayılan [reachabilityUrl] (`https://connectivitycheck.gstatic.com/generate_204`)
/// Google'ın captive portal tespit ucu'dur. Bu istek herhangi bir kullanıcı
/// verisi taşımaz ancak KVKK/GDPR kapsamında üçüncü taraf ağ trafiğine
/// hassas uygulamalar için uygun olmayabilir. Bu durumda kendi altyapınızın
/// health-check endpoint'ini kullanın:
///
/// ```dart
/// DefaultConnectivityMonitor(reachabilityUrl: 'https://api.myapp.com/health')
/// ```
class DefaultConnectivityMonitor implements ConnectivityMonitor {
  /// Reachability testi için HEAD isteği atılacak URL.
  ///
  /// `null` bırakılırsa `https://connectivitycheck.gstatic.com/generate_204`
  /// kullanılır.
  final String? reachabilityUrl;

  static const _defaultReachabilityUrl =
      'https://connectivitycheck.gstatic.com/generate_204';

  static const _reachabilityTimeout = Duration(seconds: 5);

  final Connectivity _connectivity;
  late final StreamController<ConnectivityStatus> _controller;
  StreamSubscription<List<ConnectivityResult>>? _sub;
  final Dio _dio;

  DefaultConnectivityMonitor({
    this.reachabilityUrl,
    Connectivity? connectivity,
    Dio? dio,
  })  : _connectivity = connectivity ?? Connectivity(),
        _dio = dio ??
            Dio(BaseOptions(
              connectTimeout: _reachabilityTimeout,
              receiveTimeout: _reachabilityTimeout,
            )) {
    _controller = StreamController<ConnectivityStatus>.broadcast(
      onListen: _startListening,
      onCancel: _stopListening,
    );
  }

  String get _url => reachabilityUrl ?? _defaultReachabilityUrl;

  void _startListening() {
    _sub = _connectivity.onConnectivityChanged.listen((results) async {
      final status = await _resolveStatus(results);
      if (!_controller.isClosed) {
        _controller.add(status);
      }
    });
  }

  void _stopListening() {
    _sub?.cancel();
    _sub = null;
  }

  /// `connectivity_plus` sonucunu [ConnectivityStatus]'e çevirir.
  /// Bağlı görünüyorsa reachability testi yapar.
  Future<ConnectivityStatus> _resolveStatus(
      List<ConnectivityResult> results) async {
    // En öncelikli bağlantı tipini al (wifi > mobile > others)
    final raw = _bestResult(results);
    if (raw == ConnectivityResult.none) return ConnectivityStatus.none;

    // Gerçek reachability testi
    final reachable = await _testReachability();
    if (!reachable) return ConnectivityStatus.none;

    return switch (raw) {
      ConnectivityResult.wifi => ConnectivityStatus.wifi,
      ConnectivityResult.mobile => ConnectivityStatus.cellular,
      _ => ConnectivityStatus.other,
    };
  }

  ConnectivityResult _bestResult(List<ConnectivityResult> results) {
    if (results.contains(ConnectivityResult.wifi)) {
      return ConnectivityResult.wifi;
    }
    if (results.contains(ConnectivityResult.mobile)) {
      return ConnectivityResult.mobile;
    }
    if (results.contains(ConnectivityResult.none)) {
      return ConnectivityResult.none;
    }
    return results.isNotEmpty ? results.first : ConnectivityResult.none;
  }

  /// HEAD isteği ile gerçek erişilebilirliği test eder.
  /// Herhangi bir HTTP yanıtı (2xx, 3xx, 4xx, 5xx) başarı sayılır;
  /// yalnızca zaman aşımı veya DNS hatası `false` döndürür.
  Future<bool> _testReachability() async {
    try {
      await _dio.head(_url);
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<ConnectivityStatus> checkStatus() async {
    final results = await _connectivity.checkConnectivity();
    return _resolveStatus(results);
  }

  @override
  Stream<ConnectivityStatus> get statusStream => _controller.stream;

  /// Kaynakları serbest bırakır. [QueueController.dispose()] tarafından çağrılır.
  Future<void> dispose() async {
    await _sub?.cancel();
    await _controller.close();
    _dio.close();
  }
}
