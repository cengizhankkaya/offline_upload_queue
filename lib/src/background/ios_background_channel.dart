import 'package:flutter/services.dart';

/// iOS `BGTaskScheduler` entegrasyonu için Dart tarafı köprüsü.
///
/// Bu sınıf, iOS native tarafındaki `BGTaskScheduler` kayıt ve zamanlama
/// işlemlerini bir `MethodChannel` üzerinden çağırır.
///
/// ## Native Kurulum (Uygulama Geliştiricisi İçin)
///
/// ### 1. Info.plist
/// ```xml
/// <key>BGTaskSchedulerPermittedIdentifiers</key>
/// <array>
///   <string>com.example.app.upload_refresh</string>   <!-- BGAppRefreshTask -->
///   <string>com.example.app.upload_processing</string> <!-- BGProcessingTask -->
/// </array>
/// ```
///
/// ### 2. Xcode Capabilities
/// Signing & Capabilities → Background Modes:
/// - ✅ Background fetch
/// - ✅ Background processing
/// ⚠️ Bu işaretlenmezse sistem görevi **sessizce** hiç tetiklemez.
///
/// ### 3. AppDelegate.swift
/// ```swift
/// import BackgroundTasks
///
/// // application(_:didFinishLaunchingWithOptions:) içinde:
/// BGTaskScheduler.shared.register(
///   forTaskWithIdentifier: "com.example.app.upload_refresh",
///   using: nil
/// ) { task in
///   self.handleAppRefresh(task: task as! BGAppRefreshTask)
/// }
///
/// BGTaskScheduler.shared.register(
///   forTaskWithIdentifier: "com.example.app.upload_processing",
///   using: nil
/// ) { task in
///   self.handleProcessing(task: task as! BGProcessingTask)
/// }
/// ```
///
/// ### 4. AppDelegate.swift — handler'lar
/// ```swift
/// func handleAppRefresh(task: BGAppRefreshTask) {
///   // 20 saniyelik iç zaman aşımı + expirationHandler
///   let channel = FlutterMethodChannel(
///     name: "offline_upload_queue/bg_task",
///     binaryMessenger: flutterEngine.binaryMessenger
///   )
///   task.expirationHandler = {
///     channel.invokeMethod("onExpiration", arguments: nil)
///   }
///   channel.invokeMethod("onAppRefresh", arguments: nil) { result in
///     let hasPending = result as? Bool ?? false
///     task.setTaskCompleted(success: true)
///     if hasPending {
///       IosBackgroundChannel.scheduleAppRefresh() // zincirleme yeniden kayıt
///     }
///   }
/// }
///
/// func handleProcessing(task: BGProcessingTask) {
///   let channel = FlutterMethodChannel(...)
///   task.expirationHandler = {
///     channel.invokeMethod("onExpiration", arguments: nil)
///   }
///   channel.invokeMethod("onProcessing", arguments: nil) { result in
///     let hasPending = result as? Bool ?? false
///     task.setTaskCompleted(success: true)
///     if hasPending {
///       IosBackgroundChannel.scheduleAppRefresh()
///       IosBackgroundChannel.scheduleProcessing()
///     }
///   }
/// }
/// ```
///
/// ## Dart Tarafı Kullanımı
///
/// ```dart
/// // Uygulama başlangıcında (foreground):
/// IosBackgroundChannel.instance.setMethodCallHandler(
///   onAppRefresh: () => BackgroundTaskRunner.run(queue),
///   onProcessing: () => BackgroundTaskRunner.run(queue),
///   onExpiration: () {
///     // Sistem süremiz bitti dediğinde aktif upload'ları iptal edip pending'e döndür.
///     queue.dispose();
///   },
/// );
///
/// // Her iki görevi de zamanla (paralel):
/// await IosBackgroundChannel.instance.scheduleAppRefresh(
///   refreshIdentifier: 'com.example.app.upload_refresh',
/// );
/// await IosBackgroundChannel.instance.scheduleProcessing(
///   processingIdentifier: 'com.example.app.upload_processing',
///   requiresNetworkConnectivity: true,
/// );
/// ```
class IosBackgroundChannel {
  IosBackgroundChannel._();

  static const _channelName = 'offline_upload_queue/bg_task';

  static final instance = IosBackgroundChannel._();

  final _channel = const MethodChannel(_channelName);

  /// Native taraftan gelen metodları [queue] üzerinden işler.
  ///
  /// [onAppRefresh]: BGAppRefreshTask tetiklendiğinde çağrılır.
  ///   `hasPending` dönerse native taraf zincirleme yeniden kayıt yapar.
  ///
  /// [onProcessing]: BGProcessingTask tetiklendiğinde çağrılır.
  ///
  /// [onExpiration]: expirationHandler tetiklendiğinde çağrılır —
  ///   aktif upload'ı iptal etmek için kullanılır (bkz. plan §13 madde 2).
  void setMethodCallHandler({
    required Future<bool> Function() onAppRefresh,
    required Future<bool> Function() onProcessing,
    required void Function() onExpiration,
  }) {
    _channel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'onAppRefresh':
          return await onAppRefresh();
        case 'onProcessing':
          return await onProcessing();
        case 'onExpiration':
          onExpiration();
          return null;
        default:
          throw MissingPluginException(
            'IosBackgroundChannel: bilinmeyen metod "${call.method}"',
          );
      }
    });
  }

  /// `BGAppRefreshTaskRequest`'i zamanlar.
  ///
  /// [refreshIdentifier]: Info.plist'teki `BGTaskSchedulerPermittedIdentifiers`
  /// listesindeki identifier ile birebir aynı olmalı.
  ///
  /// [earliestBeginDate]: `null` ise mümkün olan en erken zamanda tetiklenir.
  /// Apple throttling riskini azaltmak için birkaç saniye gecikme denenebilir
  /// (bkz. plan §13, "Ayar notu — earliestBeginDate").
  Future<void> scheduleAppRefresh({
    required String refreshIdentifier,
    Duration? earliestBeginDate,
  }) async {
    await _channel.invokeMethod<void>('scheduleAppRefresh', {
      'identifier': refreshIdentifier,
      'earliestBeginDateSeconds': earliestBeginDate?.inSeconds,
    });
  }

  /// `BGProcessingTaskRequest`'i zamanlar.
  ///
  /// [processingIdentifier]: Info.plist'teki identifier.
  ///
  /// [requiresNetworkConnectivity]: `true` ise sistem görevi yalnızca ağ
  /// bağlantısı olduğunda tetikler. `wifiOnly: true` olan kuyruklar için de
  /// bu `true` olmalı — native tarafta Wi-Fi'ye özgü kısıt yoktur, asıl
  /// Wi-Fi filtresi worker içinde `ConnectivityMonitor` ile uygulanır
  /// (bkz. plan §13, "wifiOnly ile BGProcessingTaskRequest çelişkisi").
  ///
  /// [requiresExternalPower]: `true` ise yalnızca cihaz şarjdayken tetiklenir.
  Future<void> scheduleProcessing({
    required String processingIdentifier,
    bool requiresNetworkConnectivity = true,
    bool requiresExternalPower = false,
  }) async {
    await _channel.invokeMethod<void>('scheduleProcessing', {
      'identifier': processingIdentifier,
      'requiresNetworkConnectivity': requiresNetworkConnectivity,
      'requiresExternalPower': requiresExternalPower,
    });
  }
}
