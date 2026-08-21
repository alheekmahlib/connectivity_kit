import 'dart:async';

import 'package:connectivity_kit/connectivity_kit.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_test/flutter_test.dart';

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
        options: const ConnectionOptions(
          disconnectDebounce: Duration.zero,
        ),
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
    expect(emitted, isEmpty); // لم تتغير الحالة أصلًا
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
    expect(emitted, [ConnectivityStatus.offline]);
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
  });
}
