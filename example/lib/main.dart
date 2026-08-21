import 'package:connectivity_kit/connectivity_kit.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 1) أنشئ الخدمة وتهيّئها (مع فحص الوصول الفعلي هنا كمثال)
  final service = InternetConnectionService(
    options: const InternetConnectionOptions(enableReachability: true),
  );
  await service.init();

  // 2) سجّلها ثم سجّل الوسيط في GetX
  Get.put(service, permanent: true);
  Get.put(InternetConnectionController(), permanent: true);

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return GetMaterialApp(
      title: 'connectivity_kit example',
      home: Scaffold(
        appBar: AppBar(title: const Text('connectivity_kit')),
        body: Center(
          // 3) رابط الواجهة بالحالة عبر Obx
          child: Obx(() {
            final controller = InternetConnectionController.instance;
            final IconData icon;
            final String label;
            switch (controller.connectionStatus.value) {
              case ConnectivityStatus.wifi:
                icon = Icons.wifi;
                label = 'متصل عبر شبكة واسعة النطاق';
              case ConnectivityStatus.cellular:
                icon = Icons.cell_tower;
                label = 'متصل عبر بيانات الجوال';
              case ConnectivityStatus.offline:
                icon = Icons.wifi_off;
                label = 'لا يوجد اتصال';
            }
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  icon,
                  size: 64,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(height: 12),
                Text(label),
              ],
            );
          }),
        ),
      ),
    );
  }
}
