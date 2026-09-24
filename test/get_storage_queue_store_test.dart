import 'dart:io';

import 'package:connectivity_kit/connectivity_kit.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_storage/get_storage.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

/// محاكي path_provider يوجّه get_storage إلى مجلد مؤقت حتى يعمل
/// في اختبارات الوحدة دون قنوات المنصة الحقيقية.
class _FakePathProvider extends PathProviderPlatform {
  _FakePathProvider(this._appDocsPath);

  final String _appDocsPath;

  @override
  Future<String?> getApplicationDocumentsPath() async => _appDocsPath;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    final dir = await Directory.systemTemp.createTemp('connectivity_kit_test');
    PathProviderPlatform.instance = _FakePathProvider(dir.path);
    await GetStorage.init('connectivity_kit');
  });

  tearDown(() async {
    await GetStorage('connectivity_kit').erase();
  });

  test('حفظ ثم تحميل يعيدان المهام كما هي', () async {
    final store = await GetStorageQueueStore.create();
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
    final store = await GetStorageQueueStore.create();
    expect(await store.load(), isEmpty);
  });

  test('الحفظ الفارغ يمسح ما سبق', () async {
    final store = await GetStorageQueueStore.create();
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
    final box = GetStorage('connectivity_kit');
    await box.write(
      'connectivity_kit.task_queue.v1',
      'ليست JSON صالحًا',
    );

    final store = GetStorageQueueStore(box);
    expect(await store.load(), isEmpty);
  });
}
