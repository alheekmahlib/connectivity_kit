import 'package:connectivity_plus/connectivity_plus.dart';

/// حالات الاتصال الموحّدة للتطبيق.
enum ConnectivityStatus {
  /// شبكة واسعة النطاق: Wi-Fi أو Ethernet أو VPN.
  wifi,

  /// بيانات الجوال (شبكة خلوية).
  cellular,

  /// لا توجد واجهة شبكة متاحة، أو فشل فحص الوصول الفعلي.
  offline,
}

/// أدوات مساعدة مختصرة فوق [ConnectivityStatus].
extension ConnectivityStatusX on ConnectivityStatus {
  /// هل يوجد اتصال متاح (أي حالة غير [ConnectivityStatus.offline])؟
  bool get isOnline => this != ConnectivityStatus.offline;

  /// هل الاتصال عبر بيانات الجوال؟ مفيد لتحذير المستخدم قبل التنزيلات.
  bool get isCellular => this == ConnectivityStatus.cellular;
}

/// تحويل قائمة [ConnectivityResult] إلى حالة واحدة.
///
/// الأولوية: شبكة واسعة النطاق (wifi/ethernet/vpn) ثم بيانات الجوال،
/// وما عدا ذلك يُعد انقطاعًا.
ConnectivityStatus resolveConnectivityStatus(List<ConnectivityResult> results) {
  if (results.contains(ConnectivityResult.wifi) ||
      results.contains(ConnectivityResult.ethernet) ||
      results.contains(ConnectivityResult.vpn)) {
    return ConnectivityStatus.wifi;
  }
  if (results.contains(ConnectivityResult.mobile)) {
    return ConnectivityStatus.cellular;
  }
  return ConnectivityStatus.offline;
}
