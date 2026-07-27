import 'dart:convert';

import 'package:dio/dio.dart';

import '../models/upload_status.dart';
import 'upload_adapter.dart';

/// Dio tabanlı REST upload adapter.
///
/// ## Kullanım
///
/// ```dart
/// final adapter = RestUploadAdapter(
///   baseUrl: 'https://api.example.com',
///   authHeaderProvider: () async => 'Bearer ${await tokenStore.getToken()}',
/// );
/// final queue = UploadQueue(adapter: adapter, ...);
/// ```
///
/// ## Auth Header
///
/// [authHeaderProvider] her `uploadFile()` çağrısında taze token almak için
/// çağrılır — statik olarak constructor'da bir kez değil. Bu sayede
/// `onAuthExpired` callback'inde yenilenen token bir sonraki denemede
/// otomatik olarak kullanılır; adapter ile token yenileme mekanizması
/// arasında ayrı bir köprü gerekmez.
///
/// `authHeaderProvider` `null` bırakılırsa hiç Authorization header eklenmez.
///
/// ## İptal Desteği
///
/// [UploadCancelToken] dio'nun kendi `CancelToken`'ına köprülenir:
/// `uploadFile()` başında `cancelToken?.registerOnCancel(dioCancelToken.cancel)`
/// çağrılır. `queue.cancel(taskId)` çağrısı bu zincirden gerçek HTTP isteğini keser.
class RestUploadAdapter implements UploadAdapter {
  final Dio _dio;

  /// Backend upload endpoint'inin kök URL'i.
  /// Upload isteği `$baseUrl/upload` adresine gönderilir.
  final String baseUrl;

  /// Her upload çağrısında taze auth header değeri sağlar.
  ///
  /// Örnek: `() async => 'Bearer ${await tokenStore.getToken()}'`
  final Future<String> Function()? authHeaderProvider;

  RestUploadAdapter({required this.baseUrl, this.authHeaderProvider, Dio? dio})
    : _dio = dio ?? Dio();

  @override
  Future<UploadResult> uploadFile({
    required String taskId,
    required String filePath,
    required Map<String, dynamic> metadata,
    required String checksum,
    void Function(int sent, int total)? onProgress,
    UploadCancelToken? cancelToken,
  }) async {
    // 1. Dio CancelToken oluştur ve paketin token'ına köprüle.
    final dioCancelToken = CancelToken();

    if (cancelToken != null) {
      // Nadir yarış durumu: cancel() istek başlamadan hemen önce çağrıldıysa
      // isteği hiç başlatma.
      if (cancelToken.isCancelled) {
        return const UploadResult.failure(FailureType.unknown);
      }
      // UploadCancelToken.cancel() çağrıldığında dio isteğini de kes.
      cancelToken.registerOnCancel(dioCancelToken.cancel);
    }

    // 2. Auth header'ı her çağrıda taze al.
    final headers = <String, String>{};
    if (authHeaderProvider != null) {
      headers['Authorization'] = await authHeaderProvider!();
    }

    try {
      final response = await _dio.post(
        '$baseUrl/upload',
        data: FormData.fromMap({
          'taskId': taskId,
          'checksum': checksum,
          'metadata': jsonEncode(metadata),
          'file': await MultipartFile.fromFile(filePath),
        }),
        cancelToken: dioCancelToken,
        options: Options(headers: headers),
        // onProgress yalnızca aktif dinleyici varsa geçirilir;
        // null ise dio hiç callback yapmaz — gereksiz chunk başına
        // Dart closure invocation maliyeti önlenir (bkz. §11.4).
        onSendProgress: onProgress == null
            ? null
            : (sent, total) => onProgress(sent, total),
      );

      return UploadResult.success(
        remoteChecksum: response.data?['checksum'] as String?,
      );
    } on DioException catch (e) {
      if (CancelToken.isCancel(e)) {
        // QueueController cancel() çağrısı zaten DB durumunu `cancelled`
        // yapacak — burada FailureType önemsiz.
        return const UploadResult.failure(FailureType.unknown);
      }
      return UploadResult.failure(_classifyDioError(e));
    }
  }

  /// DioException'ı [FailureType]'a dönüştürür.
  FailureType _classifyDioError(DioException e) {
    final statusCode = e.response?.statusCode;

    if (statusCode == null) {
      // Bağlantı kurulamadı, timeout vb.
      return FailureType.network;
    }

    if (statusCode == 401 || statusCode == 403) {
      return FailureType.authExpired;
    }

    if (statusCode == 413) {
      return FailureType.payloadTooLarge;
    }

    if (statusCode == 429) {
      return FailureType.rateLimited;
    }

    if (statusCode >= 400 && statusCode < 500) {
      // 401/403/413/429 yukarıda ele alındı — kalan 4xx kalıcı hata.
      return FailureType.badRequest;
    }

    if (statusCode >= 500) {
      return FailureType.serverError;
    }

    return FailureType.unknown;
  }
}
