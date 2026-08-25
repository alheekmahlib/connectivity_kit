import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'queued_task.dart';
import 'queue_store.dart';

/// تنفيذ [QueueStore] الافتراضي: يخزّن الطابور كاملًا كسلسلة JSON
/// بمفتاح واحد داخل `shared_preferences`.
///
/// هذا التخزين غير مشفّر على معظم المنصات؛ للتطبيقات ذات الحمولات
/// الحساسة، حقّن مخزنًا مخصصًا يحقق [QueueStore] (مثل تغليف
/// flutter_secure_storage أو قاعدة بيانات مشفّرة).
class SharedPreferencesQueueStore implements QueueStore {
  SharedPreferencesQueueStore(SharedPreferences prefs) : _prefs = prefs;

  /// ينشئ المخزن بالنسخة الافتراضية من shared_preferences.
  static Future<SharedPreferencesQueueStore> create() async =>
      SharedPreferencesQueueStore(await SharedPreferences.getInstance());

  /// مفتاح التخزين؛ اللاحقة v1 تمهّد لترقية الصيغة مستقبلًا.
  static const String _key = 'connectivity_kit.task_queue.v1';

  final SharedPreferences _prefs;

  @override
  Future<List<QueuedTask>> load() async {
    final raw = _prefs.getString(_key);
    if (raw == null || raw.isEmpty) return [];
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
    await _prefs.setString(
      _key,
      jsonEncode(<String, dynamic>{
        'version': 1,
        'tasks': tasks.map((task) => task.toJson()).toList(),
      }),
    );
  }
}
