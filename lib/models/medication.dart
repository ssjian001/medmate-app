/// 数据模型：药物与服药记录
/// 存储用 sqflite，两张表：medications / dose_events
class Medication {
  final int? id;
  final String name; // 药名
  final String dosage; // 剂量描述，如 "0.5mg" "2片"
  final List<String> times; // 每日服用时间点 "08:00","20:00"
  final String? note; // 备注（饭前/饭后等）
  final String colorTag; // 界面色标 (Material 色名)
  final bool active; // 是否启用
  final double stock; // 剩余量, -1=不管理库存
  final String customMsg; // 自定义提醒文案

  Medication({
    this.id,
    required this.name,
    required this.dosage,
    required this.times,
    this.note,
    this.colorTag = 'teal',
    this.active = true,
    this.stock = -1,
    this.customMsg = '',
  });

  Map<String, dynamic> toRow() => {
        if (id != null) 'id': id,
        'name': name,
        'dosage': dosage,
        'times': times.join(','),
        'note': note ?? '',
        'color_tag': colorTag,
        'active': active ? 1 : 0,
        'stock': stock,
        'custom_msg': customMsg,
      };

  factory Medication.fromRow(Map<String, dynamic> r) => Medication(
        id: r['id'] as int?,
        name: r['name'] as String,
        dosage: r['dosage'] as String? ?? '',
        times: (r['times'] as String? ?? '').split(',').where((s) => s.isNotEmpty).toList(),
        note: (r['note'] as String? ?? '').isEmpty ? null : r['note'] as String,
        colorTag: r['color_tag'] as String? ?? 'teal',
        active: (r['active'] as int? ?? 1) == 1,
        stock: (r['stock'] as num?)?.toDouble() ?? -1,
        customMsg: r['custom_msg'] as String? ?? '',
      );
}

/// 一次服药事件：medicationId + 计划时间(yyyy-MM-dd HH:mm) + 状态
enum DoseStatus { taken, skipped, pending }

class DoseEvent {
  final int? id;
  final int medicationId;
  final String planTime; // "2026-10-01 08:00"
  final DoseStatus status;
  final String? takenAt; // 实际打卡时间

  DoseEvent({
    this.id,
    required this.medicationId,
    required this.planTime,
    this.status = DoseStatus.pending,
    this.takenAt,
  });

  Map<String, dynamic> toRow() => {
        if (id != null) 'id': id,
        'medication_id': medicationId,
        'plan_time': planTime,
        'status': status.index,
        'taken_at': takenAt ?? '',
      };

  factory DoseEvent.fromRow(Map<String, dynamic> r) => DoseEvent(
        id: r['id'] as int?,
        medicationId: r['medication_id'] as int,
        planTime: r['plan_time'] as String,
        status: DoseStatus.values[r['status'] as int? ?? 2],
        takenAt: (r['taken_at'] as String? ?? '').isEmpty ? null : r['taken_at'] as String,
      );
}
