/// 日历视图：月历打卡热图，点日期看当天详情
import 'package:flutter/material.dart';

import '../services/db.dart';
import '../models/medication.dart';

class CalendarPage extends StatefulWidget {
  const CalendarPage({super.key});
  @override
  State<CalendarPage> createState() => _CalendarPageState();
}

class _CalendarPageState extends State<CalendarPage> {
  late DateTime _month;
  Map<String, Map<String, int>> _heat = {};
  Map<int, Medication> _meds = {};
  String? _selectedDay;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _month = DateTime(now.year, now.month);
    _load();
  }

  String get _ym =>
      '${_month.year}-${_month.month.toString().padLeft(2, '0')}';

  Future<void> _load() async {
    final heat = await Db.instance.calendarMonth(_ym);
    final meds = {for (final m in await Db.instance.allMeds(onlyActive: false)) m.id!: m};
    if (!mounted) return;
    setState(() {
      _heat = heat;
      _meds = meds;
    });
  }

  Color _dayColor(Map<String, int>? h) {
    if (h == null) return Colors.transparent;
    final total = h['total'] ?? 0;
    if (total == 0) return Colors.grey.shade200;
    final rate = (h['taken'] ?? 0) / total;
    if (rate >= 0.999) return Colors.green.shade400;
    if (rate >= 0.5) return Colors.orange.shade300;
    return Colors.red.shade300;
  }

  Future<void> _pickDay(String day) async {
    setState(() => _selectedDay = _ym == day.substring(0, 7) ? day : _selectedDay);
    if (_selectedDay != day) setState(() => _selectedDay = day);
    final doses = await Db.instance.dosesForDay(day);
    final meds = {for (final m in await Db.instance.allMeds(onlyActive: false)) m.id!: m};
    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(12),
          shrinkWrap: true,
          children: [
            Text('详细记录 $day',
                style: Theme.of(ctx).textTheme.titleMedium,
                textAlign: TextAlign.center),
            const SizedBox(height: 8),
            ...doses.map((d) {
              final med = meds[d['medication_id'] as int];
              final st = d['status'] as int;
              return ListTile(
                dense: true,
                leading: Icon(
                    st == 0 ? Icons.check_circle
                    : st == 1 ? Icons.block : Icons.schedule,
                    color: st == 0 ? Colors.green : st == 1 ? Colors.grey : Colors.orange),
                title: Text('${(d['plan_time'] as String).substring(11, 16)} ${med?.name ?? '?'}'),
                trailing: Text(st == 0 ? '已服' : st == 1 ? '跳过' : '未记录',
                    style: TextStyle(
                        color: st == 0 ? Colors.green
                        : st == 1 ? Colors.grey : Colors.orange)),
              );
            }),
            if (doses.isEmpty) const Padding(
                padding: EdgeInsets.all(20),
                child: Center(child: Text('当天无记录'))),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final first = DateTime(_month.year, _month.month, 1);
    final daysInMonth = DateTime(_month.year, _month.month + 1, 0).day;
    final leadBlank = (first.weekday - 1) % 7; // 周一开头
    final today = DateTime.now();
    final todayStr = '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';

    return Scaffold(
      appBar: AppBar(
        title: Text('${_month.year}年${_month.month}月'),
        actions: [
          IconButton(icon: const Icon(Icons.chevron_left), onPressed: () {
            setState(() => _month = DateTime(_month.year, _month.month - 1));
            _load();
          }),
          IconButton(icon: const Icon(Icons.chevron_right), onPressed: () {
            setState(() => _month = DateTime(_month.year, _month.month + 1));
            _load();
          }),
        ],
      ),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: const Row(children: [
            Expanded(child: Center(child: Text('一', style: TextStyle(color: Colors.grey)))),
            Expanded(child: Center(child: Text('二', style: TextStyle(color: Colors.grey)))),
            Expanded(child: Center(child: Text('三', style: TextStyle(color: Colors.grey)))),
            Expanded(child: Center(child: Text('四', style: TextStyle(color: Colors.grey)))),
            Expanded(child: Center(child: Text('五', style: TextStyle(color: Colors.grey)))),
            Expanded(child: Center(child: Text('六', style: TextStyle(color: Colors.grey)))),
            Expanded(child: Center(child: Text('日', style: TextStyle(color: Colors.grey)))),
          ]),
        ),
        const SizedBox(height: 4),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 8),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 7, mainAxisSpacing: 4, crossAxisSpacing: 4),
          itemCount: leadBlank + daysInMonth,
          itemBuilder: (context, i) {
            if (i < leadBlank) return const SizedBox.shrink();
            final day = i - leadBlank + 1;
            final ds = '$_ym-${day.toString().padLeft(2, '0')}';
            final h = _heat[ds];
            final isToday = ds == todayStr;
            final sel = _selectedDay == ds;
            return InkWell(
              onTap: () => _pickDay(ds),
              borderRadius: BorderRadius.circular(8),
              child: Container(
                decoration: BoxDecoration(
                  color: _dayColor(h),
                  border: Border.all(
                      color: sel ? Colors.blue : isToday ? Colors.teal : Colors.transparent,
                      width: 2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Center(child: Text('$day',
                    style: TextStyle(
                        fontSize: 13,
                        color: h != null && (h['total'] ?? 0) > 0
                            ? Colors.white : null))),
              ),
            );
          },
        ),
        const SizedBox(height: 10),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          _legend('全勤', Colors.green.shade400),
          _legend('部分', Colors.orange.shade300),
          _legend('多漏', Colors.red.shade300),
          _legend('无记录', Colors.grey.shade200),
        ],),
        const SizedBox(height: 10),
        Expanded(
          child: _selectedDay == null
              ? const Center(child: Text('点选日期查看当天详细记录',
                  style: TextStyle(color: Colors.grey)))
              : FutureBuilder<List<Map<String, dynamic>>>(
                  future: Db.instance.dosesForDay(_selectedDay!),
                  builder: (ctx, snap) {
                    if (!snap.hasData) return const SizedBox.shrink();
                    final doses = snap.data!;
                    if (doses.isEmpty) {
                      return const Center(child: Text('当天无记录'));
                    }
                    return ListView.builder(
                      itemCount: doses.length,
                      itemBuilder: (ctx, i) {
                        final d = doses[i];
                        final med = _meds[d['medication_id'] as int];
                        final st = d['status'] as int;
                        return ListTile(
                          dense: true,
                          leading: Icon(
                              st == 0 ? Icons.check_circle
                              : st == 1 ? Icons.block : Icons.schedule,
                              color: st == 0 ? Colors.green
                              : st == 1 ? Colors.grey : Colors.orange),
                          title: Text('${(d['plan_time'] as String).substring(11, 16)} ${med?.name ?? '?'}'),
                          trailing: Text(st == 0 ? '已服' : st == 1 ? '跳过' : '未记录'),
                        );
                      },
                    );
                  }),
        ),
      ]),
    );
  }

  Widget _legend(String label, Color c) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 12, height: 12, decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(3))),
          const SizedBox(width: 4),
          Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
        ]),
      );
}
