import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:offline_upload_queue/offline_upload_queue.dart';
import 'package:path_provider/path_provider.dart' as path_provider;
import 'package:path/path.dart' as p;

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

  testWidgets('Security: Database Encryption Test', (
    WidgetTester tester,
  ) async {
    final dir = await path_provider.getApplicationSupportDirectory();
    final docsDir = await path_provider.getApplicationDocumentsDirectory();
    final dummyFile = File('${docsDir.path}/dummy.txt');
    if (!await dummyFile.exists()) await dummyFile.writeAsString('test');

    final secretData = 'SUPER_SECRET_USER_DATA_123';

    // 1. WITHOUT ENCRYPTION
    final plainQueue = UploadQueue(
      boxName: 'plain_queue',
      adapter: DummyAdapter(),
    );
    await plainQueue.init();
    plainQueue.pause();
    await plainQueue.enqueue(
      filePath: dummyFile.path,
      metadata: {'sensitive': secretData},
    );
    await Future.delayed(
      const Duration(milliseconds: 500),
    ); // wait for db write
    await plainQueue.dispose();

    final plainDbPath = p.join(dir.path, 'plain_queue.db');
    final plainDbContent = await File(
      plainDbPath,
    ).readAsString(encoding: const SystemEncoding());
    // In plaintext DB, the metadata should be visible
    expect(
      plainDbContent.contains(secretData),
      isTrue,
      reason: 'Plaintext DB should contain the secret data',
    );

    // 2. WITH ENCRYPTION
    final secureQueue = UploadQueue(
      boxName: 'secure_queue',
      adapter: DummyAdapter(),
      encryptionKey: 'my_strong_password_123',
    );
    await secureQueue.init();
    secureQueue.pause();
    await secureQueue.enqueue(
      filePath: dummyFile.path,
      metadata: {'sensitive': secretData},
    );
    await Future.delayed(
      const Duration(milliseconds: 500),
    ); // wait for db write
    await secureQueue.dispose();

    final secureDbPath = p.join(dir.path, 'secure_queue.db');
    // Using readAsBytes since encrypted file might not be valid UTF-8
    final secureDbBytes = await File(secureDbPath).readAsBytes();
    final secureDbString = String.fromCharCodes(secureDbBytes);

    // In encrypted DB, the metadata should NOT be visible
    expect(
      secureDbString.contains(secretData),
      isFalse,
      reason: 'Encrypted DB must NOT contain the secret data in plaintext',
    );
  });
}
