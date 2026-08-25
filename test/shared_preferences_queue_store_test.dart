import 'package:connectivity_kit/connectivity_kit.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('حفظ ثم تحميل يعيدان المهام كما هي', () async {
    final store = await SharedPreferencesQueueStore.create();
    final tasks = [
      QueuedTask(
        id: 'a',
        type: 'send_note',
        payload: const {'body': 'نص'},
        groupId: 'note_1',
        attempts: 1,
        maxAttempts: 3,
        nextAttemptAt: DateTime.fromMillisecondsSinceEpoch(1234),
        lastError: 'err',
        createdAt: DateTime.fromMillisecondsSinceEpoch(100),
      ),
      QueuedTask(
        id: 'b',
        type: 'sync',
        payload: const {},
        maxAttempts: 3,
        createdAt: DateTime.fromMillisecondsSinceEpoch(200),
        status: TaskStatus.failed,
      ),
    ];

    await store.save(tasks);
    final loaded = await store.load();

    expect(loaded, hasLength(2));
    expect(loaded.first.id, 'a');
    expect(loaded.first.groupId, 'note_1');
    expect(loaded.first.nextAttemptAt!.millisecondsSinceEpoch, 1234);
    expect(loaded.last.status, TaskStatus.failed);
  });

  test('التحميل بلا بيانات محفوظة يعيد قائمة فارغة', () async {
    final store = await SharedPreferencesQueueStore.create();
    expect(await store.load(), isEmpty);
  });

  test('الحفظ الفارغ يمسح ما سبق', () async {
    final store = await SharedPreferencesQueueStore.create();
    await store.save([
      QueuedTask(
        id: 'a',
        type: 'x',
        payload: const {},
        maxAttempts: 1,
        createdAt: DateTime.fromMillisecondsSinceEpoch(0),
      ),
    ]);
    await store.save([]);
    expect(await store.load(), isEmpty);
  });

  test('القراءة التالفة تُعيد قائمة فارغة دون رمي', () async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      'connectivity_kit.task_queue.v1',
      'ليست JSON صالحًا',
    );

    final store = SharedPreferencesQueueStore(prefs);
    expect(await store.load(), isEmpty);
  });
}
