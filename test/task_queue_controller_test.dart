import 'package:connectivity_kit/connectivity_kit.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import 'helpers/fakes.dart';
import 'task_queue_service_test.dart' show until;

void main() {
  setUp(() {
    Get.testMode = true;
  });

  tearDown(() async {
    Get.reset();
  });

  test('إنشاء الوسيط بلا خدمة مسجّلة يرمي StateError', () {
    expect(() => TaskQueueController(), throwsStateError);
  });

  test('الوسيط ينعكس عليه تقدّم الطابور في قيم Rx', () async {
    final source = FakeConnectivitySource()
      ..current = const [ConnectivityResult.none];
    final connection = ConnectionService(
      connectivitySource: source,
      options: const ConnectionOptions(disconnectDebounce: Duration.zero),
    );
    await connection.init();
    final store = FakeQueueStore();
    final queue = TaskQueueService(
      connectionService: connection,
      store: store,
      options: const TaskQueueOptions(
        maxAttempts: 2,
        initialRetryDelay: Duration(milliseconds: 20),
      ),
    );
    queue.registerHandler('send_note', (_) async {});
    await queue.init();
    Get.put(queue, permanent: true);

    final controller = Get.put(TaskQueueController(service: queue));
    expect(controller.pendingCount.value, 0);

    await queue.enqueue(
      type: 'send_note',
      payload: {'body': 'نص'},
      groupId: 'note_1',
    );
    await until(() => controller.pendingCount.value == 1);

    source.emit(const [ConnectivityResult.wifi]);
    await until(() => controller.pendingCount.value == 0);
    expect(controller.isDraining.value, isFalse);

    Get.delete<TaskQueueController>(force: true);
    await queue.dispose();
    await connection.dispose();
    await source.close();
  });

  test('فشل نهائي يرفع failedCount ثم clearFailed يصفّرها', () async {
    final source = FakeConnectivitySource();
    final connection = ConnectionService(
      connectivitySource: source,
      options: const ConnectionOptions(disconnectDebounce: Duration.zero),
    );
    await connection.init();
    final queue = TaskQueueService(
      connectionService: connection,
      store: FakeQueueStore(),
      options: const TaskQueueOptions(
        maxAttempts: 1,
        initialRetryDelay: Duration(milliseconds: 10),
      ),
    );
    queue.registerHandler('fails', (_) async => throw Exception('خطأ'));
    await queue.init();
    Get.put(queue, permanent: true);

    final controller = TaskQueueController.instance;
    expect(Get.isRegistered<TaskQueueController>(), isTrue);

    await queue.enqueue(type: 'fails', payload: {});
    await until(() => controller.failedCount.value == 1);
    expect(controller.pendingCount.value, 0);

    expect(await controller.clearFailed(), 1);
    expect(controller.failedCount.value, 0);

    Get.delete<TaskQueueController>(force: true);
    await queue.dispose();
    await connection.dispose();
    await source.close();
  });
}
