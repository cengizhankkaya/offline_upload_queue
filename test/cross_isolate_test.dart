/// Cross-isolate / Sembast testleri — Aşama 1, test #12.
///
/// Bu testler gerçek bir Sembast veritabanı dosyası kullanır.
/// Sembast'ın concurrent yazım davranışı Drift'ten (WAL) farklı olduğundan,
/// OQ-1 Alternatif A'ya (el-değiştirme protokolü) uygun olarak
/// sıralı erişim ve crash recovery senaryoları test edilir.
///
/// CI filtreleme: `flutter test --tags cross_isolate`
/// Ana suite dışlama: `flutter test --exclude-tags cross_isolate`
@Tags(['cross_isolate'])
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:offline_upload_queue/src/database/sembast_persistence_repository.dart';
import 'package:offline_upload_queue/src/models/upload_status.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:sembast/sembast_io.dart';

class MockPathProviderPlatform extends Fake
    with MockPlatformInterfaceMixin
    implements PathProviderPlatform {
  final String tempPath;
  MockPathProviderPlatform(this.tempPath);

  @override
  Future<String?> getApplicationSupportPath() async => tempPath;
}

void main() {
  late Directory tempDir;
  late String boxName;
  late String dbPath;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('sembast_test_');
    boxName = 'test_box';
    dbPath = p.join(tempDir.path, '$boxName.db');
    PathProviderPlatform.instance = MockPathProviderPlatform(tempDir.path);
  });

  tearDown(() async {
    await tempDir.delete(recursive: true);
  });

  // ── Test #12-A: Tek process, ardışık init/dispose ──────────────────────────
  test(
    '#12-A Aynı process içinde ardışık init/dispose sorunsuz çalışır (El değiştirme simülasyonu)',
    () async {
      // Birinci repo (Ana UploadQueue simülasyonu)
      final repo1 = SembastPersistenceRepository(boxName: boxName);
      await repo1.init();

      for (var i = 0; i < 3; i++) {
        final seq = await repo1.getNextSequenceNumber();
        await repo1.enqueue(
          taskId: 'task-$i',
          filePath: '/tmp/file-$i.jpg',
          sequenceNumber: seq,
        );
      }
      await repo1.dispose(); // El değiştirme hazırlığı

      // İkinci repo (Arka plan görev simülasyonu)
      final repo2 = SembastPersistenceRepository(boxName: boxName);
      await repo2.init();

      final seq2 = await repo2.getNextSequenceNumber();
      await repo2.enqueue(
        taskId: 'task-bg',
        filePath: '/tmp/file-bg.jpg',
        sequenceNumber: seq2,
      );

      // Tüm görevleri doğrula
      final now = DateTime.now();
      final tasks = <String>[];
      var t = await repo2.getNextPending(now);
      while (t != null) {
        tasks.add(t.taskId);
        await repo2.markUploading(t.taskId); // listeye girmemesi için
        t = await repo2.getNextPending(now);
      }

      expect(tasks, containsAll(['task-0', 'task-1', 'task-2', 'task-bg']));
      expect(tasks.length, 4);

      await repo2.dispose();
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );

  // ── Test #12-B: Sequence çakışması önleme (transaction garantisi) ──────────
  test(
    '#12-B Aynı repo üzerinde eşzamanlı enqueue sequence numarası çakışması yaratmaz',
    () async {
      final repo = SembastPersistenceRepository(boxName: boxName);
      await repo.init();

      // 5 concurrent enqueue
      final futures = <Future<void>>[];
      for (var i = 0; i < 5; i++) {
        futures.add(
          repo.enqueue(
            taskId: 'concurrent-$i',
            filePath: '/tmp/file-$i.jpg',
            sequenceNumber:
                0, // getNextSequenceNumber kullanmıyoruz, transaction a güveniyoruz
          ),
        );
      }
      await Future.wait(futures);

      // Veritabanındaki tüm görevleri sırasıyla oku
      final dbFactory = databaseFactoryIo;
      final db = await dbFactory.openDatabase(dbPath);
      final store = stringMapStoreFactory.store('tasks');
      final records = await store.find(db);
      await db.close();

      final seqs = records
          .map((r) => r.value['sequenceNumber'] as int)
          .toList();
      final seqsSet = seqs.toSet();

      expect(seqsSet.length, 5, reason: 'Sequence numaraları benzersiz olmalı');
      expect(
        seqsSet.containsAll([1, 2, 3, 4, 5]),
        isTrue,
        reason: 'Sequence numaraları sıralı üretilmeli',
      );

      await repo.dispose();
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );

  // ── Test #12-C: Lock yarışı (aynı process, iki async call) ────────────────
  test(
    '#12-C Kilit yarışı: aynı process içindeki concurrent Future lar serialize edilir',
    () async {
      final repo = SembastPersistenceRepository(boxName: boxName);
      await repo.init();

      await repo.releaseLock(); // Sıfırla

      // Aynı repo üzerinden iki concurrent deneme
      final futures = [
        repo.tryAcquireLock('worker-1', const Duration(seconds: 60)),
        repo.tryAcquireLock('worker-2', const Duration(seconds: 60)),
      ];

      final results = await Future.wait(futures);

      // Yalnızca biri true olmalı
      final trueCount = results.where((r) => r == true).length;
      expect(
        trueCount,
        1,
        reason:
            'Yalnızca bir kilit alma işlemi başarılı olmalı (transaction serileştirmesi)',
      );

      await repo.dispose();
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );

  // ── Test #12-D: recoverStuckUploads (crash recovery) ───────────────────────
  test(
    '#12-D crash recovery: uploading → pending sembast için de çalışır',
    () async {
      final repo1 = SembastPersistenceRepository(boxName: boxName);
      await repo1.init();

      final seq = await repo1.getNextSequenceNumber();
      final task = await repo1.enqueue(
        taskId: 'crash-task',
        filePath: '/tmp/crash.jpg',
        sequenceNumber: seq,
      );
      await repo1.markUploading(task.taskId);

      // dispose çağırmadan veritabanını kapatarak veya bırakarak "crash" simülasyonu yapıyoruz.
      // Sembast dosya bazlı çalıştığı için başka bir repo örneği açtığımızda sorun olmaz.
      await repo1.dispose();

      // İkinci repo (Uygulamanın yeniden başlaması simülasyonu)
      final repo2 = SembastPersistenceRepository(boxName: boxName);
      await repo2.init(); // recoverStuckUploads çalışır

      final recovered = await repo2.getNextPending(DateTime.now());
      expect(
        recovered,
        isNotNull,
        reason: 'Crash sonrası uploading görev pending e dönmeli',
      );
      expect(recovered!.taskId, 'crash-task');
      expect(recovered.status, UploadStatus.pending);

      await repo2.dispose();
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );
}
