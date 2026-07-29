import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:offline_upload_queue/offline_upload_queue.dart';
import 'package:sembast/sembast_io.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class DummyAdapter implements UploadAdapter {
  @override
  Future<UploadResult> uploadFile({
    required String taskId,
    required String filePath,
    required Map<String, dynamic> metadata,
    required String checksum,
    void Function(int sent, int total)? onProgress,
    UploadCancelToken? cancelToken,
  }) async {
    return const UploadResult.success();
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Lock stealing after crash (staleLockThreshold)', (
    WidgetTester tester,
  ) async {
    final boxName = 'lock_test_queue';

    // 1. Manually write a stale lock to the database (simulating a crashed process)
    final dbFolder = await getApplicationSupportDirectory();
    final dbPath = p.join(dbFolder.path, '$boxName.db');

    // Delete old db if exists to start fresh
    await databaseFactoryIo.deleteDatabase(dbPath);

    final db = await databaseFactoryIo.openDatabase(dbPath);
    final lockStore = stringMapStoreFactory.store('worker_lock');

    // Write a lock that is 10 seconds old
    await lockStore.record('lock').put(db, {
      'acquiredAt': DateTime.now()
          .subtract(const Duration(seconds: 10))
          .toIso8601String(),
      'ownerId': 'crashed_process',
    });
    await db.close();

    // 2. Initialize Queue B
    // We set staleLockThreshold to 5 seconds. Since the lock is 10 seconds old,
    // Queue B should steal it immediately (or within a polling cycle).
    // Note: heartbeatInterval is 1s, staleLockThreshold is 5s (must be >= 3s)
    final queueB = UploadQueue(
      boxName: boxName,
      adapter: DummyAdapter(),
      advanced: UploadQueueAdvancedOptions(
        staleLockThreshold: const Duration(seconds: 5),
        heartbeatInterval: const Duration(seconds: 1),
      ),
    );

    // This init will see the stale lock and steal it.
    await queueB.init();

    // Now Queue B should be functional
    final summary = await queueB.watchSummary().first;
    expect(summary, isNotNull);

    // Clean up
    await queueB.dispose();
  });
}
