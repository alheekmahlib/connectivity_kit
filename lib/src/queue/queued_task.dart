import 'package:flutter/foundation.dart';

/// حالة المهمة في الطابور. حالة «قيد التنفيذ» ذاكرة عابرة داخل الخدمة
/// ولا تُخزَّن على القرص؛ مهمة كانت جارية عند إغلاق التطبيق تُحمَّل
/// عند الإقلاع التالي كمعلّقة.
enum TaskStatus {
  /// في انتظار توفر الاتصال أو حلول موعد المحاولة التالية.
  pending,

  /// فشلت نهائيًا بعد نفاد محاولاتها؛ تبقى محفوظة للفحص أو إعادة الجدولة.
  failed,
}

/// مهمة واحدة في طابور الأعمال التي تحتاج اتصالًا بالإنترنت.
///
/// المهمة بيانات قابلة للتسلسل بالكامل لتنجو من إغلاق التطبيق؛ التنفيذ
/// الفعلي مسؤولية معالج يُسجَّله التطبيق باسم [type].
@immutable
class QueuedTask {
  const QueuedTask({
    required this.id,
    required this.type,
    required this.payload,
    this.groupId,
    this.attempts = 0,
    required this.maxAttempts,
    this.nextAttemptAt,
    this.lastError,
    required this.createdAt,
    this.status = TaskStatus.pending,
  });

  /// يُنشئ مهمة من تمثيل JSON المخزَّن على القرص؛ الحقول الغائبة أو
  /// التالفة تُستبدل بقيم افتراضية بدل الرمي.
  factory QueuedTask.fromJson(Map<String, dynamic> json) => QueuedTask(
        id: json['id'] as String? ?? '',
        type: json['type'] as String? ?? '',
        payload: (json['payload'] as Map<String, dynamic>?) ?? const {},
        groupId: json['groupId'] as String?,
        attempts: (json['attempts'] as num?)?.toInt() ?? 0,
        maxAttempts: (json['maxAttempts'] as num?)?.toInt() ?? 1,
        nextAttemptAt: json['nextAttemptAt'] == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(
                (json['nextAttemptAt'] as num).toInt(),
              ),
        lastError: json['lastError'] as String?,
        createdAt: json['createdAt'] == null
            ? DateTime.fromMillisecondsSinceEpoch(0)
            : DateTime.fromMillisecondsSinceEpoch(
                (json['createdAt'] as num).toInt(),
              ),
        status: json['status'] == TaskStatus.failed.name
            ? TaskStatus.failed
            : TaskStatus.pending,
      );

  /// معرّف فريد للمهمة داخل هذا الجهاز.
  final String id;

  /// نوع المهمة؛ يجب أن يطابق اسم معالج مسجَّل (مثل `send_note`).
  final String type;

  /// بيانات المهمة؛ يجب أن تكون قابلة للتسلسل إلى JSON (مسؤولية التطبيق).
  final Map<String, dynamic> payload;

  /// مفتاح دمج اختياري: مهمة جديدة بنفس المفتاح تحلّ محلّ المعلّقة الأقدم.
  final String? groupId;

  /// عدد المحاولات المنفَّذة حتى الآن.
  final int attempts;

  /// الحد الأقصى للمحاولات قبل اعتبار المهمة فاشلة نهائيًا.
  final int maxAttempts;

  /// أقرب وقت مسموح للمحاولة التالية (تأجيل بعد فشل)، أو null للتنفيذ فورًا.
  final DateTime? nextAttemptAt;

  /// نص آخر خطأ (مقتطع) للتشخيص؛ لا يُستخدم في أي منطق تنفيذ.
  final String? lastError;

  /// وقت إضافة المهمة إلى الطابور.
  final DateTime createdAt;

  /// الحالة الحالية.
  final TaskStatus status;

  /// أقصى طول محفوظ لـ [lastError].
  static const int maxErrorLength = 500;

  /// قيمة حارسة للحقول القابلة للتصفير في [copyWith].
  static const Object _unset = Object();

  /// نسخة معدَّلة؛ يسمح [nextAttemptAt] و[lastError] بتمرير null صراحةً
  /// لتصفييرهما بفضل القيمة الحارسة.
  QueuedTask copyWith({
    int? attempts,
    TaskStatus? status,
    Object? nextAttemptAt = _unset,
    Object? lastError = _unset,
  }) =>
      QueuedTask(
        id: id,
        type: type,
        payload: payload,
        groupId: groupId,
        attempts: attempts ?? this.attempts,
        maxAttempts: maxAttempts,
        nextAttemptAt: nextAttemptAt == _unset
            ? this.nextAttemptAt
            : nextAttemptAt as DateTime?,
        lastError: lastError == _unset ? this.lastError : lastError as String?,
        createdAt: createdAt,
        status: status ?? this.status,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'type': type,
        'payload': payload,
        if (groupId != null) 'groupId': groupId,
        'attempts': attempts,
        'maxAttempts': maxAttempts,
        if (nextAttemptAt != null)
          'nextAttemptAt': nextAttemptAt!.millisecondsSinceEpoch,
        if (lastError != null) 'lastError': lastError,
        'createdAt': createdAt.millisecondsSinceEpoch,
        'status': status.name,
      };
}
