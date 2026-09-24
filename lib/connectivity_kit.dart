/// حزمة خفيفة لمراقبة الاتصال بالإنترنت في تطبيقات Flutter:
/// خدمة نقية تبثّ حالة الاتصال مع debounce للانقطاع، ووسيط GetX
/// جاهز للواجهات، وخيار فحص وصول فعلي للإنترنت (reachability)،
/// وطابور مهام محفوظ ينفّذ الأعمال التي تحتاج إنترنت عند عودة الاتصال.
library;

export 'src/connection_controller.dart';
export 'src/connection_service.dart';
export 'src/connectivity_source.dart';
export 'src/connectivity_status.dart';
export 'src/queue/memory_queue_store.dart';
export 'src/queue/queued_task.dart';
export 'src/queue/queue_store.dart';
export 'src/queue/get_storage_queue_store.dart';
export 'src/queue/task_handler.dart';
export 'src/queue/task_queue_controller.dart';
export 'src/queue/task_queue_service.dart';
export 'src/reachability/reachability_probe.dart';
