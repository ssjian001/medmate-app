/// 药物管理页：列表 + 新增/编辑对话框
import 'package:flutter/material.dart';

import '../models/medication.dart';
import '../services/db.dart';

class MedsPage extends StatefulWidget {
  const MedsPage({super.key});
  @override
  State<MedsPage> createState() => _MedsPageState();
}

class _MedsPageState extends State<MedsPage> {
  List<Medication> _meds = [];

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final meds = await Db.instance.allMeds(onlyActive: false);
    if (!mounted) return;
    setState(() => _meds = meds);
  }

  Future<void> _edit([Medication? m]) async {
    final name = TextEditingController(text: m?.name);
    final dosage = TextEditingController(text: m?.dosage);
    final note = TextEditingController(text: m?.note);
    final customMsg = TextEditingController(text: m?.customMsg);
    final stockCtl = TextEditingController(
        text: (m != null && m.stock >= 0) ? m.stock.toStringAsFixed(0) : '');
    var times = List<String>.from(m?.times ?? const ['08:00']);
    var colorTag = m?.colorTag ?? 'teal';

    late final bool ok;
    try {
    final r = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: Text(m == null ? '添加药物' : '编辑药物'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(controller: name, decoration: const InputDecoration(labelText: '药名 *')),
              TextField(controller: dosage, decoration: const InputDecoration(labelText: '剂量 (如 0.5mg / 2片)')),
              TextField(controller: note, decoration: const InputDecoration(labelText: '备注 (饭前/饭后...)')),
              TextField(controller: customMsg, decoration: const InputDecoration(labelText: '自定义提醒语 (留空用默认)')),
              TextField(controller: stockCtl, decoration: const InputDecoration(labelText: '库存数量 (留空=不管理)', hintText: '如 30'), keyboardType: TextInputType.number),
              const SizedBox(height: 12),
              Row(children: [
                const Text('每日时间:'),
                ...times.asMap().entries.map((e) => Padding(
                      padding: const EdgeInsets.only(left: 6),
                      child: InputChip(
                        label: Text(e.value),
                        onDeleted: times.length > 1
                            ? () => setD(() => times.removeAt(e.key))
                            : null,
                      ),
                    )),
              ]),
              OutlinedButton.icon(
                icon: const Icon(Icons.add_alarm),
                label: const Text('加时间点'),
                onPressed: () async {
                  final t = await showTimePicker(
                      context: ctx,
                      initialTime: const TimeOfDay(hour: 8, minute: 0));
                  if (t != null) {
                    setD(() => times.add(
                        '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}'));
                  }
                },
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                initialValue: colorTag,
                decoration: const InputDecoration(labelText: '颜色标'),
                items: const [
                  DropdownMenuItem(value: 'teal', child: Text('青')),
                  DropdownMenuItem(value: 'red', child: Text('红')),
                  DropdownMenuItem(value: 'orange', child: Text('橙')),
                  DropdownMenuItem(value: 'blue', child: Text('蓝')),
                  DropdownMenuItem(value: 'purple', child: Text('紫')),
                ],
                onChanged: (v) => setD(() => colorTag = v ?? 'teal'),
              ),
            ]),
          ),
          actions: [
            if (m != null)
              TextButton(
                  onPressed: () async {
                    await Db.instance.deleteMed(m.id!);
                    if (ctx.mounted) Navigator.pop(ctx, true);
                  },
                  child: const Text('删除', style: TextStyle(color: Colors.red))),
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('取消')),
            FilledButton(
                onPressed: () async {
                  if (name.text.trim().isEmpty) {
                    ScaffoldMessenger.of(ctx).showSnackBar(
                        const SnackBar(content: Text('请填写药名')));
                    return;
                  }
                  try {
                    await Db.instance.upsertMed(Medication(
                      id: m?.id,
                      name: name.text.trim(),
                      dosage: dosage.text.trim(),
                      note: note.text.trim().isEmpty ? null : note.text.trim(),
                      times: times..sort(),
                      colorTag: colorTag,
                      stock: stockCtl.text.trim().isEmpty
                          ? -1
                          : double.tryParse(stockCtl.text.trim()) ?? -1,
                      customMsg: customMsg.text.trim(),
                    ));
                    if (ctx.mounted) Navigator.pop(ctx, true);
                  } catch (e) {
                    if (ctx.mounted) {
                      ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
                          content: Text('保存失败: $e'),
                          backgroundColor: Colors.red));
                    }
                  }
                },
                child: const Text('保存')),
          ],
        ),
      ),
    );
    ok = r ?? false;
    } finally {
      for (final c in [name, dosage, note, customMsg, stockCtl]) {
        c.dispose();
      }
    }
    if (ok == true) _reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('药物管理')),
      body: _meds.isEmpty
          ? const Center(child: Text('暂无药物'))
          : ListView.builder(
              itemCount: _meds.length,
              itemBuilder: (context, i) => ListTile(
                leading: const Icon(Icons.medication_liquid),
                title: Text(_meds[i].name),
                subtitle: Text(_meds[i].times.join(' / ')),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _edit(_meds[i]),
              ),
            ),
      floatingActionButton: FloatingActionButton(
          onPressed: () => _edit(), child: const Icon(Icons.add)),
    );
  }
}
