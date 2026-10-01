/// 数据库服务：sqflite 封装（单例）
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;

import '../models/medication.dart';

class Db {
  Db._();
  static final Db instance = Db._();
  Database? _db;

  Future<Database> get db async {
    _db ??= await _open();
    return _db!;
  }

  Future<Database> _open() async {
    final path = p.join(await getDatabasesPath(), 'medmate.db');
    return openDatabase(path, version: 4,
        onUpgrade: (d, oldV, newV) async {
          // 幂等列修复: 不管从哪个版本升上来, 缺什么补什么
          // (历史版本建表语句曾缺列且版本号已标高, 只能靠无条件修复)
          final medCols = (await d.rawQuery('PRAGMA table_info(medications)'))
              .map((c) => c['name']).toSet();
          if (!medCols.contains('stock')) {
            await d.execute(
                "ALTER TABLE medications ADD COLUMN stock REAL DEFAULT -1");
          }
          if (!medCols.contains('custom_msg')) {
            await d.execute(
                "ALTER TABLE medications ADD COLUMN custom_msg TEXT DEFAULT ''");
          }
          final doseCols = (await d.rawQuery('PRAGMA table_info(dose_events)'))
              .map((c) => c['name']).toSet();
          if (!doseCols.contains('notified')) {
            await d.execute(
                'ALTER TABLE dose_events ADD COLUMN notified INTEGER DEFAULT 0');
          }
        },
        onCreate: (d, v) async {
      await d.execute('''
        CREATE TABLE medications(
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          name TEXT NOT NULL,
          dosage TEXT,
          times TEXT NOT NULL,
          note TEXT,
          color_tag TEXT,
          active INTEGER DEFAULT 1,
          stock REAL DEFAULT -1,
          custom_msg TEXT DEFAULT '')
      ''');
      await d.execute('''
        CREATE TABLE dose_events(
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          medication_id INTEGER NOT NULL,
          plan_time TEXT NOT NULL,
          status INTEGER DEFAULT 2,
          taken_at TEXT,
          notified INTEGER DEFAULT 0,
          UNIQUE(medication_id, plan_time))
      ''');
    });
  }

  // ---- medications ----
  Future<List<Medication>> allMeds({bool onlyActive = true}) async {
    final rows = await (await db).query('medications',
        where: onlyActive ? 'active=1' : null, orderBy: 'name');
    return rows.map(Medication.fromRow).toList();
  }

  Future<int> upsertMed(Medication m) async {
    final d = await db;
    if (m.id == null) return d.insert('medications', m.toRow());
    await d.update('medications', m.toRow(), where: 'id=?', whereArgs: [m.id]);
    return m.id!;
  }

  Future<void> deleteMed(int id) async {
    final d = await db;
    await d.delete('medications', where: 'id=?', whereArgs: [id]);
    await d.delete('dose_events', where: 'medication_id=?', whereArgs: [id]);
  }

  // ---- dose_events ----
  /// 确保 [date] 这天的计划事件都存在（按药物 times 生成）
  Future<void> ensurePlansFor(String date /* yyyy-MM-dd */) async {
    final d = await db;
    final meds = await allMeds();
    for (final m in meds) {
      for (final t in m.times) {
        final plan = '${date}_$t'.replaceAll('_', ' ');
        await d.insert('dose_events',
            DoseEvent(medicationId: m.id!, planTime: plan).toRow(),
            conflictAlgorithm: ConflictAlgorithm.ignore);
      }
    }
  }

  Future<List<Map<String, dynamic>>> dosesForDay(String date) async {
    final d = await db;
    return d.query('dose_events',
        where: 'plan_time LIKE ?',
        whereArgs: ['$date%'],
        orderBy: 'plan_time');
  }

  /// 漏服检查: 计划时间已过 [graceMin] 分钟且仍 pending 且未提醒过
  Future<List<Map<String, dynamic>>> overdue({int graceMin = 30}) async {
    final d = await db;
    final cutoff = DateTime.now().subtract(Duration(minutes: graceMin))
        .toIso8601String().substring(0, 16).replaceAll('T', ' ');
    return d.query('dose_events',
        where: "status=2 AND plan_time < ? AND notified=0",
        whereArgs: [cutoff],
        orderBy: 'plan_time');
  }

  /// 标记漏服通知已发
  Future<void> markNotified(int eventId) async {
    final d = await db;
    await d.update('dose_events', {'notified': 1},
        where: 'id=?', whereArgs: [eventId]);
  }

  Future<void> markTaken(int eventId, {bool skipped = false}) async {
    final d = await db;
    final now = DateTime.now().toIso8601String().substring(0, 16);
    await d.update('dose_events',
        {'status': skipped ? 1 : 0, 'taken_at': now},
        where: 'id=?', whereArgs: [eventId]);
  }

  /// 撤销打卡: 恢复为 pending
  Future<void> updateStatus(int eventId, DoseStatus status) async {
    final d = await db;
    await d.update('dose_events',
        {'status': status.index, 'taken_at': status == DoseStatus.pending ? null : DateTime.now().toIso8601String().substring(0, 16)},
        where: 'id=?', whereArgs: [eventId]);
  }

  /// 近 n 天依从率: {taken, total}
  Future<Map<String, int>> adherence(int days) async {
    final d = await db;
    final from = DateTime.now()
        .subtract(Duration(days: days))
        .toIso8601String()
        .substring(0, 10);
    final taken = await d.rawQuery(
        "SELECT COUNT(*) c FROM dose_events WHERE status=0 AND plan_time>=?", [from]);
    final skipped = await d.rawQuery(
        "SELECT COUNT(*) c FROM dose_events WHERE status=1 AND plan_time>=?", [from]);
    final total = await d.rawQuery(
        "SELECT COUNT(*) c FROM dose_events WHERE plan_time>=? AND status!=2", [from]);
    return {
      'taken': taken.first['c'] as int? ?? 0,
      'skipped': skipped.first['c'] as int? ?? 0,
      'total': total.first['c'] as int? ?? 0,
    };
  }

  /// 今日进度: {taken, total}（今天该吃的/已吃的，不含未来时间点）
  Future<Map<String, int>> todayProgress() async {
    final d = await db;
    final date = DateTime.now().toIso8601String().substring(0, 10);
    final rows = await d.query('dose_events',
        where: "plan_time LIKE ? AND status!=2 AND plan_time <= ?",
        whereArgs: ['$date%', '${date} ${DateTime.now().toIso8601String().substring(11, 16)}']);
    return {
      'taken': rows.where((r) => r['status'] == 0).length,
      'total': rows.length,
    };
  }

  /// 日历热图: 指定月份每天的 (taken, total, missed)
  Future<Map<String, Map<String, int>>> calendarMonth(String ym) async {
    final d = await db;
    final rows = await d.rawQuery('''
      SELECT substr(plan_time,1,10) day,
             SUM(CASE WHEN status=0 THEN 1 ELSE 0 END) taken,
             SUM(CASE WHEN status!=2 THEN 1 ELSE 0 END) total,
             SUM(CASE WHEN status=1 THEN 1 ELSE 0 END) skipped
      FROM dose_events WHERE plan_time LIKE ?
      GROUP BY day''', ['$ym%']);
    final out = <String, Map<String, int>>{};
    for (final r in rows) {
      out[r['day'] as String] = {
        'taken': r['taken'] as int? ?? 0,
        'total': r['total'] as int? ?? 0,
        'skipped': r['skipped'] as int? ?? 0,
      };
    }
    return out;
  }

  /// 库存扣减: 每次打卡服用后 stock-1（stock>=0 才管理）
  Future<void> deductStock(int medicationId) async {
    final d = await db;
    await d.rawUpdate(
        'UPDATE medications SET stock = stock-1 WHERE id=? AND stock>=0',
        [medicationId]);
  }

  /// 余量不足的药物 (stock>=0 且 stock <= days*每日次数, 即不足 N 天)
  Future<List<Map<String, dynamic>>> lowStock({int days = 3}) async {
    final d = await db;
    return d.rawQuery('''
      SELECT id, name, stock, times FROM medications
      WHERE active=1 AND stock>=0 AND stock <= (LENGTH(times)-LENGTH(REPLACE(times,',',''))+1) * ?
    ''', [days]);
  }

  /// 按药物分组的依从统计（近 n 天）
  Future<List<Map<String, dynamic>>> adherenceByMed(int days) async {
    final d = await db;
    final from = DateTime.now()
        .subtract(Duration(days: days))
        .toIso8601String()
        .substring(0, 10);
    return d.rawQuery('''
      SELECT m.name, m.color_tag,
             SUM(CASE WHEN e.status=0 THEN 1 ELSE 0 END) taken,
             SUM(CASE WHEN e.status!=2 THEN 1 ELSE 0 END) total
      FROM dose_events e JOIN medications m ON m.id=e.medication_id
      WHERE e.plan_time>=?
      GROUP BY e.medication_id ORDER BY total DESC''', [from]);
  }
}
