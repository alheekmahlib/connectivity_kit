/// حزمة خفيفة لمراقبة الاتصال بالإنترنت في تطبيقات Flutter:
/// خدمة نقية تبثّ حالة الاتصال مع debounce للانقطاع، ووسيط GetX
/// جاهز للواجهات، وخيار فحص وصول فعلي للإنترنت (reachability).
library;

export 'src/connection_controller.dart';
export 'src/connection_service.dart';
export 'src/connectivity_source.dart';
export 'src/connectivity_status.dart';
export 'src/reachability/reachability_probe.dart';
