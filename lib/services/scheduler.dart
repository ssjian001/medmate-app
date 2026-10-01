/// 提醒调度器: 保存/删除药物时同步系统通知计划
import 'notify.dart';
import '../models/medication.dart';

class NotificationScheduler {
  NotificationScheduler._();

  /// 稳定 ID: medId*100 + 时间点序号 (每药最多99个时间点)
  static int _id(int medId, int idx) => medId * 100 + idx;

  static Future<void> reschedule(int medId, Medication m) async {
    await cancelAll(medId);
    if (!m.active) return;
    for (var i = 0; i < m.times.length && i < 99; i++) {
      final body = m.customMsg.isNotEmpty
          ? '${m.customMsg} (${m.name} ${m.dosage})'
          : '该吃 ${m.name} ${m.dosage} 了';
      await Notify.instance.scheduleDaily(
          _id(medId, i), m.times[i], '服药提醒', body);
    }
  }

  static Future<void> cancel(int medId) async {
    for (var i = 0; i < 99; i++) {
      await Notify.instance.cancel(_id(medId, i));
    }
  }

  static Future<void> cancelAll(int medId) => cancel(medId);
}

// tz 引用防未使用告警(时区在 Notify.init 里设)
// ignore: unused_import
