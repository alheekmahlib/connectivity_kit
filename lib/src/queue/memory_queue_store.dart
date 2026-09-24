import 'queued_task.dart';
import 'queue_store.dart';

/// مخزن طابور في الذاكرة فقط: لا يكتب شيئًا على القرص ولا يبقى بعد نهاية
/// الجلسة.
///
/// هو مسار الهبوط حين يتعذّر إنشاء مخزن القرص الافتراضي — كفشل قناة
/// المنصة على بعض الأجهزة القديمة — فيستمر الطابور ضمن الجلسة بدل إجهاض
/// تهيئة التطبيق كله. يصلح أيضًا للحقن المباشر عند الرغبة في طابور
/// جلسية فقط دون أي أثر على القرص.
class MemoryQueueStore implements QueueStore {
  final List<QueuedTask> _tasks = [];

  @override
  Future<List<QueuedTask>> load() async => List.of(_tasks);

  @override
  Future<void> save(List<QueuedTask> tasks) async {
    _tasks
      ..clear()
      ..addAll(tasks);
  }
}
