import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart' as path_provider;
import 'package:offline_upload_queue/offline_upload_queue.dart';

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
    // Fast processing
    await Future.delayed(const Duration(milliseconds: 10));
    return const UploadResult.success();
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Performance: Bulk Enqueue (1000 files)', (WidgetTester tester) async {
    final queue = UploadQueue(adapter: DummyAdapter(), boxName: 'perf_bulk');
    await queue.init();
    queue.pause(); // Pause to prevent processing during enqueue

    final dir = await path_provider.getApplicationDocumentsDirectory();
    final dummyFile = File('${dir.path}/perf_dummy.txt');
    await dummyFile.writeAsString('1234567890'); // 10 bytes

    final stopwatch = Stopwatch()..start();
    for (int i = 0; i < 1000; i++) {
      await queue.enqueue(filePath: dummyFile.path);
    }
    stopwatch.stop();

    // 1000 DB inserts + 1000 sandbox file copies should be reasonably fast
    expect(stopwatch.elapsedMilliseconds, lessThan(150000)); // Should be well within 150s on emulator

    final summary = await queue.watchSummary().first;
    expect(summary.pending, 1000);
    expect(summary.estimatedDiskUsageBytes, 1000 * 10); // Exactly 10000 bytes

    await queue.dispose();
  });

  testWidgets('Performance: Large File Processing (20MB)', (
    WidgetTester tester,
  ) async {
    final queue = UploadQueue(adapter: DummyAdapter(), boxName: 'perf_large');
    await queue.init();

    final dir = await path_provider.getApplicationDocumentsDirectory();
    final largeFile = File('${dir.path}/perf_large.dat');

    // Generate a 20MB file
    final bytes = List.filled(1024 * 1024, 0); // 1MB array
    final sink = largeFile.openWrite();
    for (int i = 0; i < 20; i++) {
      sink.add(bytes);
    }
    await sink.flush();
    await sink.close();

    final stopwatch = Stopwatch()..start();
    final taskId = await queue.enqueue(filePath: largeFile.path);
    stopwatch.stop();

    expect(taskId, isNotEmpty);
    // Even for 20MB, the enqueue (which copies to sandbox) should not freeze UI indefinitely
    expect(stopwatch.elapsedMilliseconds, lessThan(10000));

    await queue.dispose();
  });

  testWidgets('Performance: Memory Leak / Cycle Check (100 inits)', (
    WidgetTester tester,
  ) async {
    // Repeatedly init and dispose to ensure stream controllers and locks are freed
    for (int i = 0; i < 100; i++) {
      final q = UploadQueue(adapter: DummyAdapter(), boxName: 'perf_leak');
      await q.init();
      await q.dispose();
    }
    // If it didn't throw StateError (e.g. Stream already listened) or OutOfMemory, it passes
    expect(true, isTrue);
  });

  testWidgets('Performance: Concurrent Multiple Queues', (
    WidgetTester tester,
  ) async {
    final q1 = UploadQueue(adapter: DummyAdapter(), boxName: 'perf_q1');
    final q2 = UploadQueue(adapter: DummyAdapter(), boxName: 'perf_q2');
    final q3 = UploadQueue(adapter: DummyAdapter(), boxName: 'perf_q3');

    await Future.wait([q1.init(), q2.init(), q3.init()]);

    final dir = await path_provider.getApplicationDocumentsDirectory();
    final dummyFile = File('${dir.path}/perf_dummy.txt');
    if (!await dummyFile.exists()) await dummyFile.writeAsString('test');

    // Enqueue concurrently
    await Future.wait([
      q1.enqueue(filePath: dummyFile.path),
      q2.enqueue(filePath: dummyFile.path),
      q3.enqueue(filePath: dummyFile.path),
    ]);

    final s1 = await q1.watchSummary().first;
    final s2 = await q2.watchSummary().first;
    final s3 = await q3.watchSummary().first;

    expect(s1.activeCount > 0 || s1.completed > 0, isTrue);
    expect(s2.activeCount > 0 || s2.completed > 0, isTrue);
    expect(s3.activeCount > 0 || s3.completed > 0, isTrue);

    await Future.wait([q1.dispose(), q2.dispose(), q3.dispose()]);
  });
}
