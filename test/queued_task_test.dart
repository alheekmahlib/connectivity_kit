import 'package:connectivity_kit/connectivity_kit.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('toJson/fromJson ذهابًا وإيابًا بكل الحقول', () {
    final task = QueuedTask(
      id: 't-1',
      type: 'send_note',
      payload: const {'body': 'نص', 'n': 3},
      groupId: 'note_42',
      attempts: 2,
      maxAttempts: 3,
      nextAttemptAt: DateTime.fromMillisecondsSinceEpoch(1700000000123),
      lastError: 'خطأ ما',
      createdAt: DateTime.fromMillisecondsSinceEpoch(1600000000456),
      status: TaskStatus.pending,
    );

    final restored = QueuedTask.fromJson(task.toJson());

    expect(restored.id, task.id);
    expect(restored.type, task.type);
    expect(restored.payload, task.payload);
    expect(restored.groupId, 'note_42');
    expect(restored.attempts, 2);
    expect(restored.maxAttempts, 3);
    expect(
      restored.nextAttemptAt!.millisecondsSinceEpoch,
      1700000000123,
    );
    expect(restored.lastError, 'خطأ ما');
    expect(
      restored.createdAt.millisecondsSinceEpoch,
      1600000000456,
    );
    expect(restored.status, TaskStatus.pending);
  });

  test('الحقول الفارغة تُحذف من JSON وتُسترد null', () {
    final task = QueuedTask(
      id: 't-2',
      type: 'sync',
      payload: const {},
      maxAttempts: 2,
      createdAt: DateTime.fromMillisecondsSinceEpoch(0),
    );

    final json = task.toJson();
    expect(json.containsKey('groupId'), isFalse);
    expect(json.containsKey('nextAttemptAt'), isFalse);
    expect(json.containsKey('lastError'), isFalse);

    final restored = QueuedTask.fromJson(json);
    expect(restored.groupId, isNull);
    expect(restored.nextAttemptAt, isNull);
    expect(restored.lastError, isNull);
  });

  test('الحالة الفاشلة تُحفظ وتُسترد', () {
    final task = QueuedTask(
      id: 't-3',
      type: 'x',
      payload: const {},
      maxAttempts: 1,
      createdAt: DateTime.fromMillisecondsSinceEpoch(0),
      status: TaskStatus.failed,
    );
    expect(
      QueuedTask.fromJson(task.toJson()).status,
      TaskStatus.failed,
    );
  });

  test('fromJson متسامح مع الحقول الغائبة والمجهولة', () {
    final restored = QueuedTask.fromJson({
      'id': 't-4',
      'type': 'y',
      'unknown_field': true,
    });

    expect(restored.attempts, 0);
    expect(restored.maxAttempts, 1);
    expect(restored.payload, isEmpty);
    expect(restored.status, TaskStatus.pending);
    expect(restored.createdAt.millisecondsSinceEpoch, 0);
  });

  test('copyWith يعدّل ويصفّر الحقول القابلة للتصفير صراحةً', () {
    final task = QueuedTask(
      id: 't-5',
      type: 'x',
      payload: const {},
      maxAttempts: 3,
      createdAt: DateTime.fromMillisecondsSinceEpoch(0),
      nextAttemptAt: DateTime.fromMillisecondsSinceEpoch(1),
      lastError: 'قديم',
    );

    final updated = task.copyWith(
      attempts: 1,
      nextAttemptAt: DateTime.fromMillisecondsSinceEpoch(2),
      lastError: 'جديد',
    );
    expect(updated.attempts, 1);
    expect(updated.nextAttemptAt!.millisecondsSinceEpoch, 2);
    expect(updated.lastError, 'جديد');
    expect(updated.id, task.id);

    final cleared = updated.copyWith(nextAttemptAt: null, lastError: null);
    expect(cleared.nextAttemptAt, isNull);
    expect(cleared.lastError, isNull);
    // الحقول غير الممرَّرة تبقى كما هي
    expect(cleared.attempts, 1);
    expect(cleared.id, task.id);
  });
}
