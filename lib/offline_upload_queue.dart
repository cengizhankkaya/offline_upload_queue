/// offline_upload_queue — public API barrel dosyası.
///
/// Bu dosya yalnızca dışa açılacak sembolleri export eder.
/// İç implementasyon detayları (`src/` altındaki dosyalar) doğrudan
/// kullanılmamalı; yalnızca bu barrel üzerinden erişilmeli.
library;

// ── Modeller ─────────────────────────────────────────────────────────────────
export 'src/models/upload_status.dart';
export 'src/models/upload_task.dart';
export 'src/models/queue_summary.dart';

// ── Ağ katmanı ────────────────────────────────────────────────────────────────
export 'src/network/upload_adapter.dart';
export 'src/network/rest_upload_adapter.dart';
export 'src/network/connectivity_monitor.dart';

// ── Kuyruk (public API) ───────────────────────────────────────────────────────
export 'src/queue/upload_queue.dart';
export 'src/queue/upload_queue_options.dart' show UploadQueueAdvancedOptions, LogLevel;
export 'src/queue/retry_policy.dart' show BackoffStrategy, RetryPolicy;

// ── Veritabanı (isteğe bağlı — ileri düzey kullanım için) ────────────────────
export 'src/database/database.dart';
export 'src/database/tables.dart';
export 'src/database/persistence_repository.dart';
