import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:get/get.dart';

import '../connection_service.dart';
import '../connectivity_status.dart';
import 'get_storage_queue_store.dart';
import 'memory_queue_store.dart';
import 'queued_task.dart';
import 'queue_store.dart';
import 'task_handler.dart';

/// إعدادات [TaskQueueService].
class TaskQueueOptions {
  const TaskQueueOptions({
    /// الحد الأقصى لمحاولات تنفيذ المهمة قبل اعتبارها فاشلة نهائيًا.
    this.maxAttempts = 3,

    /// تأخير أول إعادة محاولة بعد الفشل.
    this.initialRetryDelay = const Duration(seconds: 5),

    /// معامل التضاعف بين محاولات إعادة المحاولة المتتالية.
    this.retryDelayFactor = 2,

    /// سقف تأخير إعادة المحاولة مهما تضاعف.
    this.maxRetryDelay = const Duration(seconds: 60),

    /// مهلة تنفيذ المهمة الواحدة؛ تجاوزها يُحسب فشلًا للمحاولة — ضروري
    /// لأن الطابور تسلسلي ومهمة معلّقة إلى الأبد تحجب من بعدها.
    this.taskTimeout = const Duration(seconds: 30),
  });

  final int maxAttempts;
  final Duration initialRetryDelay;
  final int retryDelayFactor;
  final Duration maxRetryDelay;
  final Duration taskTimeout;
}

/// حدث يُبثّ من [TaskQueueService.events] عن دورة حياة الطابور.
sealed class QueueEvent {
  const QueueEvent();
}

/// حدث يخصّ مهمة بعينها.
sealed class QueueTaskEvent extends QueueEvent {
  const QueueTaskEvent(this.task);

  /// المهمة التي يتعلق بها الحدث.
  final QueuedTask task;
}

/// أُضيفت مهمة إلى الطابور (جديدة أو حلّت محلّ معلّقة بنفس groupId).
class QueueTaskEnqueued extends QueueTaskEvent {
  const QueueTaskEnqueued(super.task);
}

/// نجح تنفيذ المهمة وأُزيلت من الطابور.
class QueueTaskSucceeded extends QueueTaskEvent {
  const QueueTaskSucceeded(super.task);
}

/// فشلت محاولة وبقي رصيد محاولات؛ أُعيدت جدولة المهمة بتأخير تصاعدي.
class QueueTaskRetrying extends QueueTaskEvent {
  const QueueTaskRetrying(super.task,
      {required this.attempt, required this.error});

  /// رقم المحاولة الفاشلة (يبدأ من 1).
  final int attempt;

  /// الخطأ الذي أفشل المحاولة.
  final Object error;
}

/// نفدت محاولات المهمة وحُدِّدت فاشلة نهائيًا (تبقى محفوظة).
class QueueTaskFailedPermanently extends QueueTaskEvent {
  const QueueTaskFailedPermanently(super.task, {required this.error});

  /// خطأ المحاولة الأخيرة.
  final Object error;
}

/// توقفت حلقة التنفيذ (فرغ الطابور أو انقطع الاتصال)؛ مناسب لتحديث
/// مؤشرات الواجهة مثل isDraining.
class QueueDrained extends QueueEvent {
  const QueueDrained();
}

/// خدمة طابور الأعمال دون اتصال: المهام التي تحتاج إنترنت تُضاف إلى
/// طابور محفوظ على القرص وتُنفَّذ تسلسليًا بترتيب إضافتها عند توفر
/// الاتصال، مع إعادة محاولة محدودة وتأخير تصاعدي — دون تدخل المستخدم.
///
/// يجب تسجيل المعالجات (registerHandler) ثم استدعاء [init] مع await قبل
/// أي استخدام آخر، و[dispose] عند عدم الحاجة. استدعاء [dispose] قبل
/// [init] آمن.
class TaskQueueService {
  TaskQueueService({
    TaskQueueOptions options = const TaskQueueOptions(),
    ConnectionService? connectionService,
    QueueStore? store,
  })  : _options = options,
        _connectionService = connectionService ?? _findRegisteredService(),
        _store = store;

  static ConnectionService _findRegisteredService() {
    if (Get.isRegistered<ConnectionService>()) {
      return Get.find<ConnectionService>();
    }
    throw StateError(
      'ConnectionService غير مسجّل في GetX.\n'
      'سجّله أولاً: Get.put(service, permanent: true)\n'
      'أو مرّره مباشرة: TaskQueueService(connectionService: service)',
    );
  }

  final TaskQueueOptions _options;
  final ConnectionService _connectionService;
  QueueStore? _store;

  final StreamController<QueueEvent> _eventsController =
      StreamController<QueueEvent>.broadcast();

  /// بث أحداث دورة حياة الطابور.
  Stream<QueueEvent> get events => _eventsController.stream;

  final Map<String, TaskHandler> _handlers = {};

  List<QueuedTask> _tasks = [];

  StreamSubscription<ConnectivityStatus>? _statusSubscription;
  Completer<void>? _wakeCompleter;
  String? _runningTaskId;
  bool _draining = false;
  bool _isInitialized = false;
  bool _isDisposed = false;

  /// عدّاد أحادي لتوليد معرفات فريدة داخل هذا الـ isolate.
  static int _idCounter = 0;

  /// مصنع المخزن الافتراضي؛ قابل للاستبدال في الاختبارات لمحاكاة فشل
  /// الإنشاء (كانقطاع قناة المنصة على بعض الأجهزة).
  @visibleForTesting
  static Future<QueueStore> Function() defaultStoreFactory =
      GetStorageQueueStore.create;

  /// المهام المعلّقة بترتيب إضافتها.
  List<QueuedTask> get pendingTasks => List.unmodifiable(
        _tasks.where((task) => task.status == TaskStatus.pending),
      );

  /// المهام الفاشلة نهائيًا.
  List<QueuedTask> get failedTasks => List.unmodifiable(
        _tasks.where((task) => task.status == TaskStatus.failed),
      );

  /// عدد المهام المعلّقة.
  int get pendingCount =>
      _tasks.where((task) => task.status == TaskStatus.pending).length;

  /// عدد المهام الفاشلة نهائيًا.
  int get failedCount =>
      _tasks.where((task) => task.status == TaskStatus.failed).length;

  /// هل حلقة التنفيذ تعمل الآن؟
  bool get isDraining => _draining;

  /// تسجيل معالج لنوع مهام؛ يُفضَّل قبل [init] حتى لا تفشل مهمة محمَّلة
  /// من قرص سابق لمجرد تأخر التسجيل. إعادة التسجيل لنوع تستبدل المعالج.
  void registerHandler(String type, TaskHandler handler) {
    if (_isDisposed) return;
    _handlers[type] = handler;
  }

  /// التهيئة — يجب استدعاؤها مع await قبل استخدام الطابور.
  /// الاستدعاء المتكرر آمن (يُتجاهل).
  Future<void> init() async {
    if (_isInitialized || _isDisposed) return;
    _isInitialized = true;

    _store ??= await _createDefaultStore();
    try {
      _tasks = await _store!.load();
    } on Object catch (e) {
      debugPrint('TaskQueue: فشل تحميل الطابور المحفوظ — يبدأ فارغًا: $e');
      _tasks = [];
    }

    _statusSubscription =
        _connectionService.connectionStream.listen(_onStatusChanged);
    _scheduleDrain();
  }

  /// ينشئ المخزن الافتراضي، وإن فشل إنشاؤه هبط إلى مخزن في الذاكرة —
  /// فشل التخزين لا يجوز أن يجهض init كلها فيعلّق إقلاع التطبيق المضيف.
  Future<QueueStore> _createDefaultStore() async {
    try {
      return await defaultStoreFactory();
    } on Object catch (e) {
      debugPrint(
        'TaskQueue: فشل إنشاء مخزن القرص — الطابور يعمل في الذاكرة لهذه '
        'الجلسة: $e',
      );
      return MemoryQueueStore();
    }
  }

  /// إضافة مهمة إلى الطابور؛ إن كان هناك اتصال بدأ تنفيذها فورًا بالترتيب،
  /// وإلا بقيت معلّقة حتى عودة الاتصال. مهمة بنفس [groupId] لمهمة معلّقة
  /// سابقة تحلّ محلّها (الأحدث تفوز).
  Future<QueuedTask> enqueue({
    required String type,
    required Map<String, dynamic> payload,
    String? groupId,
  }) async {
    _ensureUsable();
    if (groupId != null) {
      _tasks.removeWhere(
        (task) => task.status == TaskStatus.pending && task.groupId == groupId,
      );
    }
    final task = QueuedTask(
      id: _newTaskId(),
      type: type,
      payload: payload,
      groupId: groupId,
      maxAttempts: _options.maxAttempts,
      createdAt: DateTime.now(),
    );
    _tasks.add(task);
    await _persist();
    _emit(QueueTaskEnqueued(task));
    _scheduleDrain();
    return task;
  }

  /// إزالة مهمة من الطابور بمعرّفها؛ المهمة قيد التنفيذ الآن غير قابلة
  /// للإزالة (يعيد false).
  Future<bool> removeTask(String id) async {
    _ensureUsable();
    if (id == _runningTaskId) return false;
    final before = _tasks.length;
    _tasks.removeWhere((task) => task.id == id);
    if (_tasks.length == before) return false;
    await _persist();
    return true;
  }

  /// إعادة جدولة مهمة فاشلة نهائيًا: تُصفَّر محاولاتها وتُلحق بآخر الطابور
  /// كمعلّقة جديدة. يعيد false إن لم توجد مهمة فاشلة بهذا المعرّف.
  Future<bool> retryTask(String id) async {
    _ensureUsable();
    final index = _tasks.indexWhere(
      (task) => task.id == id && task.status == TaskStatus.failed,
    );
    if (index == -1) return false;
    final old = _tasks.removeAt(index);
    _tasks.add(
      QueuedTask(
        id: old.id,
        type: old.type,
        payload: old.payload,
        groupId: old.groupId,
        maxAttempts: old.maxAttempts,
        createdAt: old.createdAt,
      ),
    );
    await _persist();
    _scheduleDrain();
    return true;
  }

  /// حذف كل المهام الفاشلة نهائيًا؛ يعيد عدد المحذوفات.
  Future<int> clearFailed() async {
    _ensureUsable();
    final before = _tasks.length;
    _tasks.removeWhere((task) => task.status == TaskStatus.failed);
    final removed = before - _tasks.length;
    if (removed > 0) await _persist();
    return removed;
  }

  /// إغلاق الاشتراك والبث وانتظار المهمة الجارية ثم الحفظ —
  /// آمن قبل init وبعد dispose.
  Future<void> dispose() async {
    if (_isDisposed) return;
    _isDisposed = true;
    await _statusSubscription?.cancel();
    _statusSubscription = null;
    _wake(); // أيقظ حلقة منتظرة لتلاحظ _isDisposed وتتوقف
    try {
      await _runningFuture;
    } on Object {
      // _executeAt لا يرمي أصلًا؛ حماية إضافية فقط.
    }
    await _persist();
    await _eventsController.close();
  }

  Future<void>? _runningFuture;

  void _onStatusChanged(ConnectivityStatus status) {
    // الانقطاع لا يُلغي مهمة جارية؛ الحلقة نفسها تتوقف قبل بدء مهمة جديدة.
    if (status.isOnline) _scheduleDrain();
  }

  void _ensureUsable() {
    if (_isDisposed) {
      throw StateError(
          'TaskQueueService مُهملة (dispose) — أنشئ مثيلًا جديدًا.');
    }
    if (!_isInitialized) {
      throw StateError(
        'TaskQueueService غير مهيأة.\n'
        'استدعِ await queue.init() قبل إضافة المهام أو التحكم بالطابور.',
      );
    }
  }

  String _newTaskId() {
    final micros = DateTime.now().microsecondsSinceEpoch;
    return '$micros-${_idCounter++}';
  }

  /// بدء الحلقة إن كانت متوقفة، أو إيقاظ حلقة منتظرة لإعادة مسح الطابور.
  void _scheduleDrain() {
    if (_isDisposed) return;
    if (!_connectionService.currentStatus.isOnline) return;
    if (_draining) {
      _wake();
      return;
    }
    unawaited(_drainLoop());
  }

  void _wake() {
    final completer = _wakeCompleter;
    if (completer != null && !completer.isCompleted) completer.complete();
  }

  /// الحلقة التسلسلية: تنفّذ أول مهمة مؤهلة، وتتخطى المؤجلة بـ nextAttemptAt
  /// وتقف عند انقطاع الاتصال أو فراغ الطابور أو بعد إيقاظها أثناء انتظار.
  Future<void> _drainLoop() async {
    _draining = true;
    try {
      while (!_isDisposed) {
        if (!_connectionService.currentStatus.isOnline) break;

        final now = DateTime.now();
        var eligibleIndex = -1;
        for (var i = 0; i < _tasks.length; i++) {
          final task = _tasks[i];
          if (task.status != TaskStatus.pending) continue;
          final due = task.nextAttemptAt;
          if (due == null || !due.isAfter(now)) {
            eligibleIndex = i;
            break;
          }
        }

        if (eligibleIndex == -1) {
          // لا مهمة مؤهلة الآن: انتظر أقرب تأجيل أو حدثًا يوقظنا.
          final earliest = _earliestRetryTime();
          if (earliest == null) break; // لا معلّقة مؤجّلة أصلًا → توقف
          var delay = earliest.difference(DateTime.now());
          if (delay < Duration.zero) delay = Duration.zero;
          await _park(delay);
          continue;
        }

        await _executeAt(eligibleIndex);
      }
    } finally {
      _draining = false;
      _emit(const QueueDrained());
    }
  }

  DateTime? _earliestRetryTime() {
    DateTime? earliest;
    for (final task in _tasks) {
      if (task.status != TaskStatus.pending) continue;
      final due = task.nextAttemptAt;
      if (due == null) return null;
      if (earliest == null || due.isBefore(earliest)) earliest = due;
    }
    return earliest;
  }

  /// انتظار قابل للإيقاظ: مؤقت للمدة أو إشارة من [_wake] أيّهما أولًا.
  Future<void> _park(Duration delay) {
    final completer = _wakeCompleter = Completer<void>();
    final timer = Timer(delay, _wake);
    return completer.future.whenComplete(timer.cancel);
  }

  Future<void> _executeAt(int index) async {
    final task = _tasks[index];
    final attempt = task.attempts + 1;
    _runningTaskId = task.id;
    final runFuture = _runHandler(task);
    _runningFuture = runFuture;
    Object? caught;
    try {
      await runFuture;
    } on Object catch (error) {
      caught = error;
    } finally {
      _runningTaskId = null;
      _runningFuture = null;
    }

    if (caught == null) {
      _tasks.removeWhere((t) => t.id == task.id);
      await _persist();
      _emit(QueueTaskSucceeded(task));
      return;
    }

    final error = caught;
    final isFinal = attempt >= task.maxAttempts;
    final updated = task.copyWith(
      attempts: attempt,
      status: isFinal ? TaskStatus.failed : TaskStatus.pending,
      lastError: _formatError(error),
      nextAttemptAt: isFinal ? null : DateTime.now().add(_retryDelay(attempt)),
    );
    final taskIndex = _tasks.indexWhere((t) => t.id == task.id);
    if (taskIndex != -1) _tasks[taskIndex] = updated;
    await _persist();
    if (isFinal) {
      _emit(QueueTaskFailedPermanently(updated, error: error));
    } else {
      _emit(QueueTaskRetrying(updated, attempt: attempt, error: error));
    }
  }

  Future<void> _runHandler(QueuedTask task) async {
    final handler = _handlers[task.type];
    if (handler == null) {
      // معالج غائب = فشل قابل للإعادة؛ يرحم تسجيل معالجات متأخر بعد init.
      throw StateError('لا يوجد معالج مسجَّل لنوع المهمة "${task.type}"');
    }
    await handler(task.payload).timeout(_options.taskTimeout);
  }

  /// تأخير إعادة المحاولة بعد المحاولة رقم [failedAttempt]: يبدأ من
  /// initialRetryDelay ويتضاعف بـ retryDelayFactor حتى maxRetryDelay.
  Duration _retryDelay(int failedAttempt) {
    var delay = _options.initialRetryDelay;
    for (var i = 1; i < failedAttempt; i++) {
      final doubled = delay * _options.retryDelayFactor;
      if (doubled > _options.maxRetryDelay) {
        return _options.maxRetryDelay;
      }
      delay = doubled;
    }
    return delay > _options.maxRetryDelay ? _options.maxRetryDelay : delay;
  }

  String _formatError(Object error) {
    final text = error.toString();
    return text.length > QueuedTask.maxErrorLength
        ? text.substring(0, QueuedTask.maxErrorLength)
        : text;
  }

  Future<void> _persist() async {
    final store = _store;
    if (store == null) return;
    try {
      await store.save(List.of(_tasks));
    } on Object catch (e) {
      debugPrint('TaskQueue: فشل حفظ الطابور — تستمر الجلسة في الذاكرة: $e');
    }
  }

  void _emit(QueueEvent event) {
    if (!_eventsController.isClosed) _eventsController.add(event);
  }
}
