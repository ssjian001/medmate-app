// 通知服务：到点提醒（flutter_local_notifications + zonedSchedule）
library;

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tzdata;

class Notify {
  Notify._();
  static final Notify instance = Notify._();
  final _plugin = FlutterLocalNotificationsPlugin();
  bool _ready = false;
  /// 点击通知后的回调 (payload = 计划时间 'yyyy-MM-dd HH:mm')
  static void Function(String payload)? onNotificationTap;

  Future<void> init() async {
    if (_ready) return;
    tzdata.initializeTimeZones();
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
  Future<void> scheduleDaily(int id, String hhmm, String title, String body) async {
    await init();
    final h = int.parse(hhmm.split(':')[0]);
    final m = int.parse(hhmm.split(':')[1]);
    await _plugin.zonedSchedule(
      id, title, body,
      _nextInstanceOf(h, m),
      // payload 由调用方通过 routeTo 设置
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'medmate_daily', '服药提醒',
          importance: Importance.defaultImportance,
          priority: Priority.defaultPriority,
        ),
      ),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      matchDateTimeComponents: DateTimeComponents.time,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
    );
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
