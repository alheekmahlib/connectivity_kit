import 'dart:async';

import 'package:connectivity_kit/connectivity_kit.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

/// مصدر اتصال مزيف يقود الأحداث يدويًا بدل قنوات المنصة.
class FakeConnectivitySource implements ConnectivitySource {
  final StreamController<List<ConnectivityResult>> _controller =
      StreamController<List<ConnectivityResult>>.broadcast();

  List<ConnectivityResult> current = const [ConnectivityResult.wifi];

  /// تأخير checkConnectivity لمحاكاة السباق مع أحداث الـ stream.
  Duration checkDelay = Duration.zero;

  @override
  Stream<List<ConnectivityResult>> get onConnectivityChanged =>
      _controller.stream;

  @override
  Future<List<ConnectivityResult>> checkConnectivity() async {
    if (checkDelay > Duration.zero) {
      await Future<void>.delayed(checkDelay);
    }
    return current;
  }

  void emit(List<ConnectivityResult> results) {
    current = results;
    _controller.add(results);
  }

  Future<void> close() => _controller.close();
}

/// فاحص وصول مزيف بعدد استدعاءات وتأخير قابلين للضبط.
class FakeReachabilityProbe implements ReachabilityProbe {
  FakeReachabilityProbe({this.reachable = true, this.delay = Duration.zero});

  bool reachable;
  Duration delay;
  int callCount = 0;

  @override
  Future<bool> isReachable() async {
    callCount++;
    if (delay > Duration.zero) {
      await Future<void>.delayed(delay);
    }
    return reachable;
  }
}

/// مخزن طابور في الذاكرة مع خيار محاكاة فشل الحفظ.
class FakeQueueStore implements QueueStore {
  FakeQueueStore({this.failOnSave = false});

  /// عند true يرمي save استثناءً لمحاكاة خلل التخزين.
  bool failOnSave;

  /// آخر لقطة ناجحة حفظها المخزن؛ تستخدم أيضًا لتحميل حالة سابقة.
  List<QueuedTask> saved = [];

  int saveCount = 0;

  @override
  Future<List<QueuedTask>> load() async => List.of(saved);

  @override
  Future<void> save(List<QueuedTask> tasks) async {
    saveCount++;
    if (failOnSave) throw Exception('fake store failure');
    saved = List.of(tasks);
  }
}
