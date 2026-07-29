import 'dart:async';

import 'package:offline_upload_queue/offline_upload_queue.dart';

/// Upload'u programlı olarak duraklatıp devam ettirebilen test adapter'ı.
///
/// ## Kullanım alanları
///
/// - **Concurrency testleri:** Upload tam yürütülürken `cancel()` / `dispose()` çağrısı
/// - **Dispose sonrası gecikmiş response:** Adapter'ı dispose sonrası tamamla, state
///   bozulmaması doğrulanır
/// - **İptal semantiği:** `cancelToken` bağlantısı kopar mı test edilir
///
/// ## Örnek
///
/// ```dart
/// final adapter = ControllableUploadAdapter(pauseOnCall: true);
/// // ... controller init + enqueue ...
///
/// // Upload başladığında duraklar
/// await uploadingCompleter.future;
///
/// // Upload'u iptal et ve pending'e al (dispose semantiği)
/// await controller.dispose();
///
/// // Adapter'ı gecikmiş olarak tamamla — state bozulmamalı
/// adapter.resumeAll();
/// ```
class ControllableUploadAdapter implements UploadAdapter {
  final _pauseCompleters = <String, Completer<UploadResult>>{};

  /// Başlatılan upload'ların taskId listesi (sıralı).
  final List<String> startedTaskIds = [];

  UploadResult _defaultResult;

  /// `true` olduğunda her `uploadFile()` çağrısı bir Completer'a askıya alınır.
  /// `resume(taskId)` veya `resumeAll()` ile devam ettirilir.
  bool pauseOnCall;

  ControllableUploadAdapter({
    UploadResult? defaultResult,
    this.pauseOnCall = false,
  }) : _defaultResult = defaultResult ?? const UploadResult.success();

  /// Varsayılan upload sonucunu değiştirir.
  void setDefaultResult(UploadResult result) => _defaultResult = result;

  /// Verilen `taskId`'nin upload'u bekliyor mu?
  bool isWaiting(String taskId) {
    final c = _pauseCompleters[taskId];
    return c != null && !c.isCompleted;
  }

  /// Bekleyen herhangi bir upload var mı?
  bool get hasWaiting =>
      _pauseCompleters.values.any((c) => !c.isCompleted);

  /// Toplam adapter çağrı sayısı.
  int get callCount => startedTaskIds.length;

  /// Belirtilen `taskId`'nin upload'unu tamamlar.
  ///
  /// [result] verilmezse `_defaultResult` kullanılır.
  void resume(String taskId, {UploadResult? result}) {
    final c = _pauseCompleters[taskId];
    if (c != null && !c.isCompleted) {
      c.complete(result ?? _defaultResult);
    }
  }

  /// Bekleyen tüm upload'ları tamamlar.
  void resumeAll({UploadResult? result}) {
    for (final entry in _pauseCompleters.entries) {
      if (!entry.value.isCompleted) {
        entry.value.complete(result ?? _defaultResult);
      }
    }
  }

  @override
  Future<UploadResult> uploadFile({
    required String taskId,
    required String filePath,
    required Map<String, dynamic> metadata,
    required String checksum,
    void Function(int sent, int total)? onProgress,
    UploadCancelToken? cancelToken,
  }) async {
    startedTaskIds.add(taskId);

    if (!pauseOnCall) return _defaultResult;

    final completer = Completer<UploadResult>();
    _pauseCompleters[taskId] = completer;

    // Cancel token iptal edildiğinde completer'ı hata ile kapat
    cancelToken?.registerOnCancel(() {
      if (!completer.isCompleted) {
        completer.completeError(
          Exception('Upload iptal edildi: $taskId'),
          StackTrace.current,
        );
      }
    });

    return completer.future;
  }
}
