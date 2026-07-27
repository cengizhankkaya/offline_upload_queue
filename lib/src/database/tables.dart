import 'package:drift/drift.dart';

import '../models/upload_status.dart';

/// Composite index: `getNextPending` sorgusunun yüksek performanslı çalışması
/// için `status`, `nextRetryAt` ve `sequenceNumber` üzerinde.
///
/// Kuyruk büyüdükçe bu index olmadan sorgu lineer taramaya döner.
@TableIndex(
  name: 'idx_upload_tasks_status_retry_seq',
  columns: {#status, #nextRetryAt, #sequenceNumber},
)
@DataClassName('UploadTaskData')
class UploadTasks extends Table {
  /// Dahili otomatik artan birincil anahtar.
  IntColumn get localId => integer().autoIncrement()();

  /// UUID — idempotency key; backend'e bu değer gönderilir.
  TextColumn get taskId => text().unique()();

  /// Dosyanın yerel yolu.
  ///
  /// `copyToSandbox: true` (varsayılan) ise bu, paketin kendi sandbox
  /// kopyasının yolunu tutar — orijinal dosya değil.
  TextColumn get filePath => text()();

  /// Monoton artan mantıksal sıra numarası.
  ///
  /// `getNextPending` sorgusu bu alana göre sıralar.
  /// ⚠️ UNIQUE constraint var — çakışma durumunda `enqueue()` en fazla
  /// 3 kez yeniden dener (bkz. §11.7).
  IntColumn get sequenceNumber => integer()();

  /// Görevin anlık durumu. Drift `intEnum<UploadStatus>()` kullanır.
  ///
  /// ⚠️ [UploadStatus] enum sırası kesinlikle değiştirilmemeli.
  IntColumn get status => intEnum<UploadStatus>()();

  /// Son hatanın tipi. `null` ise henüz hata yok.
  IntColumn get failureType => intEnum<FailureType>().nullable()();

  /// Kaç kez denendiği.
  IntColumn get retryCount => integer().withDefault(const Constant(0))();

  /// `metadata` alanının JSON string'i.
  ///
  /// Yalnızca `jsonEncode` destekli tipler (String, num, bool, null, List, Map).
  /// Geçersiz tip verilirse `enqueue()` senkron `ArgumentError` fırlatır.
  TextColumn get metadataJson => text().nullable()();

  /// SHA-256 checksum. `pending` durumunda `null`; `uploading`'e geçerken
  /// doldurulur.
  TextColumn get checksum => text().nullable()();

  /// Sandbox kopyasının bayt cinsinden boyutu.
  ///
  /// `enqueue()` sırasında `stat()` ile tek seferlik doldurulur.
  /// `estimatedDiskUsageBytes` bu kolonun `SUM`'udur — dosya sistemine
  /// dokunmadan ucuz SQL sorgusuyla hesaplanır.
  IntColumn get fileSizeBytes => integer().nullable()();

  /// İnsan okunabilir hata mesajı (debug/UI amaçlı).
  TextColumn get errorMessage => text().nullable()();

  /// Görevin kuyruğa alındığı zaman.
  DateTimeColumn get createdAt => dateTime()();

  /// Backoff sonrası bir sonraki deneme zamanı.
  ///
  /// `null` ise görev hemen alınabilir.
  /// `getNextPending` sorgusu: `nextRetryAt IS NULL OR nextRetryAt <= :now`
  DateTimeColumn get nextRetryAt => dateTime().nullable()();

  @override
  List<Set<Column>> get uniqueKeys => [
    {sequenceNumber},
  ];
}

/// Worker kilidi için tek satırlık tablo.
///
/// Atomik koşullu `UPDATE` ile devralma + heartbeat mekanizması için
/// kullanılır (bkz. §7). Her zaman tek bir satır tutar (`id = 0`).
class ActiveWorkerLock extends Table {
  /// Sabit birincil anahtar — her zaman `0`.
  IntColumn get id => integer().withDefault(const Constant(0))();

  /// Kilidin alındığı zaman.
  DateTimeColumn get acquiredAt => dateTime()();

  /// Kilidin sahibi (isolate/worker kimliği). Debug amaçlı, nullable.
  TextColumn get ownerId => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}
