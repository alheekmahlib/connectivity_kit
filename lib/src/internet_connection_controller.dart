import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:get/get.dart';

import 'connectivity_status.dart';
import 'internet_connection_service.dart';

/// وسيط GetX يعبّي حالة الاتصال في [Rx] لمراقبتها مباشرة في الواجهات.
///
/// عرض رسائل المستخدم (snackbar ونحوه) مسؤولية التطبيق المستهلك عبر
/// الاستماع لـ [connectionStatus].
class InternetConnectionController extends GetxController {
  InternetConnectionController({InternetConnectionService? service})
    : _connectivityService = service ?? _findRegisteredService();

  static InternetConnectionService _findRegisteredService() {
    if (Get.isRegistered<InternetConnectionService>()) {
      return Get.find<InternetConnectionService>();
    }
    throw StateError(
      'InternetConnectionService غير مسجّل في GetX.\n'
      'سجّله أولاً: Get.put(service, permanent: true)\n'
      'أو مرّره مباشرة: InternetConnectionController(service: service)',
    );
  }

  /// وصول شائع: يعيد المثيل المسجّل أو ينشئه مسجّلًا دائمًا.
  static InternetConnectionController get instance =>
      Get.isRegistered<InternetConnectionController>()
      ? Get.find<InternetConnectionController>()
      : Get.put<InternetConnectionController>(
          InternetConnectionController(),
          permanent: true,
        );

  final InternetConnectionService _connectivityService;
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
