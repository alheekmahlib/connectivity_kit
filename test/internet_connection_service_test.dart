import 'package:connectivity_kit/connectivity_kit.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/fakes.dart';

void main() {
  test('init يعبّي الحالة الأولية من checkConnectivity', () async {
    final source = FakeConnectivitySource()
      ..current = const [ConnectivityResult.mobile];
    final service = ConnectionService(connectivitySource: source);

    await service.init();

    expect(service.currentStatus, ConnectivityStatus.cellular);
    await service.dispose();
  });

  test(
    'حدث أحدث من الـ stream لا تكتبي فوقه نتيجة checkConnectivity القديمة',
    () async {
      final source = FakeConnectivitySource()
        ..current = const [ConnectivityResult.none] // نتيجة أولية قديمة
        ..checkDelay = const Duration(milliseconds: 60);
      final service = ConnectionService(
        connectivitySource: source,
        options: const ConnectionOptions(disconnectDebounce: Duration.zero),
      );

      final initFuture = service.init();
      // حدث أحدث يصل قبل اكتمال الفحص الأولي
      await Future<void>.delayed(const Duration(milliseconds: 10));
      source.emit(const [ConnectivityResult.wifi]);
      await initFuture;

      expect(service.currentStatus, ConnectivityStatus.wifi);
      await service.dispose();
    },
  );

  test('الانقطاع العابر أقصر من الـ debounce لا يُبث', () async {
    final source = FakeConnectivitySource();
    final service = ConnectionService(
      connectivitySource: source,
      options: const ConnectionOptions(
        disconnectDebounce: Duration(milliseconds: 80),
      ),
    );
    await service.init();
    final emitted = <ConnectivityStatus>[];
    final sub = service.connectionStream.listen(emitted.add);
    expect(service.currentStatus, ConnectivityStatus.wifi);

    source.emit(const [ConnectivityResult.none]);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    source.emit(const [ConnectivityResult.wifi]); // عودة قبل انقضاء المهلة
    await Future<void>.delayed(const Duration(milliseconds: 150));

    expect(service.currentStatus, ConnectivityStatus.wifi);
    // البذرة فقط؛ الانقطاع العابر أقصر من الـ debounce لا يُبث حدثًا
    expect(emitted, [ConnectivityStatus.wifi]);
    await sub.cancel();
    await service.dispose();
  });

  test('الانقطاع المستمر يُبث بعد مهلة الـ debounce فقط', () async {
    final source = FakeConnectivitySource();
    final service = ConnectionService(
      connectivitySource: source,
      options: const ConnectionOptions(
        disconnectDebounce: Duration(milliseconds: 60),
      ),
    );
    await service.init();
    final emitted = <ConnectivityStatus>[];
    final sub = service.connectionStream.listen(emitted.add);

    source.emit(const [ConnectivityResult.none]);
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(service.currentStatus, ConnectivityStatus.wifi); // ما زال بالانتظار

    await Future<void>.delayed(const Duration(milliseconds: 120));
    expect(service.currentStatus, ConnectivityStatus.offline);
    expect(emitted, [ConnectivityStatus.wifi, ConnectivityStatus.offline]);
    await sub.cancel();
    await service.dispose();
  });

  test('المشترك بعد init يستلم الحالة الراهنة فورًا (بذرة)', () async {
    final source = FakeConnectivitySource()
      ..current = const [ConnectivityResult.wifi];
    final service = ConnectionService(connectivitySource: source);
    await service.init();

    // محاكاة مستمع يُنشأ بعد اكتمال main() — كالمزوّدات التي تُبنى
    // مع أول إطار واجهة بعد runApp.
    final received = <ConnectivityStatus>[];
    final sub = service.connectionStream.listen(received.add);
    await Future<void>.delayed(Duration.zero);

    expect(received, [ConnectivityStatus.wifi]);
    await sub.cancel();
    await service.dispose();
  });

  test('البذرة تصل حتى لو أعاد المصدر إطلاق نفس الحالة بعدها', () async {
    final source = FakeConnectivitySource()
      ..current = const [ConnectivityResult.wifi];
    final service = ConnectionService(connectivitySource: source);
    await service.init();

    final received = <ConnectivityStatus>[];
    final sub = service.connectionStream.listen(received.add);
    await Future<void>.delayed(Duration.zero);

    // النظام يعيد إطلاق wifi (بلا تغيير فعلي) — لا يجب أن يضيف حدثًا
    source.emit(const [ConnectivityResult.wifi]);
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(received, [ConnectivityStatus.wifi]);
    await sub.cancel();
    await service.dispose();
  });

  test('dispose قبل init آمن ولا يرمي استثناءً', () async {
    final service = ConnectionService();
    await service.dispose();
    expect(service.currentStatus, ConnectivityStatus.offline);
  });

  test('dispose يوقف بث الأحداث بعده', () async {
    final source = FakeConnectivitySource();
    final service = ConnectionService(connectivitySource: source);
    await service.init();
    await service.dispose();

    source.emit(const [ConnectivityResult.mobile]);
    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(service.currentStatus, ConnectivityStatus.wifi);
  });

  group('مع تفعيل reachability', () {
    test('init لا يُحجب على فحص الوصول الأولي', () async {
      final source = FakeConnectivitySource()
        ..current = const [ConnectivityResult.wifi];
      final probe = FakeReachabilityProbe(
        delay: const Duration(milliseconds: 250),
      )..reachable = false;
      final service = ConnectionService(
        connectivitySource: source,
        reachabilityProbe: probe,
        options: const ConnectionOptions(
          enableReachability: true,
          disconnectDebounce: Duration.zero,
        ),
      );

      var initDone = false;
      final initFuture = service.init().then((_) => initDone = true);

      // أثناء الفحص الجارٍ: init عاد بالفعل وحالة الواجهة مبثوثة فورًا
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(
        initDone,
        isTrue,
        reason: 'init يجب ألا ينتظر نتيجة فحص الوصول الفعلي',
      );
      expect(
        service.currentStatus,
        ConnectivityStatus.wifi,
        reason: 'حالة الواجهة تُبث فورًا قبل اكتمال الفحص',
      );

      // وعند فشل الفحص لاحقًا تُقلب الحالة إلى offline عبر الـ stream
      await initFuture;
      await Future<void>.delayed(const Duration(milliseconds: 250));
      expect(probe.callCount, 1);
      expect(service.currentStatus, ConnectivityStatus.offline);
      await service.dispose();
    });

    test('فشل الفحص يحوّل الحالة إلى offline', () async {
      final source = FakeConnectivitySource()
        ..current = const [ConnectivityResult.wifi];
      final probe = FakeReachabilityProbe()..reachable = false;
      final service = ConnectionService(
        connectivitySource: source,
        reachabilityProbe: probe,
        options: const ConnectionOptions(
          enableReachability: true,
          disconnectDebounce: Duration(milliseconds: 40),
        ),
      );

      await service.init();

      expect(probe.callCount, 1);
      // init تبث حالة الواجهة فورًا (wifi) ثم تُقلب إلى offline بعد اكتمال
      // الفحص الفاشل + مهلة الـ debounce (40ms).
      expect(service.currentStatus, ConnectivityStatus.wifi);
      await Future<void>.delayed(const Duration(milliseconds: 120));
      expect(service.currentStatus, ConnectivityStatus.offline);
      await service.dispose();
    });

    test('نجاح الفحص يُبقي الحالة كما هي', () async {
      final source = FakeConnectivitySource()
        ..current = const [ConnectivityResult.wifi];
      final probe = FakeReachabilityProbe()..reachable = true;
      final service = ConnectionService(
        connectivitySource: source,
        reachabilityProbe: probe,
        options: const ConnectionOptions(enableReachability: true),
      );

      await service.init();

      expect(service.currentStatus, ConnectivityStatus.wifi);
      expect(probe.callCount, 1);
      await service.dispose();
    });

    test('حدث أحدث أثناء فحص جارٍ يُبطل نتيجة الفحص الأقدم', () async {
      final source = FakeConnectivitySource()
        ..current = const [ConnectivityResult.wifi];
      final probe = FakeReachabilityProbe(
        delay: const Duration(milliseconds: 80),
      )..reachable = true;
      final service = ConnectionService(
        connectivitySource: source,
        reachabilityProbe: probe,
        options: const ConnectionOptions(enableReachability: true),
      );
      await service.init();

      // فحص wifi جارٍ، ثم يصل حدث أحدث (cellular) قبل اكتماله
      source.emit(const [ConnectivityResult.mobile]);
      await Future<void>.delayed(const Duration(milliseconds: 200));

      expect(probe.callCount, 2);
      expect(service.currentStatus, ConnectivityStatus.cellular);
      await service.dispose();
    });

    test('إعادة الفحص الدورية تستعيد الاتصال بعد فشل عابر', () async {
      final source = FakeConnectivitySource()
        ..current = const [ConnectivityResult.wifi];
      final probe = FakeReachabilityProbe()..reachable = false;
      final service = ConnectionService(
        connectivitySource: source,
        reachabilityProbe: probe,
        options: const ConnectionOptions(
          enableReachability: true,
          disconnectDebounce: Duration(milliseconds: 40),
          recheckInterval: Duration(milliseconds: 80),
        ),
      );

      await service.init();
      // الفحص الأولي فشل: الحالة تُقلب إلى offline بعد الـ debounce (40ms)
      await Future<void>.delayed(const Duration(milliseconds: 120));
      expect(service.currentStatus, ConnectivityStatus.offline);

      // الشبكة عادت فعلًا؛ إعادة الفحص الدورية يجب أن تلتقطها
      probe.reachable = true;
      await Future<void>.delayed(const Duration(milliseconds: 250));

      expect(service.currentStatus, ConnectivityStatus.wifi);
      expect(probe.callCount, greaterThanOrEqualTo(2));
      await service.dispose();
    });

    test('recheckInterval = zero يعطّل إعادة الفحص الدورية', () async {
      final source = FakeConnectivitySource()
        ..current = const [ConnectivityResult.wifi];
      final probe = FakeReachabilityProbe()..reachable = false;
      final service = ConnectionService(
        connectivitySource: source,
        reachabilityProbe: probe,
        options: const ConnectionOptions(
          enableReachability: true,
          disconnectDebounce: Duration(milliseconds: 40),
          recheckInterval: Duration.zero,
        ),
      );

      await service.init();
      probe.reachable = true;
      await Future<void>.delayed(const Duration(milliseconds: 150));

      expect(probe.callCount, 1); // الفحص الأولي فقط
      expect(service.currentStatus, ConnectivityStatus.offline);
      await service.dispose();
    });
  });
}
