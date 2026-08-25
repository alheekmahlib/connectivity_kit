import 'package:connectivity_kit/connectivity_kit.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import 'helpers/fakes.dart';

void main() {
  setUp(() {
    Get.testMode = true;
  });

  tearDown(() async {
    Get.reset();
  });

  test('إنشاء الوسيط بلا خدمة مسجّلة يرمي StateError برسالة واضحة', () {
    expect(() => ConnectionController(), throwsStateError);
  });

  test('الوسيط يتبع حالة الخدمة ويحدّث isOnline/isCellular', () async {
    final source = FakeConnectivitySource()
      ..current = const [ConnectivityResult.wifi];
    final service = ConnectionService(
      connectivitySource: source,
      options: const ConnectionOptions(
        disconnectDebounce: Duration(milliseconds: 40),
      ),
    );
    await service.init();
    Get.put(service, permanent: true);

    final controller = Get.put(ConnectionController(service: service));
    expect(controller.connectionStatus.value, ConnectivityStatus.wifi);
    expect(controller.isOnline, isTrue);
    expect(controller.isCellular, isFalse);

    source.emit(const [ConnectivityResult.mobile]);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(controller.connectionStatus.value, ConnectivityStatus.cellular);
    expect(controller.isCellular, isTrue);

    source.emit(const [ConnectivityResult.none]);
    await Future<void>.delayed(const Duration(milliseconds: 120));
    expect(controller.isOnline, isFalse);
    expect(controller.connectionStatus.value, ConnectivityStatus.offline);

    Get.delete<ConnectionController>(force: true);
    await service.dispose();
    await source.close();
  });

  test('instance ينشئ الوسيط تلقائيًا متى سُجّلت الخدمة', () async {
    final source = FakeConnectivitySource()
      ..current = const [ConnectivityResult.mobile];
    final service = ConnectionService(connectivitySource: source);
    await service.init();
    Get.put(service, permanent: true);

    final controller = ConnectionController.instance;
    expect(Get.isRegistered<ConnectionController>(), isTrue);
    expect(controller.connectionStatus.value, ConnectivityStatus.cellular);
    expect(controller.isCellular, isTrue);

    Get.delete<ConnectionController>(force: true);
    await service.dispose();
    await source.close();
  });
}
