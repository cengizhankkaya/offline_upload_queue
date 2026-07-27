import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/upload_status.dart';
import 'tables.dart';

part 'database.g.dart';

/// Paketin SQLite veritabanı.
///
/// Drift kod üretimi gerektirir:
/// ```
/// dart run build_runner build --delete-conflicting-outputs
/// ```
///
/// ## Şema Migrasyon Kuralları
///
/// - Yeni kolon/tablo ekleyen her paket sürümü [schemaVersion]'ı artırmak **zorundadır**.
/// - [migration] içindeki `onUpgrade` bloğuna yeni bir `if (from < N)` dalı eklenir.
/// - Migrasyonlar kümülatif ve sıralı olmalı — kullanıcılar sürümleri atlayarak
///   güncelleyebilir (v1 → v3 doğrudan).
@DriftDatabase(tables: [UploadTasks, ActiveWorkerLock])
class QueueDatabase extends _$QueueDatabase {
  QueueDatabase([QueryExecutor? executor])
    : super(executor ?? _openConnection());

  /// Birim testlerde in-memory veritabanı kullanmak için:
  /// ```dart
  /// final db = QueueDatabase.forTesting(NativeDatabase.memory());
  /// ```
  QueueDatabase.forTesting(super.executor);

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) => m.createAll(),
    onUpgrade: (m, from, to) async {
      // v1 → v2 ve sonrası için örnek şablon:
      //
      // if (from < 2) {
      //   await m.addColumn(uploadTasks, uploadTasks.someNewColumn);
      // }
      // if (from < 3) {
      //   await m.createTable(someNewTable);
      // }
      //
      // Her `if (from < N)` bloğu bağımsız çalışır — kullanıcılar
      // sürümleri atlayarak güncelleyebilir.
    },
    beforeOpen: (details) async {
      // WAL modu etkinleştir — cross-isolate güvenli yazma için gerekli.
      // bkz. §7 (WAL/cross-isolate spike).
      await customStatement('PRAGMA journal_mode=WAL;');
      await customStatement('PRAGMA foreign_keys=ON;');
    },
  );
}

/// Varsayılan veritabanı bağlantısı: `getApplicationSupportDirectory()` altında.
LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dbFolder = await getApplicationSupportDirectory();
    final file = File(p.join(dbFolder.path, 'offline_upload_queue.db'));
    return NativeDatabase.createInBackground(file);
  });
}
