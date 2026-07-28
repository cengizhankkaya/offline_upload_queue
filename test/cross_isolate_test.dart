/// Cross-isolate WAL testleri — Aşama 1, test #12.
///
/// Bu testler gerçek bir SQLite WAL veritabanı dosyası + birden fazla
/// Dart isolate kullanır. Flaky çıkma riski diğer unit testlerden yüksek
/// olduğu için CI'da **ayrı bir job**'da çalışır (bkz. .github/workflows/ci.yml).
///
/// CI filtreleme: `flutter test --tags cross_isolate`
/// Ana suite dışlama: `flutter test --exclude-tags cross_isolate`
@Tags(['cross_isolate'])
library;

import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:test/test.dart';
import 'package:offline_upload_queue/src/database/database.dart';
import 'package:offline_upload_queue/src/database/drift_persistence_repository.dart';
import 'package:offline_upload_queue/src/models/upload_status.dart';
import 'package:path/path.dart' as p;

// ─────────────────────────────────────────────────────────────────────────────
// Yardımcı: geçici dizinde WAL etkin SQLite veritabanı aç
// ─────────────────────────────────────────────────────────────────────────────

/// Geçici bir dosya yoluna WAL modunda NativeDatabase açar.
///
/// Dönen [QueryExecutor] ile [QueueDatabase] ya da [DriftPersistenceRepository]
/// oluşturulabilir. Test sonunda `dispose()` çağırıldıktan sonra dosyayı sil.
QueueDatabase openWalDb(String filePath) {
  final file = File(filePath);
  final executor = NativeDatabase(
    file,
    setup: (db) {
      db.execute('PRAGMA journal_mode=WAL;');
      db.execute('PRAGMA foreign_keys=ON;');
    },
  );
  return QueueDatabase.forTesting(executor);
}

// ─────────────────────────────────────────────────────────────────────────────
// Isolate giriş noktaları (top-level — Isolate.spawn gereksinimi)
// ─────────────────────────────────────────────────────────────────────────────

/// İkinci isolate: verilen DB dosyasına [count] adet görev enqueue eder,
/// tamamlayınca [sendPort]'a enqueue edilen taskId listesini gönderir.
Future<void> _secondIsolateWorker(List<dynamic> args) async {
  final String dbPath = args[0] as String;
  final int count = args[1] as int;
  final SendPort sendPort = args[2] as SendPort;

  final db = openWalDb(dbPath);
  final repo = DriftPersistenceRepository(db);
  await repo.init();

  final ids = <String>[];
  for (var i = 0; i < count; i++) {
    final seq = await repo.getNextSequenceNumber();
    final task = await repo.enqueue(
      taskId: 'isolate2-task-$i',
      filePath: '/tmp/dummy-$i.jpg',
      sequenceNumber: seq,
      fileSizeBytes: 1024 * (i + 1),
    );
    ids.add(task.taskId);
  }

  await repo.dispose();
  await db.close();

  sendPort.send(ids);
}

/// İkinci isolate: kilit almayı dener, sonucu [sendPort]'a gönderir.
Future<void> _lockContestIsolate(List<dynamic> args) async {
  final String dbPath = args[0] as String;
  final SendPort sendPort = args[1] as SendPort;

  final db = openWalDb(dbPath);
  final repo = DriftPersistenceRepository(db);
  await repo.init();

  // Birinciyle aynı anda çalışıyor; birinin false alması beklenir.
  final acquired = await repo.tryAcquireLock(
    'isolate-2',
    const Duration(seconds: 30),
  );

  await repo.dispose();
  await db.close();

  sendPort.send(acquired);
}

// ─────────────────────────────────────────────────────────────────────────────
// Testler
// ─────────────────────────────────────────────────────────────────────────────

void main() {
  late Directory tempDir;
  late String dbPath;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('cross_isolate_test_');
    dbPath = p.join(tempDir.path, 'test.db');
  });

  tearDown(() async {
    // Dosyaları temizle (WAL dosyaları da silinir)
    await tempDir.delete(recursive: true);
  });

  // ── Test #12-A: İki isolate'ten eşzamanlı enqueue ─────────────────────────
  test(
    '#12-A iki isolate aynı WAL DB\'ye eşzamanlı enqueue yapabilir',
    () async {
      // Ana isolate: 3 görev yazar
      final db1 = openWalDb(dbPath);
      final repo1 = DriftPersistenceRepository(db1);
      await repo1.init();

      for (var i = 0; i < 3; i++) {
        final seq = await repo1.getNextSequenceNumber();
        await repo1.enqueue(
          taskId: 'isolate1-task-$i',
          filePath: '/tmp/file-$i.jpg',
          sequenceNumber: seq,
        );
      }

      // İkinci isolate: 3 görev daha yazar
      final receivePort = ReceivePort();
      await Isolate.spawn(
        _secondIsolateWorker,
        [dbPath, 3, receivePort.sendPort],
      );
      final List<String> isolate2Ids =
          await receivePort.first as List<String>;

      // Her iki isolate'in görevleri DB'de görünmeli
      final allTasks = await (db1.select(db1.uploadTasks)).get();
      final allIds = allTasks.map((t) => t.taskId).toSet();

      expect(
        allIds,
        containsAll(['isolate1-task-0', 'isolate1-task-1', 'isolate1-task-2']),
        reason: 'Ana isolate görevleri DB\'de olmalı',
      );
      expect(
        allIds,
        containsAll(isolate2Ids),
        reason: 'İkinci isolate görevleri de DB\'de olmalı',
      );
      expect(allTasks.length, equals(6), reason: 'Toplam 6 görev olmalı');

      // sequenceNumber'ların çakışmaması (UNIQUE constraint hayatta)
      final seqs = allTasks.map((t) => t.sequenceNumber).toList();
      expect(seqs.toSet().length, equals(6), reason: 'Tüm sequence numaraları benzersiz olmalı');

      await repo1.dispose();
      await db1.close();
      receivePort.close();
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );

  // ── Test #12-B: WAL read — bir isolate yazarken diğeri okuyabilir ─────────
  test(
    '#12-B WAL: bir isolate yazarken diğeri eski snapshot\'ı okuyabilir',
    () async {
      // Önce DB'yi ve şemayı oluştur
      final db1 = openWalDb(dbPath);
      final repo1 = DriftPersistenceRepository(db1);
      await repo1.init();

      // Okuyucu isolate başlamadan önce 1 görev yaz (başlangıç durumu)
      await repo1.enqueue(
        taskId: 'seed-task',
        filePath: '/tmp/seed.jpg',
        sequenceNumber: 1,
      );

      // Ana isolate okuma yapar
      final pendingBefore = await repo1.getNextSequenceNumber();

      // İkinci isolate 3 görev daha yazar
      final receivePort = ReceivePort();
      await Isolate.spawn(
        _secondIsolateWorker,
        [dbPath, 3, receivePort.sendPort],
      );
      await receivePort.first; // isolate tamamlanmasını bekle

      // Ana isolate'in yeni okuması tüm görevleri görmeli (WAL checkpoint)
      final seqAfter = await repo1.getNextSequenceNumber();

      // Yeni sequence, eski sequence'dan büyük olmalı (yeni görevler eklendi)
      expect(
        seqAfter,
        greaterThan(pendingBefore),
        reason: 'İkinci isolate yazdıktan sonra sequence numarası artmalı',
      );

      await repo1.dispose();
      await db1.close();
      receivePort.close();
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );

  // ── Test #12-C: Kilit yarışı — tek worker kilidi alabilir ─────────────────
  test(
    '#12-C kilit yarışı: iki isolate\'ten yalnızca biri kilidi alabilir',
    () async {
      // DB oluştur ve şemayı kur
      final db1 = openWalDb(dbPath);
      final repo1 = DriftPersistenceRepository(db1);
      await repo1.init();

      // Lock satırını sıfırdan başlatmak için temizle (test izolasyonu)
      await repo1.releaseLock();

      // Ana isolate kilidi alır: satır yok → INSERT epoch=0 → UPDATE epoch=0 < staleThreshold(60s)
      final acquired1 = await repo1.tryAcquireLock(
        'isolate-1',
        const Duration(seconds: 60),
      );
      expect(acquired1, isTrue, reason: 'Ana isolate kilidi alabilmeli');

      // Heartbeat güncelle: acquiredAt = now → kilit stale değil
      await repo1.updateHeartbeat('isolate-1', DateTime.now());

      // 100 ms bekle: DB yazımının tamamlandığından emin ol
      await Future<void>.delayed(const Duration(milliseconds: 100));

      // İkinci isolate aynı kilidi almaya çalışır (threshold: 60 sn → lock stale değil)
      final receivePort = ReceivePort();
      await Isolate.spawn(
        _lockContestIsolate,
        [dbPath, receivePort.sendPort],
      );
      final bool acquired2 = await receivePort.first as bool;

      // İkinci isolate aktif kilit varken false almalı
      expect(
        acquired2,
        isFalse,
        reason:
            'İkinci isolate aktif kilit varken kilidi alamamalı (SQLite tek yazar garantisi)',
      );

      await repo1.dispose();
      await db1.close();
      receivePort.close();
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );

  // ── Test #12-D: recoverStuckUploads cross-isolate crash recovery ───────────
  test(
    '#12-D crash recovery: uploading → pending isolate sınırını aşar',
    () async {
      // İzolate 1: bir görevi uploading durumuna çeker ve kapanır (crash sim.)
      final db1 = openWalDb(dbPath);
      final repo1 = DriftPersistenceRepository(db1);
      await repo1.init();

      final seq = await repo1.getNextSequenceNumber();
      final task = await repo1.enqueue(
        taskId: 'crash-task',
        filePath: '/tmp/crash.jpg',
        sequenceNumber: seq,
      );
      await repo1.markUploading(task.taskId);

      // Bağlantıyı kapat (crash simülasyonu — lock serbest bırakılmadan)
      await db1.close();

      // İzolate 2 (ya da yeniden açılan uygulama): init() crash recovery çalıştırır
      final db2 = openWalDb(dbPath);
      final repo2 = DriftPersistenceRepository(db2);
      await repo2.init(); // recoverStuckUploads burada çalışır

      final recovered = await repo2.getNextPending(DateTime.now());
      expect(
        recovered,
        isNotNull,
        reason: 'Crash sonrası uploading görev pending\'e dönmeli',
      );
      expect(
        recovered!.taskId,
        equals('crash-task'),
        reason: 'Kurtarılan görev doğru taskId\'ye sahip olmalı',
      );
      expect(
        recovered.status,
        equals(UploadStatus.pending),
        reason: 'Kurtarılan görev pending durumunda olmalı',
      );

      await repo2.dispose();
      await db2.close();
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );
}
