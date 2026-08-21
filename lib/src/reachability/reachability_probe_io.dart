import 'dart:io';

import 'reachability_probe.dart';

/// فحص الوصول عبر محاولة اتصال TCP مباشرة — أسرع وأخف من طلب HTTP
/// ولا يتأثر بذاكرة DNS المؤقتة.
class SocketReachabilityProbe implements ReachabilityProbe {
  SocketReachabilityProbe({
    required this.host,
    required this.port,
    required this.timeout,
  });

  final String host;
  final int port;
  final Duration timeout;

  @override
  Future<bool> isReachable() async {
    Socket? socket;
    try {
      socket = await Socket.connect(host, port, timeout: timeout);
      return true;
    } on SocketException {
      return false;
    } on Exception {
      // أي خطأ آخر (مهلة مثلًا) يُعامل كعدم وصول
      return false;
    } finally {
      socket?.destroy();
    }
  }
}
