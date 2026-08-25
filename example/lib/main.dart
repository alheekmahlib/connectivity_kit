import 'dart:async';

import 'package:connectivity_kit/connectivity_kit.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

/// مصدر اتصال تجريبي قابل للتبديل من الواجهة بدل قنوات المنصة،
/// لعرض سلوك الطابور الحقيقي دون الحاجة لقطع الشبكة فعلًا.
class DemoConnectivitySource implements ConnectivitySource {
  final _controller = StreamController<List<ConnectivityResult>>.broadcast();

  List<ConnectivityResult> current = const [ConnectivityResult.wifi];

  @override
  Stream<List<ConnectivityResult>> get onConnectivityChanged =>
      _controller.stream;

  @override
  Future<List<ConnectivityResult>> checkConnectivity() async => current;

  void setOnline(bool online) {
    current = online
        ? const [ConnectivityResult.wifi]
        : const [ConnectivityResult.none];
    _controller.add(current);
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 1) خدمة مراقبة الاتصال بمصدر تجريبي قابل للتبديل
  final source = DemoConnectivitySource();
  Get.put(source, permanent: true);
  final service = ConnectionService(
    connectivitySource: source,
    options: const ConnectionOptions(disconnectDebounce: Duration.zero),
  );
  await service.init();
  Get.put(service, permanent: true);
  Get.put(ConnectionController(), permanent: true);

  // 2) طابور المهام دون اتصال: سجّل المعالجات قبل init
  final queue = TaskQueueService(connectionService: service);
  queue.registerHandler('send_note', (payload) async {
    // محاكاة نداء شبكة يستغرق وقتًا؛ في تطبيق حقيقي هذا dio/http.
    await Future<void>.delayed(const Duration(milliseconds: 800));
  });
  await queue.init();
  Get.put(queue, permanent: true);
  Get.put(TaskQueueController(), permanent: true);

  // 3) أحداث الطابور → إشعارات المستخدم (مسؤولية التطبيق المستهلك)
  queue.events.listen((event) {
    switch (event) {
      case QueueTaskSucceeded():
        Get.snackbar('تم الإرسال', 'وصلت "${event.task.payload['title']}"');
      case QueueTaskFailedPermanently():
        Get.snackbar(
          'فشل الإرسال',
          'تعذّر إرسال "${event.task.payload['title']}"',
        );
      case QueueTaskEnqueued() || QueueTaskRetrying() || QueueDrained():
        break;
    }
  });

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return GetMaterialApp(
      title: 'connectivity_kit example',
      theme: ThemeData(useMaterial3: true),
      home: const HomeView(),
    );
  }
}

class HomeView extends StatelessWidget {
  const HomeView({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('connectivity_kit')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: const [
          _ConnectionCard(),
          SizedBox(height: 12),
          _QueueDemoCard(),
        ],
      ),
    );
  }
}

class _ConnectionCard extends StatelessWidget {
  const _ConnectionCard();

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Obx(() {
          final controller = ConnectionController.instance;
          final (icon, label) = switch (controller.connectionStatus.value) {
            ConnectivityStatus.wifi => (
                Icons.wifi,
                'متصل عبر شبكة واسعة النطاق'
              ),
            ConnectivityStatus.cellular => (
                Icons.cell_tower,
                'متصل عبر بيانات الجوال'
              ),
            ConnectivityStatus.offline => (Icons.wifi_off, 'لا يوجد اتصال'),
          };
          return Column(
            children: [
              Icon(icon,
                  size: 48, color: Theme.of(context).colorScheme.primary),
              const SizedBox(height: 8),
              Text(label),
            ],
          );
        }),
      ),
    );
  }
}

class _QueueDemoCard extends StatelessWidget {
  const _QueueDemoCard();

  @override
  Widget build(BuildContext context) {
    final source = Get.find<DemoConnectivitySource>();
    final queue = Get.find<TaskQueueService>();
    final controller = TaskQueueController.instance;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('طابور المهام دون اتصال',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            const Text(
              'جرّب: اقطع الاتصال ثم أرسل ملاحظات — تبقى في الطابور محفوظة، '
              'وأعد الاتصال لتُرسل تلقائيًا في الخلفية دون تدخّلك.',
            ),
            const SizedBox(height: 12),
            Obx(() {
              final online = ConnectionController.instance.isOnline;
              return SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(online ? 'الاتصال: متصل' : 'الاتصال: مقطوع'),
                value: online,
                // يبدّل مصدر الاتصال التجريبي؛ الطابور يستأنف تلقائيًا
                onChanged: source.setOnline,
              );
            }),
            const SizedBox(height: 4),
            Obx(() {
              return Wrap(
                spacing: 8,
                children: [
                  Chip(
                    avatar: const Icon(Icons.schedule, size: 18),
                    label: Text('معلّقة: ${controller.pendingCount.value}'),
                  ),
                  Chip(
                    avatar: const Icon(Icons.error_outline, size: 18),
                    label: Text('فاشلة: ${controller.failedCount.value}'),
                  ),
                ],
              );
            }),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: () {
                final noteId = DateTime.now().millisecondsSinceEpoch % 1000;
                queue.enqueue(
                  type: 'send_note',
                  payload: {'title': 'ملاحظة $noteId', 'body': 'نص تجريبي'},
                  // groupId يجعل تعديل الملاحظة نفسها لاحقًا يحلّ محلّ القديمة
                  groupId: 'note_$noteId',
                );
              },
              icon: const Icon(Icons.send_outlined),
              label: const Text('إرسال ملاحظة'),
            ),
            Obx(() {
              if (controller.failedCount.value == 0) return const SizedBox();
              return OutlinedButton.icon(
                onPressed: () => controller.clearFailed(),
                icon: const Icon(Icons.delete_outline),
                label: const Text('حذف الفاشلة'),
              );
            }),
          ],
        ),
      ),
    );
  }
}
