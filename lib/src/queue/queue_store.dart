import 'queued_task.dart';

/// واجهة تخزين الطابور على القرص — قابلة للحقن لمن يريد مخزنًا مخصصًا
/// (مشفّرًا أو قاعدة بيانات) بدل التنفيذ الافتراضي.
abstract interface class QueueStore {
  /// تحميل المهام المحفوظة؛ القراءة التالفة أو الغائبة تُعيد قائمة فارغة.
  Future<List<QueuedTask>> load();

  /// حفظ لقطة الطابور كاملة (المعلّقة والفاشلة) استبدالًا لأي سابق.
  Future<void> save(List<QueuedTask> tasks);
}
