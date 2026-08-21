import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:get/get.dart';

import 'connection_service.dart';
import 'connectivity_status.dart';

/// وسيط GetX يعبّي حالة الاتصال في [Rx] لمراقبتها مباشرة في الواجهات.
///
/// عرض رسائل المستخدم (snackbar ونحوه) مسؤولية التطبيق المستهلك عبر
/// الاستماع لـ [connectionStatus].
class ConnectionController extends GetxController {
  ConnectionController({ConnectionService? service})
      : _connectivityService = service ?? _findRegisteredService();

  static ConnectionService _findRegisteredService() {
    if (Get.isRegistered<ConnectionService>()) {
      return Get.find<ConnectionService>();
    }
    throw StateError(
      'InternetConnectionService غير مسجّل في GetX.\n'
      'سجّله أولاً: Get.put(service, permanent: true)\n'
      'أو مرّره مباشرة: InternetConnectionController(service: service)',
    );
  }

  /// وصول شائع: يعيد المثيل المسجّل أو ينشئه مسجّلًا دائمًا.
  static ConnectionController get instance =>
      Get.isRegistered<ConnectionController>()
          ? Get.find<ConnectionController>()
          : Get.put<ConnectionController>(
              ConnectionController(),
              permanent: true,
            );

  final ConnectionService _connectivityService;
  StreamSubscription<ConnectivityStatus>? _subscription;

  /// الحالة الحالية للمراقبة في الواجهات عبر Obx.
  final Rx<ConnectivityStatus> connectionStatus =
      ConnectivityStatus.offline.obs;

  /// هل يوجد اتصال متاح؟
  bool get isOnline => connectionStatus.value.isOnline;

  /// هل الاتصال عبر بيانات الجوال؟
  bool get isCellular => connectionStatus.value.isCellular;

  @override
  void onInit() {
    super.onInit();
    connectionStatus.value = _connectivityService.currentStatus;
    _subscription = _connectivityService.connectionStream.listen((status) {
      debugPrint('Connectivity status changed: $status');
      connectionStatus.value = status;
    });
  }

  @override
  void onClose() {
    _subscription?.cancel();
    super.onClose();
  }
}
