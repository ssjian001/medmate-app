/// 统计页：今日进度环 + 近 7/30 天依从率 + 按药物分组
import 'package:flutter/material.dart';

import '../services/db.dart';

class StatsPage extends StatefulWidget {
  const StatsPage({super.key});
  @override
  State<StatsPage> createState() => _StatsPageState();
}

class _StatsPageState extends State<StatsPage> {
  Map<String, int> _today = {}, _7 = {}, _30 = {};
  List<Map<String, dynamic>> _byMed = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final t = await Db.instance.todayProgress();
    final a = await Db.instance.adherence(7);
    final b = await Db.instance.adherence(30);
    final m = await Db.instance.adherenceByMed(30);
    if (!mounted) return;
    setState(() {
      _today = t;
      _7 = a;
      _30 = b;
      _byMed = m;
    });
  }

  Widget _ring(String label, Map<String, int> d, double size) {
    final total = d['total'] ?? 0;
    final taken = d['taken'] ?? 0;
    final rate = total == 0 ? 0.0 : taken / total;
    return Column(children: [
      SizedBox(
        width: size, height: size,
        child: Stack(alignment: Alignment.center, children: [
          SizedBox(
            width: size, height: size,
            child: CircularProgressIndicator(
              value: total == 0 ? 0 : rate,
              strokeWidth: 9,
              strokeCap: StrokeCap.round,
              backgroundColor: Colors.grey.shade300,
            ),
          ),
          Text(total == 0 ? '—' : '${(rate * 100).toStringAsFixed(0)}%',
              style: TextStyle(fontSize: size / 4.2, fontWeight: FontWeight.bold)),
        ]),
      ),
      const SizedBox(height: 6),
      Text(label),
      Text('$taken/$total', style: const TextStyle(color: Colors.grey, fontSize: 12)),
    ]);
  }

  Widget _barCard(String title, Map<String, int> d) {
    final total = d['total'] ?? 0;
    final taken = d['taken'] ?? 0;
    final rate = total == 0 ? null : taken / total;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Text(rate == null ? '暂无数据' : '依从率 ${(rate * 100).toStringAsFixed(0)}%  ($taken/$total)'),
          const SizedBox(height: 8),
          LinearProgressIndicator(
              value: rate, minHeight: 10, borderRadius: BorderRadius.circular(5)),
          const SizedBox(height: 4),
          Text('漏服/跳过 ${d['skipped'] ?? 0} 次',
              style: const TextStyle(color: Colors.grey, fontSize: 12)),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      appBar: AppBar(title: const Text('服药统计')),
      body: ListView(padding: const EdgeInsets.all(12), children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 20),
            child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
              _ring('今日', _today, 110),
              _ring('近 7 天', _7, 110),
              _ring('近 30 天', _30, 110),
            ]),
          ),
        ),
        const SizedBox(height: 8),
        _barCard('近 30 天明细', _30),
        const SizedBox(height: 8),
        if (_byMed.isNotEmpty) ...[
          Padding(padding: const EdgeInsets.only(left: 4, bottom: 6),
              child: Text('按药物（近 30 天）',
                  style: Theme.of(context).textTheme.titleMedium)),
          ..._byMed.map((r) => Card(
                child: ListTile(
                  leading: Icon(Icons.medication,
                      color: _tagColor(r['color_tag'] as String? ?? 'teal', isDark)),
                  title: Text(r['name'] as String? ?? '?'),
                  subtitle: LinearProgressIndicator(
                      value: (r['total'] as int? ?? 0) == 0
                          ? 0
                          : (r['taken'] as int) / (r['total'] as int),
                      minHeight: 6,
                      borderRadius: BorderRadius.circular(3)),
                  trailing: Text('${r['taken']}/${r['total']}'),
                ),
              )),
        ],
      ]),
    );
  }

  Color _tagColor(String tag, bool isDark) {
    final base = switch (tag) {
      'red' => Colors.red,
      'orange' => Colors.orange,
      'blue' => Colors.blue,
      'purple' => Colors.purple,
      _ => Colors.teal,
    };
    return isDark ? base.shade300 : base.shade400;
  }
}
