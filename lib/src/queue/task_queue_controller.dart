import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:get/get.dart';

import 'task_queue_service.dart';

/// وسيط GetX يعبّي إحصاءات الطابور في [Rx] لمراقبتها مباشرة في الواجهات.
///
/// عرض رسائل المستخدم (snackbar ونحوه) مسؤولية التطبيق المستهلك عبر
/// الاستماع لأحداث [TaskQueueService.events].
class TaskQueueController extends GetxController {
  TaskQueueController({TaskQueueService? service})
      : _queueService = service ?? _findRegisteredService();

  static TaskQueueService _findRegisteredService() {
    if (Get.isRegistered<TaskQueueService>()) {
      return Get.find<TaskQueueService>();
    }
    throw StateError(
      'TaskQueueService غير مسجّل في GetX.\n'
      'سجّله أولاً: Get.put(service, permanent: true)\n'
      'أو مرّره مباشرة: TaskQueueController(service: service)',
    );
  }

  /// وصول شائع: يعيد المثيل المسجّل أو ينشئه مسجّلًا دائمًا.
  static TaskQueueController get instance =>
      Get.isRegistered<TaskQueueController>()
          ? Get.find<TaskQueueController>()
          : Get.put<TaskQueueController>(
              TaskQueueController(),
              permanent: true,
            );

  final TaskQueueService _queueService;
  StreamSubscription<QueueEvent>? _subscription;

  /// عدد المهام المعلّقة في الطابور (تراها Obx).
  final RxInt pendingCount = 0.obs;

  /// عدد المهام الفاشلة نهائيًا.
  final RxInt failedCount = 0.obs;

  /// هل حلقة التنفيذ تعمل الآن؟
  final RxBool isDraining = false.obs;

  /// إعادة جدولة مهمة فاشلة (انظر [TaskQueueService.retryTask]).
  Future<bool> retryTask(String id) async {
    final result = await _queueService.retryTask(id);
    _resync();
    return result;
  }

  /// حذف كل المهام الفاشلة (انظر [TaskQueueService.clearFailed]).
  Future<int> clearFailed() async {
    final removed = await _queueService.clearFailed();
    _resync();
    return removed;
  }

  @override
  void onInit() {
    super.onInit();
    _resync();
    _subscription = _queueService.events.listen(
      (_) => _resync(),
      onError: (Object error) =>
          debugPrint('TaskQueueController: خطأ في بث الطابور: $error'),
    );
  }

  /// مزامنة القيم التفاعلية من حالة الخدمة بعد كل حدث أو استدعاء تحكم.
  void _resync() {
    pendingCount.value = _queueService.pendingCount;
    failedCount.value = _queueService.failedCount;
    isDraining.value = _queueService.isDraining;
  }

  @override
  void onClose() {
    _subscription?.cancel();
    super.onClose();
  }
}
