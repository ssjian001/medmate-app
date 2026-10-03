/// 主页：今日时间轴 + 打卡（整卡可点/过时禁用/漏服检测）
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../models/medication.dart';
import '../services/db.dart';
import '../services/notify.dart';
import '../services/app_lock.dart';
import 'meds_page.dart';
import 'calendar_page.dart';
import '../services/exporter.dart';
import 'stats_page.dart';

class TodayPage extends StatefulWidget {
  const TodayPage({super.key});
  @override
  State<TodayPage> createState() => _TodayPageState();
}

class _TodayPageState extends State<TodayPage> with WidgetsBindingObserver {
  String _date = _today();
  List<Map<String, dynamic>> _doses = [];
  Map<int, Medication> _meds = {};
  bool _locked = true; // 未解锁时不渲染任何服药数据

  static String _today() {
    final n = DateTime.now();
    return '${n.year}-${n.month.toString().padLeft(2, '0')}-${n.day.toString().padLeft(2, '0')}';
  }

  static String _nowHm() =>
      DateTime.now().toIso8601String().substring(11, 16);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _bootstrap();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    final today = _today();
    if (today != _date) {
      // 跨零点: 回到前台已是新的一天, 换日期重拉当天计划 (不会自动补昨天)
      setState(() => _date = today);
    }
    if (_locked) return; // 锁定状态别偷偷拉数据
    _reload(); // 回前台刷新+查漏服
  }

  Future<void> _bootstrap() async {
    final unlocked = await AppLock.instance.ensureUnlocked(); // 隐私锁
    if (!mounted) return;
    if (!unlocked) {
      setState(() => _locked = true);
      return; // 认证失败 → 只显示锁定占位页
    }
    setState(() => _locked = false);
    // 通知权限引导（Android 13+ 运行时权限）
    final plugin = FlutterLocalNotificationsPlugin();
    final android = plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    final granted = await android?.areNotificationsEnabled();
    if (granted == false && mounted) {
      ScaffoldMessenger.of(context).showMaterialBanner(MaterialBanner(
        content: const Text('开启通知权限才能收到服药提醒'),
        actions: [
          TextButton(
            onPressed: () async {
              ScaffoldMessenger.of(context).clearMaterialBanners();
              await android?.requestNotificationsPermission();
              await Notify.instance.init();
              _reload();
            },
            child: const Text('去开启'),
          ),
          TextButton(
            onPressed: () => ScaffoldMessenger.of(context).clearMaterialBanners(),
            child: const Text('稍后'),
          ),
        ],
      ));
    }
    // 时区获取失败 → zonedSchedule 按 UTC 排程, 提醒整体偏移, 必须让用户知情
    await Notify.instance.init();
    if (Notify.instance.timezoneWarning && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('时区获取失败，提醒时间可能不准')),
      );
    }
    _reload();
  }

  Future<void> _reload() async {
    await Db.instance.ensurePlansFor(_date);
    final doses = await Db.instance.dosesForDay(_date);
    final meds = {for (final m in await Db.instance.allMeds()) m.id!: m};
    if (!mounted) return;
    setState(() {
      _doses = doses;
      _meds = meds;
    });
    _checkOverdue();
  }

  /// 漏服检测: 超 30 分钟未打卡的 pending → 本地通知提醒
  Future<void> _checkOverdue() async {
    final overdue = await Db.instance.overdue(graceMin: 30);
    for (final d in overdue) {
      final med = _meds[d['medication_id'] as int];
      if (med == null) continue;
      await Notify.instance.now(
          '漏服提醒',
          '${med.name} ${med.dosage} 计划 '
          '${(d['plan_time'] as String).substring(11, 16)} 还未打卡');
      await Db.instance.markNotified(d['id'] as int);
    }
  }

  Future<void> _mark(int id, bool skipped) async {
    await _markGroup([id], skipped);
  }

  Future<void> _markGroup(List<int> ids, bool skipped) async {
    for (final id in ids) {
      await Db.instance.markTaken(id, skipped: skipped);
    }
    await _reload();
    _checkLowStock();
  }

  /// 库存不足提醒（每轮只弹一次, 靠 lowStock 查询本身幂等）
  Future<void> _checkLowStock() async {
    final low = await Db.instance.lowStock(days: 3);
    for (final m in low) {
      await Notify.instance.now('库存不足',
          '${m['name']} 只剩 ${m['stock']?.toStringAsFixed(0)} 份, 记得补药');
      await Db.instance.markStockNotified(m['id'] as int);
    }
  }

  /// 撤销打卡（恢复 pending）
  Future<void> _undo(int id) async {
    await Db.instance.updateStatus(id, DoseStatus.pending);
    await _reload();
  }

  Future<void> _showGroupMenu(String planTime, List<Map<String, dynamic>> group) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Padding(padding: const EdgeInsets.all(12),
              child: Text('$planTime  共${group.length}种药',
                  style: Theme.of(ctx).textTheme.titleMedium)),
          ...group.map((d) {
            final med = _meds[d['medication_id'] as int];
            final st = d['status'] as int;
            return ListTile(
              leading: Icon(
                  st == 0 ? Icons.check_circle : st == 1 ? Icons.block : Icons.radio_button_unchecked,
                  color: st == 0 ? Colors.green : st == 1 ? Colors.grey : Colors.orange),
              title: Text(med?.name ?? '?'),
              trailing: st == 2
                  ? TextButton(onPressed: () {
                      Navigator.pop(ctx);
                      _mark(d['id'] as int, false);
                    }, child: const Text('服用'))
                  : TextButton(onPressed: () {
                      Navigator.pop(ctx);
                      _undo(d['id'] as int);
                    }, child: const Text('撤销')),
            );
          }),
        ]),
      ),
    );
    if (action == null) _reload();
  }

  Future<void> _showDoseMenu(Map<String, dynamic> d) async {
    final status = d['status'] as int;
    final med = _meds[d['medication_id'] as int];
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          if (status == 2) ...[
            ListTile(leading: const Icon(Icons.check_circle, color: Colors.green),
                title: const Text('标记已服用'),
                onTap: () => Navigator.pop(ctx, 'taken')),
            ListTile(leading: const Icon(Icons.close, color: Colors.grey),
                title: const Text('跳过这次'),
                onTap: () => Navigator.pop(ctx, 'skipped')),
          ] else
            ListTile(leading: const Icon(Icons.undo),
                title: const Text('撤销打卡'),
                onTap: () => Navigator.pop(ctx, 'undo')),
          ListTile(leading: const Icon(Icons.info_outline),
              title: Text('${med?.name ?? ''} 计划时间 '
                  '${(d['plan_time'] as String).substring(11, 16)}'),
              onTap: () => Navigator.pop(ctx)),
        ]),
      ),
    );
    switch (action) {
      case 'taken': await _mark(d['id'] as int, false);
      case 'skipped': await _mark(d['id'] as int, true);
      case 'undo': await _undo(d['id'] as int);
    }
  }

  Color _colorOf(String tag) => switch (tag) {
        'red' => Colors.red.shade300,
        'orange' => Colors.orange.shade300,
        'blue' => Colors.blue.shade300,
        'purple' => Colors.purple.shade300,
        _ => Colors.teal.shade300,
      };

  @override
  Widget build(BuildContext context) {
    final nowHm = _nowHm();
    return Scaffold(
      appBar: AppBar(title: const Text('MedMate 服药助手')),
      body: RefreshIndicator(
        onRefresh: _reload,
        child: _doses.isEmpty
            ? ListView(children: const [
                SizedBox(height: 120),
                Center(child: Text('还没有添加药物\n点右下角 💊 开始',
                    textAlign: TextAlign.center)),
              ])
            : Builder(builder: (context) {
                // 按 plan_time 分组: 同一时间点多药合一张卡
                final groups = <String, List<Map<String, dynamic>>>{};
                for (final d in _doses) {
                  groups.putIfAbsent(d['plan_time'] as String, () => []).add(d);
                }
                final times = groups.keys.toList()..sort();
                return ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: times.length,
                  itemBuilder: (context, i) {
                    final time = times[i].substring(11, 16);
                    final group = groups[times[i]]!;
                    final allDone = group.every((d) => d['status'] == 0);
                    final anySkipped = group.any((d) => d['status'] == 1);
                    final pending = group.where((d) => d['status'] == 2).toList();
                    final pastDue = !allDone && time.compareTo(nowHm) < 0;
                    return Card(
                      color: allDone
                          ? Colors.grey.shade100
                          : _colorOf(_meds[group.first['medication_id'] as int]
                                  ?.colorTag ?? 'teal')
                              .withValues(alpha: 0.15),
                      child: Column(children: [
                        ListTile(
                          onTap: () => _showGroupMenu(times[i], group),
                          leading: Text(time,
                              style: TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                  color: pastDue ? Colors.red : null)),
                          title: Text(group
                              .map((d) => _meds[d['medication_id'] as int]?.name ?? '?')
                              .join(' + ')),
                          subtitle: Text([
                            group
                                .map((d) {
                                  final m = _meds[d['medication_id'] as int];
                                  return [m?.dosage, m?.note]
                                      .whereType<String>()
                                      .where((s) => s.isNotEmpty)
                                      .join(' ');
                                })
                                .where((s) => s.isNotEmpty)
                                .toSet()
                                .join(' / '),
                            if (pastDue && !allDone) '⏰ 已过时间',
                          ].where((s) => s.isNotEmpty).join(' · ')),
                          trailing: allDone
                              ? const Icon(Icons.check_circle,
                                  color: Colors.green, size: 32)
                              : anySkipped && pending.isEmpty
                                  ? const Icon(Icons.block,
                                      color: Colors.grey, size: 28)
                                  : null,
                        ),
                        if (pending.isNotEmpty)
                          Padding(
                            padding:
                                const EdgeInsets.only(left: 72, right: 12, bottom: 10),
                            child: Row(children: [
                              FilledButton.icon(
                                  onPressed: () => _markGroup(
                                      pending.map((d) => d['id'] as int).toList(),
                                      false),
                                  icon: const Icon(Icons.done_all, size: 18),
                                  label: const Text('全部服用')),
                              const SizedBox(width: 10),
                              TextButton(
                                  onPressed: () => _showDoseMenu(pending.first),
                                  child: const Text('单独操作…')),
                            ]),
                          ),
                      ]),
                    );
                  },
                );
              }),
      ),
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          FloatingActionButton.small(
              heroTag: 'stats',
              onPressed: () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const StatsPage())),
              child: const Icon(Icons.insights)),
          const SizedBox(height: 10),
          FloatingActionButton.small(
              heroTag: 'calendar',
              onPressed: () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const CalendarPage())),
              child: const Icon(Icons.calendar_month)),
          const SizedBox(height: 10),
          FloatingActionButton.small(
              heroTag: 'export',
              onPressed: () async {
                try {
                  await Exporter.instance.shareCsv(days: 30);
                } catch (e) {
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      content: Text('导出失败: $e'),
                      backgroundColor: Colors.red));
                }
              },
              child: const Icon(Icons.ios_share)),
          const SizedBox(height: 10),
          FloatingActionButton.small(
              heroTag: 'meds',
              onPressed: () async {
                await Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const MedsPage()));
                _reload();
              },
              child: const Icon(Icons.medication)),
        ],
      ),
    );
  }
}
