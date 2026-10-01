/// 导出服务: 打卡记录 CSV（通过系统分享发给医生/家属）
import 'dart:convert';
import 'dart:io';

import 'package:csv/csv.dart';
import 'package:share_plus/share_plus.dart';

import 'db.dart';

class Exporter {
  Exporter._();
  static final Exporter instance = Exporter._();

  Future<void> shareCsv({int days = 30}) async {
    final d = await Db.instance;
    final meds = {for (final m in await d.allMeds(onlyActive: false)) m.id!: m};
    final from = DateTime.now().subtract(Duration(days: days))
        .toIso8601String().substring(0, 10);

    final rows = await (await d.db).rawQuery('''
      SELECT e.plan_time, e.medication_id, e.status, e.taken_at
      FROM dose_events e WHERE e.plan_time>=? AND e.status!=2
      ORDER BY e.plan_time''', [from]);

    final csv = const ListToCsvConverter().convert([
      ['日期时间', '药名', '剂量', '状态', '实际打卡时间'],
      ...rows.map((r) {
        final med = meds[r['medication_id'] as int];
        final st = r['status'] as int;
        return [
          r['plan_time'],
          med?.name ?? '?',
          med?.dosage ?? '',
          st == 0 ? '已服用' : '跳过',
          (r['taken_at'] as String? ?? '').isEmpty ? '' : r['taken_at'],
        ];
      }),
    ]);

    final dir = await Directory.systemTemp.createTemp('medmate');
    final f = File('${dir.path}/medmate_${days}days.csv');
    await f.writeAsString('\uFEFF$csv', encoding: const Utf8Codec()); // BOM 让 Excel 识别中文

    await SharePlus.instance.share(ShareParams(
        files: [XFile(f.path)],
        text: 'MedMate 服药记录（近 $days 天）'));
  }
}
