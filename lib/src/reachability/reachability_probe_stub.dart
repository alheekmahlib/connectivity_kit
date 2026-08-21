import 'reachability_probe.dart';

/// تنفيذ الويب: لا فحص فعلي — يُعتمد طور التوقيع نفسه كتنفيذ المنصات
/// الأخرى، وتُعتمد حالة واجهة الشبكة كما هي.
class SocketReachabilityProbe implements ReachabilityProbe {
  SocketReachabilityProbe({
    required String host,
    required int port,
    required Duration timeout,
  });

  @override
  Future<bool> isReachable() async => true;
}
