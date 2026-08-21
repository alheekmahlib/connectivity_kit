import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

import 'connectivity_source.dart';
import 'connectivity_status.dart';
import 'reachability/reachability_probe.dart';
import 'reachability/reachability_probe_stub.dart'
    if (dart.library.io) 'reachability/reachability_probe_io.dart';

/// إعدادات [ConnectionService].
class ConnectionOptions {
  const ConnectionOptions({
    /// مهلة انتظار حالة الانقطاع قبل بثّها، لتجنّب الأحداث المؤقتة الكاذبة.
    this.disconnectDebounce = const Duration(seconds: 3),

    /// تفعيل فحص الوصول الفعلي للإنترنت قبل اعتبار الاتصال متاحًا.
    /// معطَّل افتراضيًا؛ عند تفعيله تُعتبر الشبكة بلا إنترنت إن فشل الفحص.
    this.enableReachability = false,

    /// مهلة فحص الوصول الفعلي.
    this.reachabilityTimeout = const Duration(seconds: 5),

    /// المضيف المستهدف في فحص الوصول (اتصال TCP مباشر بلا HTTP).
    this.probeHost = '1.1.1.1',

    /// المنفذ المستهدف في فحص الوصول.
    this.probePort = 53,
  });

  final Duration disconnectDebounce;
  final bool enableReachability;
  final Duration reachabilityTimeout;
  final String probeHost;
  final int probePort;
}

/// خدمة مراقبة الاتصال بالإنترنت: تبثّ [ConnectivityStatus] عند تغيّرها فقط،
/// مع debounce للانقطاع وخيار فحص الوصول الفعلي.
///
/// يجب استدعاء [init] مع `await` قبل استخدام الخدمة، و[dispose] عند عدم
/// الحاجة إليها. استدعاء [dispose] قبل [init] آمن.
class ConnectionService {
  ConnectionService({
    ConnectionOptions options = const ConnectionOptions(),
    ConnectivitySource? connectivitySource,
    ReachabilityProbe? reachabilityProbe,
  })  : _options = options,
        _connectivitySource =
            connectivitySource ?? const DefaultConnectivitySource(),
        _reachabilityProbe = reachabilityProbe ??
            (options.enableReachability
                ? SocketReachabilityProbe(
                    host: options.probeHost,
                    port: options.probePort,
                    timeout: options.reachabilityTimeout,
                  )
                : null);

  final ConnectionOptions _options;
  final ConnectivitySource _connectivitySource;
  final ReachabilityProbe? _reachabilityProbe;

  final StreamController<ConnectivityStatus> _connectionStatusController =
      StreamController<ConnectivityStatus>.broadcast();

  /// بث التغيرات في حالة الاتصال (للقيمة المتغيّرة فقط).
  Stream<ConnectivityStatus> get connectionStream =>
      _connectionStatusController.stream;

  ConnectivityStatus _currentStatus = ConnectivityStatus.offline;

  /// آخر حالة اتصال معروفة.
  ConnectivityStatus get currentStatus => _currentStatus;

  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  Timer? _disconnectTimer;
  bool _isInitialized = false;
  bool _isDisposed = false;

  /// هل وصل حدث من الـ stream؟ يمنع نتيجة checkConnectivity الأولية —
  /// وهي الأقدم — من الكتابة فوق حدث أحدث.
  bool _hasStreamEvent = false;

  /// يُبطل أي فحص وصول جارٍ عند وصول حدث أحدث أو عند dispose.
  int _probeSequence = 0;

  /// دالة التهيئة — يجب استدعاؤها مع await قبل استخدام الخدمة.
  /// الاستدعاء المتكرر آمن (يُتجاهل).
  Future<void> init() async {
    if (_isInitialized || _isDisposed) return;
    _isInitialized = true;

    _connectivitySubscription =
        _connectivitySource.onConnectivityChanged.listen(_onConnectivityResult);

    final initialResult = await _connectivitySource.checkConnectivity();
    if (_isDisposed || _hasStreamEvent) return;
    await _applyResolved(resolveConnectivityStatus(initialResult));
  }

  void _onConnectivityResult(List<ConnectivityResult> result) {
    _hasStreamEvent = true;
    _applyResolved(resolveConnectivityStatus(result));
  }

  /// تطبيق الحالة مع فحص الوصول الفعلي إن كان مفعّلًا.
  Future<void> _applyResolved(ConnectivityStatus status) async {
    if (!_options.enableReachability ||
        _reachabilityProbe == null ||
        status == ConnectivityStatus.offline) {
      // لا معنى لفحص وصول بلا واجهة شبكة أصلًا
      _updateWithDebounce(status);
      return;
    }

    final sequence = ++_probeSequence;
    bool reachable;
    try {
      reachable = await _reachabilityProbe.isReachable();
    } on Object {
      reachable = false;
    }
    if (_isDisposed || sequence != _probeSequence) return;
    _updateWithDebounce(reachable ? status : ConnectivityStatus.offline);
  }

  /// اتصال فعلي: يُطبَّق فورًا مع إلغاء أي انتظار انقطاع معلّق.
  /// انقطاع محتمل: انتظر مهلة الـ debounce قبل البثّ.
  void _updateWithDebounce(ConnectivityStatus newStatus) {
    if (newStatus != ConnectivityStatus.offline) {
      _disconnectTimer?.cancel();
      _disconnectTimer = null;
      _applyStatus(newStatus);
    } else {
      if (_disconnectTimer?.isActive ?? false) return;
      _disconnectTimer = Timer(_options.disconnectDebounce, () {
        _disconnectTimer = null;
        _applyStatus(ConnectivityStatus.offline);
      });
    }
  }

  /// بث الحالة الجديدة فقط إذا تغيّرت عن السابقة.
  void _applyStatus(ConnectivityStatus newStatus) {
    if (newStatus == _currentStatus) return;
    _currentStatus = newStatus;
    if (!_connectionStatusController.isClosed) {
      _connectionStatusController.add(newStatus);
    }
    debugPrint('Connectivity status updated: $newStatus');
  }

  /// إغلاق الاشتراك والـ StreamController — آمن قبل init وبعد dispose.
  Future<void> dispose() async {
    if (_isDisposed) return;
    _isDisposed = true;
    _disconnectTimer?.cancel();
    _disconnectTimer = null;
    _probeSequence++; // يُبطل أي فحص وصول جارٍ
    await _connectivitySubscription?.cancel();
    _connectivitySubscription = null;
    await _connectionStatusController.close();
  }
}
