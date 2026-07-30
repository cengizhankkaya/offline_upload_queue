# offline_upload_queue example

Bu uygulama paketin public API'sini ve platform arka plan kurulumunu gösterir.

## Çalıştırma

```bash
# Opsiyonel: kökteki mock sunucu (ExampleRestAdapter için)
dart run tool/mock_server.dart

cd example
flutter run
```

## Ekranlar

| Sekme | Ne test eder |
|---|---|
| Kuyruk | enqueue, progress, cancel, özet stream'leri |
| Cellular | `wifiOnly` + `forceUploadOnce` |
| Hata | kalıcı / geçici hata ve retry |
| Disk | sandbox kullanımı ve uyarı eşiği |
| Debug | loglar, pause/resume, purge |

## Platform kurulumu

- **iOS:** `Info.plist` BGTask kimlikleri + `AppDelegate.swift` MethodChannel
- **Android:** `Workmanager` `callbackDispatcher` + `RECEIVE_BOOT_COMPLETED`

Ayrıntılar için kök [README.md](../README.md) içindeki Background Sync bölümüne bakın.
