import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart' as path_provider;
import 'package:offline_upload_queue_example/main.dart' as app;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Network Chaos Test: 429 and Timeout', (
    WidgetTester tester,
  ) async {
    app.main();

    // Wait for the FutureBuilder to complete by looking for the QueueScreen
    bool initialized = false;
    for (int i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 500));
      if (find
          .text('Kuyruk başlatılıyor... (Kilit bekleniyor olabilir)')
          .evaluate()
          .isEmpty) {
        initialized = true;
        break;
      }
    }
    expect(initialized, isTrue, reason: 'App failed to initialize in time');

    final dir = await path_provider.getApplicationDocumentsDirectory();

    // --- Test 1: 429 Too Many Requests ---
    final file429 = File('${dir.path}/test_429.txt');
    await file429.writeAsString('429 test content');

    final initialSummary = await app.uploadQueue.watchSummary().first;
    final initialFailed = initialSummary.failed;

    await app.uploadQueue.enqueue(
      filePath: file429.path,
      metadata: {'demo': '429_case'},
    );

    // It should quickly fail because 429 is immediate
    bool failedObserved = false;
    for (int i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 500));
      final summary = await app.uploadQueue.watchSummary().first;
      if (summary.failed > initialFailed) {
        failedObserved = true;
        break;
      }
    }
    expect(
      failedObserved,
      isTrue,
      reason: 'Task should transition to failed on 429 response',
    );

    // --- Test 2: Network Timeout ---
    final fileTimeout = File('${dir.path}/test_timeout.txt');
    await fileTimeout.writeAsString('timeout test content');
    final beforeTimeoutFailed =
        (await app.uploadQueue.watchSummary().first).failed;

    await app.uploadQueue.enqueue(
      filePath: fileTimeout.path,
      metadata: {'demo': 'timeout_case'},
    );

    // Timeout takes 5 seconds due to the HTTP client timeout we added
    bool timeoutFailedObserved = false;
    for (int i = 0; i < 20; i++) {
      // wait up to 10 seconds
      await tester.pump(const Duration(milliseconds: 500));
      final summary = await app.uploadQueue.watchSummary().first;
      if (summary.failed > beforeTimeoutFailed) {
        timeoutFailedObserved = true;
        break;
      }
    }
    expect(
      timeoutFailedObserved,
      isTrue,
      reason: 'Task should transition to failed on timeout',
    );
  });
}
