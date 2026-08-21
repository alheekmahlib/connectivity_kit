import 'package:connectivity_plus/connectivity_plus.dart';

/// مصدر نتائج الاتصال — يسمح بحقن بديل لأغراض الاختبار.
abstract interface class ConnectivitySource {
  /// بث التغيرات في واجهة الشبكة.
  Stream<List<ConnectivityResult>> get onConnectivityChanged;

  /// فحص الحالة الحالية مرة واحدة.
  Future<List<ConnectivityResult>> checkConnectivity();
}

/// التنفيذ الافتراضي المبني مباشرة على connectivity_plus.
class DefaultConnectivitySource implements ConnectivitySource {
  const DefaultConnectivitySource();

  @override
  Stream<List<ConnectivityResult>> get onConnectivityChanged =>
      Connectivity().onConnectivityChanged;

  @override
  Future<List<ConnectivityResult>> checkConnectivity() =>
      Connectivity().checkConnectivity();
}
