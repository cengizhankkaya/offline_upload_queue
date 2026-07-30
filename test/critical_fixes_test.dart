import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:offline_upload_queue/offline_upload_queue.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'helpers/controllable_upload_adapter.dart';

class MockPathProviderPlatform extends Fake
    with MockPlatformInterfaceMixin
    implements PathProviderPlatform {
  final String tempPath;
  MockPathProviderPlatform(this.tempPath);

  @override
  Future<String?> getApplicationSupportPath() async => tempPath;
}

class ProgressAwareAdapter implements UploadAdapter {
  bool sawProgressCallback = false;

  @override
  Future<UploadResult> uploadFile({
    required String taskId,
    required String filePath,
    required Map<String, dynamic> metadata,
    required String checksum,
    void Function(int sent, int total)? onProgress,
    UploadCancelToken? cancelToken,
  }) async {
    if (onProgress != null) {
      sawProgressCallback = true;
      onProgress(50, 100);
      onProgress(100, 100);
    }
    await Future<void>.delayed(const Duration(milliseconds: 20));
    return const UploadResult.success();
  }
}

class WifiMonitor implements ConnectivityMonitor {
  @override
  Future<ConnectivityStatus> checkStatus() async => ConnectivityStatus.wifi;

  @override
  Stream<ConnectivityStatus> get statusStream => const Stream.empty();
}

class FailureReturningAdapter implements UploadAdapter {
  @override
  Future<UploadResult> uploadFile({
    required String taskId,
    required String filePath,
    required Map<String, dynamic> metadata,
    required String checksum,
    void Function(int sent, int total)? onProgress,
    UploadCancelToken? cancelToken,
  }) async {
    // RestUploadAdapter sözleşmesi: iptalde exception değil failure.
    final completer = Completer<UploadResult>();
    cancelToken?.registerOnCancel(() {
      if (!completer.isCompleted) {
        completer.complete(const UploadResult.failure(FailureType.unknown));
      }
    });
    return completer.future;
  }
}

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('critical_fixes_');
    PathProviderPlatform.instance = MockPathProviderPlatform(tempDir.path);
  });

  tearDown(() async {
    await tempDir.delete(recursive: true);
  });

  test('dispose() sonrası init() tekrar çalışır', () async {
    final queue = UploadQueue(
      adapter: ProgressAwareAdapter(),
      boxName: 'reinit',
      connectivityMonitor: WifiMonitor(),
      copyToSandbox: false,
    );

    await queue.init();
    await queue.dispose();
    await queue.init();
    expect(queue.isInitialized, isTrue);
    await queue.dispose();
  });

  test('watchProgress dinleyici varken onProgress bağlanır', () async {
    final adapter = ProgressAwareAdapter();
    final queue = UploadQueue(
      adapter: adapter,
      boxName: 'progress',
      connectivityMonitor: WifiMonitor(),
      copyToSandbox: false,
    );
    await queue.init();
    addTearDown(queue.dispose);

    final file = File('${tempDir.path}/p.txt')..writeAsStringSync('hello');
    final taskId = await queue.enqueue(filePath: file.path);

    final received = <double>[];
    final sub = queue.watchProgress(taskId).listen(received.add);

    await queue
        .watchTasks(statuses: {UploadStatus.completed})
        .firstWhere((tasks) => tasks.any((t) => t.taskId == taskId))
        .timeout(const Duration(seconds: 5));

    await sub.cancel();
    expect(adapter.sawProgressCallback, isTrue);
    expect(received, isNotEmpty);
  });

  test('cancel() failure dönüşünde görev cancelled kalır', () async {
    final adapter = ControllableUploadAdapter(pauseOnCall: true);
    final queue = UploadQueue(
      adapter: adapter,
      boxName: 'cancel_fail',
      connectivityMonitor: WifiMonitor(),
      copyToSandbox: false,
    );
    await queue.init();
    addTearDown(queue.dispose);

    final file = File('${tempDir.path}/c.txt')..writeAsStringSync('x');
    final taskId = await queue.enqueue(filePath: file.path);

    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(adapter.isWaiting(taskId), isTrue);

    await queue.cancel(taskId);
    await Future<void>.delayed(const Duration(milliseconds: 100));

    final task = await queue.getTask(taskId);
    expect(task?.status, UploadStatus.cancelled);
  });

  test('BackgroundTaskRunner paylaşılan kuyruğu dispose etmez', () async {
    final queue = UploadQueue(
      adapter: ProgressAwareAdapter(),
      boxName: 'bg_shared',
      connectivityMonitor: WifiMonitor(),
      copyToSandbox: false,
    );
    await queue.init();
    addTearDown(queue.dispose);

    final hasPending = await BackgroundTaskRunner.run(
      queue,
      timeout: const Duration(milliseconds: 200),
    );
    expect(queue.isInitialized, isTrue);
    expect(hasPending, isFalse);
  });

  test('setBackgroundDeadline init öncesi saklanır', () async {
    final queue = UploadQueue(
      adapter: FailureReturningAdapter(),
      boxName: 'deadline',
      connectivityMonitor: WifiMonitor(),
      copyToSandbox: false,
    );
    final deadline = DateTime.now().add(const Duration(seconds: 20));
    queue.setBackgroundDeadline(deadline);
    await queue.init();
    expect(queue.isInitialized, isTrue);
    queue.setBackgroundDeadline(null);
    await queue.dispose();
  });
}
