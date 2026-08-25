# تصميم ميزة الطابور دون اتصال — Offline Task Queue

- التاريخ: 2026-08-24
- الحزمة: connectivity_kit (من 0.1.1 إلى 0.2.0)
- الحالة: معتمد بعد جلسة brainstorming + grilling

## المشكلة

المستخدم يكتب ملاحظة في تطبيق بلا إنترنت فيفشل الإرسال وتضيع العملية أو تتطلب
تدخلًا يدويًا. المطلوب: أي عملية تحتاج إنترنت (إرسال، مزامنة، ...) تُضاف إلى
طابور محفوظ، ويُستأنف تنفيذها تلقائيًا في الخلفية عند عودة الاتصال أو عند فتح
التطبيق لاحقًا، دون تدخل المستخدم.

## القرارات المعتمدة

| المحور | القرار |
| --- | --- |
| بقاء المهام | تنجو من إغلاق التطبيق (مهام قابلة للتسلسل + معالجات تُسجَّل عند الإقلاع) |
| التخزين | واجهة `QueueStore` قابلة للحقن + تنفيذ افتراضي `shared_preferences` (JSON بمفتاح واحد مُصدَر) |
| سياسة الفشل | 3 محاولات (قابلة للضبط)، backoff تصاعدي 5s→10s→20s بحد 60s، ثم `failed` نهائية محفوظة + حدث |
| التنفيذ | تسلسلي FIFO صارم، مهلة مهمة 30s (مهمة معلّقة لا تحجب من خلفها) |
| تأجيل المعاد | مهمة فاشلة وبقي لها محاولات تبقى بموقعها مع طابع `nextAttemptAt` ولا تحجب من بعدها |
| الدمج | `groupId` اختياري: الأحدث تحل محل المعلّقة الأقدم بنفس المفتاح (latest-wins) |
| معالج غائب | يُعامل كفشل عادي يُحسب محاولة (يرحم الإقلاع البطيء للتطبيقات) |
| واجهة GetX | `TaskQueueController` فقط: `pendingCount/failedCount/isDraining` كـ Rx — بلا widgets |
| سقف الطابور | بلا سقف في v1 (تنبيه web/localStorage موثق فقط) |
| الخصوصية | التخزين الافتراضي غير مشفّر — تحذير موثّق + الواجهة القابلة للحقن مسار التشفير |

## المعمارية

خدمة طابور مستقلة بنمط المكتبة القائم (حقن تبعيات + `Default*` للافتراضي)؛
مستهلكو المراقبة فقط لا يتأثرون بأي تغيير.

```
التطبيق
  ├─▶ ConnectionService          (مراقبة — كما هي بلا تغيير)
  │         │ connectionStream
  │         ▼
  ├─▶ TaskQueueService           (محرك الطابور)
  │       ├─ QueueStore (حقن)
  │       │    └─ SharedPreferencesQueueStore (افتراضي)
  │       └─ handlers: {'send_note': TaskHandler, ...}
  │
  └─▶ TaskQueueController        (GetX — اختياري للواجهة)
```

### الملفات

```
lib/src/queue/
  queued_task.dart                   النموذج + التسلسل
  task_handler.dart                  typedef TaskHandler
  queue_store.dart                   واجهة التخزين
  shared_preferences_queue_store.dart التنفيذ الافتراضي
  task_queue_service.dart            المحرك + الخيارات + الأحداث
  task_queue_controller.dart         غلاف GetX
```

## المكونات

### QueuedTask

- `id`: توليد داخلي (microtimestamp + عدّاد أحادي) — بلا تبعية uuid.
- `type`: اسم النوع يطابق معالجًا مسجلًا (مثل `send_note`).
- `payload`: `Map<String, dynamic>` قابلة للتسلسل JSON (مسؤولية التطبيق).
- `groupId?`: مفتاح الدمج (latest-wins على المعلّقة فقط).
- `attempts` / `maxAttempts` / `nextAttemptAt?` / `lastError?` (مقتطع 500 حرف).
- `createdAt`، و`TaskStatus { pending, failed }` — حالة `running` ذاكرة عابرة فقط.
- `copyWith` + `toJson/fromJson`.

### TaskHandler

```dart
typedef TaskHandler = Future<void> Function(Map<String, dynamic> payload);
```

الدالة تملك آثارها الجانبية (تحديث قاعدة بيانات التطبيق مثلًا)؛ لا قيمة إرجاع.

### QueueStore

```dart
abstract interface class QueueStore {
  Future<List<QueuedTask>> load();
  Future<void> save(List<QueuedTask> tasks);
}
```

`SharedPreferencesQueueStore`: يُنشأ بمثيل محقون أو عبر `create()` غير المتزامن؛
يخزن `{"version":1,"tasks":[...]}` تحت `connectivity_kit.task_queue.v1`؛
القراءة التالفة تُعيد قائمة فارغة (لا رمي).

### TaskQueueService

- المُنشئ: `ConnectionService?` (وإلا `Get.find` مع `StateError` عربي واضح
  بالأسماء الحالية)، `QueueStore?` (افتراضي `SharedPreferencesQueueStore`
  يُنشأ داخل `init`)، `TaskQueueOptions`.
- `TaskQueueOptions` (const): `maxAttempts=3`، `initialRetryDelay=5s`،
  `retryDelayFactor=2`، `maxRetryDelay=60s`، `taskTimeout=30s`.
- `init()` (idempotent): تحميل المحفوظ، الاشتراك في `connectionStream`،
  بدء الحلقة إن كان متصلًا.
- `enqueue({type, payload, groupId?})`: استبدال بنفس groupId (معلّقة فقط) ثم
  إلحاق، حفظ فوري، بث `QueueTaskEnqueued`، إيقاظ الحلقة.
- حلقة `_drainLoop` تسلسلية: حرس `_draining` + إيقاظ بمُكمِّل (Completer) عند
  enqueue/عودة الاتصال؛ مهمة فاشلة تُؤجَّل بـ `nextAttemptAt` وتتخطاها الحلقة
  وتتنفذ من بعدها ثم توقف الحلقة نفسها حتى أقرب تأجيل أو حدث جديد.
- التنفيذ بمهلة عبر `Future.timeout(taskTimeout)` — المهلة تُحسب فشلًا.
- الأحداث (sealed): `QueueTaskEnqueued` / `QueueTaskSucceeded` /
  `QueueTaskRetrying(attempt, error)` / `QueueTaskFailedPermanently(error)`
  على بث broadcast.
- الاستعلام: `pendingTasks` / `failedTasks` / `pendingCount` / `failedCount` /
  `isDraining`.
- التحكم: `removeTask(id)` (غير القابلة للإزالة أثناء التنفيذ — false)،
  `retryTask(id)` (فاشلة → معلقة كأنها جديدة بآخر الطابور)، `clearFailed()`.
- `dispose()` آمن قبل init وبعده: يلغي الاشتراك، يوقظ الحلقة لتتوقف، ينتظر
  الجاري (محدود بالمهلة أصلًا)، يحفظ، يغلق البث.

### TaskQueueController

بنمط `ConnectionController` تمامًا: مُنشئ بحقن أو `Get.find` + رسالة خطأ
واضحة، `instance` (find أو put permanent)، `RxInt pendingCount/failedCount`
و`RxBool isDraining` تُزامَن من أحداث الخدمة وأيضا بعد استدعاءات التحكم عبر
passthrough بسيطة. لا snackbars ولا widgets.

## سير الاستهلاك النموذجي

```dart
final connection = ConnectionService();
await connection.init();
Get.put(connection, permanent: true);

final queue = TaskQueueService(connectionService: connection);
queue.registerHandler('send_note', (payload) async {
  await api.post('/notes', body: payload);
});
await queue.init();
Get.put(queue, permanent: true);

// عند أي إرسال (متصلًا أو لا):
await queue.enqueue(
  type: 'send_note',
  payload: {'title': '...', 'body': '...'},
  groupId: 'note_42',
);
```

## معالجة الأخطاء

- فشل حفظ المخزن: `debugPrint` + استمرار الجلسة في الذاكرة.
- استثناء المعالج: يُحسب محاولة، رسالته في `lastError` المقتطعة.
- مهلة المهمة: `TimeoutException` يُحسب محاولة.
- معالج غائب: فشل قابل للإعادة (يرحم تسجيل المعالجات المتأخر).
- حمولة غير قابلة للتسلسل: عقد موثق على التطبيق (تخزين JSON).

## الاختبارات

- fakes يدوية بلا mocktail، موحدة في `test/helpers/fakes.dart`
  (نقل المكرر + `FakeQueueStore` بخيار فشل الحفظ).
- `task_queue_service_test.dart`: خدمة اتصال حقيقية بـ `FakeConnectivitySource`.
  الحالات: enqueue دون اتصال يبقى pending محفوظًا؛ عودة الاتصال تستأنف؛
  الترتيب FIFO؛ الفشل → إعادة بمحاولة وbackoff؛ نفاد المحاولات → failed محفوظة
  + حدث؛ retryTask؛ استبدال groupId؛ المهلة فشل؛ معالج غائب قابل للإعادة؛
  removeTask/clearFailed؛ فشل الحفظ لا يكسر الجلسة؛ dispose قبل init آمن.
- `shared_preferences_queue_store_test.dart`: بمحاكاة
  `SharedPreferences.setMockInitialValues` — حفظ/تحميل/قراءة تالفة.
- `task_queue_controller_test.dart`: انعكاس التقدم في قيم Rx.
- `queued_task_test.dart`: تسلسل JSON ذهابًا وإيابًا (groupId=null، مقتطع الخطأ).

## التوثيق والترقية

- pubspec: `shared_preferences: ^2.2.0` + version 0.2.0.
- CHANGELOG: إدخال 0.1.1 المفقود (إعادة التسمية) + إدخال 0.2.0.
- README: تصحيح الأسماء القديمة `InternetConnection*` إلى `Connection*`،
  تحديث مرجع التثبيت، قسم كامل للطابور (التسجيل، enqueue، الأحداث، الخيارات،
  المخزن المخصص للبيانات الحساسة، تنبيه web/localStorage، تحذير عدم التشفير).
- توسيع example بتجربة إرسال ملاحظة دون اتصال.

## خارج النطاق (مؤجل بقرار)

- التشغيل الخلفي النظامي عبر workmanager (تنفيذ عند إغلاق التطبيق كليًا).
- سقف عدد المهام، تأجيل المهام الثقيلة على cellular، التنفيذ المتوازي.
- ترحيل التطبيقات المستهلكة إلى الاعتمادية الجديدة.
