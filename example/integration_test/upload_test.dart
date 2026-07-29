import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart' as path_provider;
import 'package:offline_upload_queue_example/main.dart' as app;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('End-to-end upload lifecycle test', (WidgetTester tester) async {
    // 1. Build the app
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

    // 2. Initial state verification
    final initialSummary = await app.uploadQueue.watchSummary().first;
    final initialCompleted = initialSummary.completed;

    // 3. Create a dummy file for testing
    final dir = await path_provider.getApplicationDocumentsDirectory();
    final file = File('${dir.path}/test_upload.txt');
    await file.writeAsString('Integration test file content');

    // 4. Enqueue the file
    final taskId = await app.uploadQueue.enqueue(
      filePath: file.path,
      metadata: {'demo': 'integration_test'},
    );

    expect(taskId, isNotNull);
    expect(taskId.isNotEmpty, isTrue);

    // 5. Verify it transitions
    // The MockUploadAdapter takes about 2 seconds to complete.
    // We poll the summary for completion.
    bool wasUploading = false;
    bool completed = false;

    for (int i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 500));

      final summary = await app.uploadQueue.watchSummary().first;

      if (summary.uploading > 0) {
        wasUploading = true;
      }

      if (summary.completed > initialCompleted) {
        completed = true;
        break;
      }
    }

    expect(
      wasUploading,
      isTrue,
      reason: 'Task should have entered uploading state',
    );
    expect(
      completed,
      isTrue,
      reason: 'Task should have completed successfully',
    );
  });
}
