// 通知服务：到点提醒（flutter_local_notifications + zonedSchedule）
library;

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tzdata;

class Notify {
  Notify._();
  static final Notify instance = Notify._();
  final _plugin = FlutterLocalNotificationsPlugin();
  bool _ready = false;

  /// 系统时区获取失败标记 (true = 提醒按 UTC 排程, 时间可能不准)
  /// UI 可在启动后读取此字段提示用户
  bool timezoneWarning = false;
  /// 每药物预留的时间点槽位数 (取消时按此范围全取消)
  static const int slotsPerMed = 20;
  /// 点击通知后的回调 (payload = 计划时间 'yyyy-MM-dd HH:mm')
  static void Function(String payload)? onNotificationTap;

  /// 提醒 id 生成规则: medId*100 + 时间点序号
  /// 调度与取消共用, 保证改时间点后旧提醒能被准确撤掉
  static int dailyId(int medId, int index) => medId * 100 + index;

  Future<void> init() async {
    if (_ready) return;
    tzdata.initializeTimeZones();
    try {
      // 不设本地时区的话 zonedSchedule 全按 UTC 算, 国内会差 8 小时
      final info = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(info.identifier));
    } catch (e) {
      // 取不到系统时区 (异常/平台不支持) → 保持 timezone 默认值, 不阻断启动
      // 但 zonedSchedule 会按 UTC 算, 提醒整体偏移 → 记日志+置标记让 UI 提示
      timezoneWarning = true;
      debugPrint('[Notify] 获取系统时区失败, 提醒时间可能不准: $e');
    }
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    await _plugin.initialize(
      const InitializationSettings(android: androidInit),
      onDidReceiveNotificationResponse: (resp) {
        final p = resp.payload;
        if (p != null && p.isNotEmpty) onNotificationTap?.call(p);
      },
    );
    _ready = true;
  }

  /// 立即通知（漏服/库存提醒），payload 携带计划时间
  Future<void> now(String title, String body, {String? payload}) async {
    await init();
    await _plugin.show(
      DateTime.now().millisecondsSinceEpoch % 0x7fffffff,
      title,
      body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          'medmate_urgent', '漏服提醒',
          importance: Importance.max, priority: Priority.high,
        ),
      ),
      payload: payload,
    );
  }

  /// 每日重复提醒（按药物的 time "HH:mm"）
  Future<void> scheduleDaily(
      int id, String hhmm, String title, String body, {String? payload}) async {
    await init();
    final parts = hhmm.split(':');
    if (parts.length < 2) return;
    final h = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    if (h == null || m == null) return;
    await _plugin.zonedSchedule(
      id, title, body,
      _nextInstanceOf(h, m),
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'medmate_daily', '服药提醒',
          importance: Importance.defaultImportance,
          priority: Priority.defaultPriority,
        ),
      ),
      payload: payload,
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      matchDateTimeComponents: DateTimeComponents.time,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
    );
  }

  /// 按药物的 times 重建每日提醒: 先取消旧的, 再按序号逐个排
  /// (时间点被删/被改时不会留下僵尸提醒)
  /// [customMsg] 为药物自定义提醒语, 留空则用 [body]
  Future<void> syncMed({
    required int medId,
    required List<String> times,
    required String title,
    required String body,
    String? customMsg,
  }) async {
    await cancelMed(medId);
    final today = DateTime.now().toIso8601String().substring(0, 10);
    final text = (customMsg != null && customMsg.isNotEmpty) ? customMsg : body;
    for (var i = 0; i < times.length && i < slotsPerMed; i++) {
      final t = times[i];
      try {
        await scheduleDaily(dailyId(medId, i), t, title, '$text · $t',
            payload: '$today $t');
      } catch (_) {
        // 单个时间点排程失败不影响其它时间点
      }
    }
  }

  /// 取消某药物的全部提醒 (时间点数量可能变过, 按槽位范围全取消)
  Future<void> cancelMed(int medId) async {
    await init();
    for (var i = 0; i < slotsPerMed; i++) {
      await _plugin.cancel(dailyId(medId, i));
    }
  }

  Future<void> cancel(int id) async {
    await _plugin.cancel(id);
  }

  tz.TZDateTime _nextInstanceOf(int h, int m) {
    final now = tz.TZDateTime.now(tz.local);
    var t = tz.TZDateTime(tz.local, now.year, now.month, now.day, h, m);
    if (t.isBefore(now)) t = t.add(const Duration(days: 1));
    return t;
  }
}
