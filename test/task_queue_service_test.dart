import 'dart:async';

import 'package:connectivity_kit/connectivity_kit.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/fakes.dart';

/// ينتظر تحقق الشرط مع ضخّ الأحداث دوريًا؛ يفشل بعد مهلة بدل التعليق.
Future<void> until(
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 2),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('انتهت مهلة انتظار الشرط');
    }
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

/// بيئة اختبار جاهزة: خدمة اتصال حقيقية بمصدر مزيف + طابور بخيارات سريعة.
class _Harness {
  _Harness({
    List<ConnectivityResult> initial = const [ConnectivityResult.wifi],
    TaskQueueOptions options = const TaskQueueOptions(),
    FakeQueueStore? store,
  }) {
    source = FakeConnectivitySource()..current = initial;
    connection = ConnectionService(
      connectivitySource: source,
      options: const ConnectionOptions(disconnectDebounce: Duration.zero),
    );
    this.store = store ?? FakeQueueStore();
    queue = TaskQueueService(
      options: options,
      connectionService: connection,
      store: this.store,
    );
  }

  late final FakeConnectivitySource source;
  late final ConnectionService connection;
  late final FakeQueueStore store;
  late final TaskQueueService queue;

  /// بيئة بلا مخزن محقون — init يشغّل defaultStoreFactory نفسه؛
  /// لا تلمس harness.store هنا.
  _Harness._bare(FakeConnectivitySource src, ConnectionService conn) {
    source = src;
    connection = conn;
    queue = TaskQueueService(connectionService: connection);
  }

  /// خيارات سريعة للاختبارات: محاولتان وتأخير إعادة قصير.
  static const TaskQueueOptions fastOptions = TaskQueueOptions(
    maxAttempts: 2,
    initialRetryDelay: Duration(milliseconds: 30),
    taskTimeout: Duration(seconds: 5),
  );

  Future<void> start() async {
    await connection.init();
    await queue.init();
  }

  Future<void> dispose() async {
    await queue.dispose();
    await connection.dispose();
    await source.close();
  }
}

void main() {
  test('dispose قبل init آمن ولا يرمي استثناءً', () async {
    final harness = _Harness();
    await harness.queue.dispose();
    await harness.connection.dispose();
    await harness.source.close();
  });

  test('إنشاء الخدمة بلا ConnectionService مسجّلة يرمي StateError', () {
    expect(() => TaskQueueService(), throwsStateError);
  });

  test('enqueue قبل init يرمي StateError برسالة واضحة', () async {
    final harness = _Harness();
    await harness.connection.init();
    expect(
      () => harness.queue.enqueue(type: 't', payload: {}),
      throwsStateError,
    );
    await harness.dispose();
  });

  group('دون اتصال', () {
    test('المهمة تبقى معلّقة ومحفوظة ولا يُستدعى المعالج', () async {
      final harness = _Harness(initial: const [ConnectivityResult.none]);
      var calls = 0;
      harness.queue.registerHandler('send_note', (_) async => calls++);
      await harness.start();

      final task = await harness.queue.enqueue(
        type: 'send_note',
        payload: {'body': 'ملاحظة'},
      );

      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(calls, 0);
      expect(harness.queue.pendingCount, 1);
      expect(harness.store.saved, hasLength(1));
      expect(harness.store.saved.single.id, task.id);
      await harness.dispose();
    });

    test('عودة الاتصال تنفّذ المهمة المعلّقة تلقائيًا', () async {
      final harness = _Harness(initial: const [ConnectivityResult.none]);
      final executed = <String>[];
      harness.queue.registerHandler(
        'send_note',
        (payload) async => executed.add(payload['body'] as String),
      );
      await harness.start();
      await harness.queue.enqueue(
        type: 'send_note',
        payload: {'body': 'ملاحظة دون اتصال'},
      );

      harness.source.emit(const [ConnectivityResult.wifi]);
      await until(() => executed.isNotEmpty);

      expect(executed, ['ملاحظة دون اتصال']);
      expect(harness.queue.pendingCount, 0);
      expect(harness.store.saved, isEmpty);
      await harness.dispose();
    });

    test('groupId يستبدل المعلّقة الأقدم بالأحدث', () async {
      final harness = _Harness(initial: const [ConnectivityResult.none]);
      await harness.start();

      await harness.queue.enqueue(
        type: 'send_note',
        payload: {'v': 1},
        groupId: 'note_42',
      );
      await harness.queue.enqueue(
        type: 'send_note',
        payload: {'v': 2},
        groupId: 'note_42',
      );

      expect(harness.queue.pendingCount, 1);
      expect(harness.queue.pendingTasks.single.payload['v'], 2);
      expect(harness.store.saved, hasLength(1));
      await harness.dispose();
    });
  });

  group('متصلًا', () {
    test('المهام تُنفَّذ بترتيب FIFO صارم', () async {
      final harness = _Harness();
      final order = <int>[];
      harness.queue.registerHandler(
        'sync',
        (payload) async {
          await Future<void>.delayed(const Duration(milliseconds: 10));
          order.add(payload['n'] as int);
        },
      );
      await harness.start();

      for (var n = 1; n <= 3; n++) {
        await harness.queue.enqueue(type: 'sync', payload: {'n': n});
      }
      await until(() => order.length == 3);

      expect(order, [1, 2, 3]);
      await harness.dispose();
    });

    test('الطابور المحفوظ مسبقًا يُحمَّل عند init وينفَّذ', () async {
      final store = FakeQueueStore()
        ..saved = [
          QueuedTask(
            id: 'pre-1',
            type: 'sync',
            payload: {'n': 7},
            maxAttempts: 2,
            createdAt: DateTime.fromMillisecondsSinceEpoch(0),
          ),
        ];
      final harness = _Harness(store: store);
      final executed = <int>[];
      harness.queue.registerHandler(
        'sync',
        (payload) async => executed.add(payload['n'] as int),
      );
      await harness.start();

      await until(() => executed.isNotEmpty);
      expect(executed, [7]);
      expect(harness.queue.pendingCount, 0);
      await harness.dispose();
    });
  });

  group('الفشل والمحاولات', () {
    test('فشل واحد يعيد الجدولة بـ backoff ثم تنجح المحاولة الثانية', () async {
      final harness = _Harness(options: _Harness.fastOptions);
      var attempts = 0;
      harness.queue.registerHandler('flaky', (_) async {
        attempts++;
        if (attempts == 1) throw Exception('فشل مؤقت');
      });
      final events = <QueueEvent>[];
      final sub = harness.queue.events.listen(events.add);
      await harness.start();

      await harness.queue.enqueue(type: 'flaky', payload: {});
      await until(() => attempts >= 2);

      expect(attempts, 2);
      expect(harness.queue.pendingCount, 0);
      expect(
        events.whereType<QueueTaskRetrying>().single.attempt,
        1,
      );
      expect(
        events.whereType<QueueTaskSucceeded>(),
        hasLength(1),
      );
      await sub.cancel();
      await harness.dispose();
    });

    test('نفاد المحاولات يعلّم المهمة فاشلة نهائيًا مع حدث', () async {
      final harness = _Harness(options: _Harness.fastOptions);
      var attempts = 0;
      harness.queue.registerHandler('always_fails', (_) async {
        attempts++;
        throw Exception('خطأ دائم');
      });
      var permanentError = '';
      final sub = harness.queue.events.listen((event) {
        if (event is QueueTaskFailedPermanently) {
          permanentError = event.error.toString();
        }
      });
      await harness.start();

      final task =
          await harness.queue.enqueue(type: 'always_fails', payload: {});
      await until(() => harness.queue.failedCount == 1);

      expect(attempts, 2);
      final failed = harness.queue.failedTasks.single;
      expect(failed.id, task.id);
      expect(failed.lastError, contains('خطأ دائم'));
      expect(permanentError, contains('خطأ دائم'));
      expect(harness.store.saved.single.status, TaskStatus.failed);
      await sub.cancel();
      await harness.dispose();
    });

    test('مهلة المهمة تُحسب فشلًا للمحاولة', () async {
      const options = TaskQueueOptions(
        maxAttempts: 1,
        taskTimeout: Duration(milliseconds: 40),
      );
      final harness = _Harness(options: options);
      harness.queue.registerHandler(
        'slow',
        (_) async => Future<void>.delayed(const Duration(milliseconds: 500)),
      );
      await harness.start();

      await harness.queue.enqueue(type: 'slow', payload: {});
      await until(() => harness.queue.failedCount == 1);

      expect(
        harness.queue.failedTasks.single.lastError,
        contains('TimeoutException'),
      );
      await harness.dispose();
    });

    test('معالج غائب فشل قابل للإعادة ثم ينجح بعد تسجيل المعالج', () async {
      final harness = _Harness(options: _Harness.fastOptions);
      var registered = false;
      harness.queue.registerHandler('late', (_) async {
        if (!registered) throw StateError('معالج مؤقت');
      });
      await harness.start();

      await harness.queue.enqueue(type: 'late', payload: {});
      await until(() => harness.queue.pendingTasks.single.attempts == 1);
      // سجّل معالجًا فعليًا قبل حلول إعادة المحاولة.
      harness.queue.registerHandler('late', (_) async {});
      registered = true;

      await until(() => harness.queue.pendingCount == 0);
      expect(harness.queue.failedCount, 0);
      await harness.dispose();
    });
  });

  group('التحكم اليدوي', () {
    test('removeTask تزيل المعلّقة وترفض قيد التنفيذ', () async {
      final harness = _Harness();
      final release = Completer<void>();
      var started = false;
      harness.queue.registerHandler('blocked', (_) async {
        started = true;
        await release.future;
      });
      await harness.start();

      final task = await harness.queue.enqueue(type: 'blocked', payload: {});
      await until(() => started);
      expect(await harness.queue.removeTask(task.id), isFalse);

      release.complete();
      await until(() => harness.queue.pendingCount == 0);

      // دون اتصال لا تبدأ الحلقة التنفيذ؛ الإزالة حتمية.
      harness.source.emit(const [ConnectivityResult.none]);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      final pending = await harness.queue.enqueue(type: 'x', payload: {});
      expect(await harness.queue.removeTask(pending.id), isTrue);
      expect(harness.queue.pendingCount, 0);
      await harness.dispose();
    });

    test('retryTask تعيد الفاشلة للتنفيذ وتنجح', () async {
      final harness = _Harness(options: _Harness.fastOptions);
      var shouldFail = true;
      harness.queue.registerHandler('recover', (_) async {
        if (shouldFail) throw Exception('فشل أولي');
      });
      await harness.start();

      final task = await harness.queue.enqueue(type: 'recover', payload: {});
      await until(() => harness.queue.failedCount == 1);
      shouldFail = false;

      expect(await harness.queue.retryTask(task.id), isTrue);
      await until(() => harness.queue.pendingCount == 0);
      expect(harness.queue.failedCount, 0);
      expect(await harness.queue.retryTask(task.id), isFalse);
      await harness.dispose();
    });

    test('clearFailed تحذف الفاشلات وتعيد عددها', () async {
      const options = TaskQueueOptions(
        maxAttempts: 1,
        initialRetryDelay: Duration(milliseconds: 10),
      );
      final harness = _Harness(options: options);
      harness.queue.registerHandler('fails', (_) async => throw Exception());
      await harness.start();

      await harness.queue.enqueue(type: 'fails', payload: {});
      await harness.queue.enqueue(type: 'fails', payload: {});
      await until(() => harness.queue.failedCount == 2);

      expect(await harness.queue.clearFailed(), 2);
      expect(harness.queue.failedCount, 0);
      expect(harness.store.saved, isEmpty);
      await harness.dispose();
    });
  });

  test('فشل حفظ المخزن لا يكسر الجلسة', () async {
    final harness = _Harness(store: FakeQueueStore(failOnSave: true));
    final executed = <String>[];
    harness.queue.registerHandler(
      'send_note',
      (payload) async => executed.add(payload['body'] as String),
    );
    await harness.start();

    await harness.queue.enqueue(type: 'send_note', payload: {'body': 'نص'});
    await until(() => executed.isNotEmpty);

    expect(executed, ['نص']);
    expect(harness.queue.pendingCount, 0);
    expect(harness.store.saveCount, greaterThan(0));
    await harness.dispose();
  });

  group('المخزن الافتراضي', () {
    // بيئة بلا مخزن محقون لتشغيل defaultStoreFactory نفسه.
    _Harness noStoreHarness() {
      final source = FakeConnectivitySource();
      final connection = ConnectionService(
        connectivitySource: source,
        options: const ConnectionOptions(disconnectDebounce: Duration.zero),
      );
      return _Harness._bare(source, connection);
    }

    tearDown(() {
      TaskQueueService.defaultStoreFactory = SharedPreferencesQueueStore.create;
    });

    test('فشل إنشاء مخزن القرص لا يجهض init والطابور يعمل في الذاكرة',
        () async {
      TaskQueueService.defaultStoreFactory = () async => throw Exception(
            'PlatformException(channel-error, Unable to establish '
            'connection on channel)',
          );
      final harness = noStoreHarness();
      final executed = <int>[];
      harness.queue.registerHandler(
        'sync',
        (payload) async => executed.add(payload['n'] as int),
      );
      await harness.connection.init();
      await harness.queue.init(); // لا يرمي رغم فشل المصنع.

      await harness.queue.enqueue(type: 'sync', payload: {'n': 1});
      await until(() => executed.isNotEmpty);

      expect(executed, [1]);
      expect(harness.queue.pendingCount, 0);
      await harness.dispose();
    });

    test('نجاح المصنع الافتراضي يستخدم المخزن الذي أنشأه', () async {
      final store = FakeQueueStore();
      TaskQueueService.defaultStoreFactory = () async => store;
      final harness = noStoreHarness();
      harness.queue.registerHandler('sync', (_) async {});
      await harness.connection.init();
      await harness.queue.init();

      await harness.queue.enqueue(type: 'sync', payload: {});
      await until(() => harness.queue.pendingCount == 0);

      expect(store.saveCount, greaterThan(0));
      await harness.dispose();
    });
  });
}
