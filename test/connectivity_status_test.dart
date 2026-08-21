import 'package:connectivity_kit/connectivity_kit.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('resolveConnectivityStatus', () {
    test('يرجّح الشبكة الواسعة على بيانات الجوال', () {
      const results = [ConnectivityResult.mobile, ConnectivityResult.wifi];
      expect(resolveConnectivityStatus(results), ConnectivityStatus.wifi);
    });

    test('ethernet وvpn يُعدّان شبكة واسعة النطاق', () {
      expect(
        resolveConnectivityStatus([ConnectivityResult.ethernet]),
        ConnectivityStatus.wifi,
      );
      expect(
        resolveConnectivityStatus([ConnectivityResult.vpn]),
        ConnectivityStatus.wifi,
      );
    });

    test('بيانات الجوال وحدها حالة cellular', () {
      expect(
        resolveConnectivityStatus([ConnectivityResult.mobile]),
        ConnectivityStatus.cellular,
      );
    });

    test('none والقائمة الفارغة وbluetooth حالة offline', () {
      expect(
        resolveConnectivityStatus([ConnectivityResult.none]),
        ConnectivityStatus.offline,
      );
      expect(resolveConnectivityStatus([]), ConnectivityStatus.offline);
      expect(
        resolveConnectivityStatus([ConnectivityResult.bluetooth]),
        ConnectivityStatus.offline,
      );
    });
  });

  group('ConnectivityStatusX', () {
    test('isOnline صحيح لكل حالة غير offline', () {
      expect(ConnectivityStatus.wifi.isOnline, isTrue);
      expect(ConnectivityStatus.cellular.isOnline, isTrue);
      expect(ConnectivityStatus.offline.isOnline, isFalse);
    });

    test('isCellular صحيح لبيانات الجوال فقط', () {
      expect(ConnectivityStatus.cellular.isCellular, isTrue);
      expect(ConnectivityStatus.wifi.isCellular, isFalse);
      expect(ConnectivityStatus.offline.isCellular, isFalse);
    });
  });
}
