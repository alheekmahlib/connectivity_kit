import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:get_storage/get_storage.dart';

import 'queued_task.dart';
import 'queue_store.dart';

/// تنفيذ [QueueStore] الافتراضي: يخزّن الطابور كاملًا كسلسلة JSON
/// بمفتاح واحد داخل حاوية `get_storage` مخصّصة للحزمة.
///
/// هذا التخزين غير مشفّر على معظم المنصات؛ للتطبيقات ذات الحمولات
/// الحساسة، حقّن مخزنًا مخصصًا يحقق [QueueStore] (مثل تغليف
/// flutter_secure_storage أو قاعدة بيانات مشفّرة).
class GetStorageQueueStore implements QueueStore {
  GetStorageQueueStore(GetStorage box) : _box = box;

  /// ينشئ المخزن بعد تهيئة حاوية get_storage المخصّصة للحزمة.
  ///
  /// الحاوية المعزولة تُبقي بيانات الطابور بمنأى عن الحاوية
  /// الافتراضية للتطبيق (تنجو من `erase()` عند تسجيل الخروج مثلًا).
  static Future<GetStorageQueueStore> create() async {
    await GetStorage.init(_container);
    return GetStorageQueueStore(GetStorage(_container));
  }

  /// اسم حاوية التخزين المعزولة عن حاويات التطبيق المستضيف.
  static const String _container = 'connectivity_kit';

  /// مفتاح التخزين؛ اللاحقة v1 تمهّد لترقية الصيغة مستقبلًا.
  static const String _key = 'connectivity_kit.task_queue.v1';

  final GetStorage _box;

  @override
  Future<List<QueuedTask>> load() async {
    final raw = _box.read<dynamic>(_key);
    if (raw == null) return [];
    if (raw is! String || raw.isEmpty) return [];
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      final tasks = decoded['tasks'] as List<dynamic>? ?? const <dynamic>[];
      return tasks
          .whereType<Map<String, dynamic>>()
          .map(QueuedTask.fromJson)
          .toList();
    } on Object catch (e) {
      debugPrint('TaskQueueStore: تعذّر تحليل الطابور المحفوظ — يُهمل: $e');
      return [];
    }
  }

  @override
  Future<void> save(List<QueuedTask> tasks) async {
    await _box.write(
      _key,
      jsonEncode(<String, dynamic>{
        'version': 1,
        'tasks': tasks.map((task) => task.toJson()).toList(),
      }),
    );
  }
}
