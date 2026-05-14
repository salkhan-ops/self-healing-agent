class Schedule {
  const Schedule({
    required this.id,
    required this.name,
    required this.intervalMinutes,
    required this.enabled,
    required this.lastRun,
    required this.nextRun,
    required this.runCount,
  });

  final int id;
  final String name;
  final int intervalMinutes;
  final bool enabled;
  final DateTime? lastRun;
  final DateTime? nextRun;
  final int runCount;

  factory Schedule.fromJson(Map<String, dynamic> json) {
    return Schedule(
      id: _int(json['id']),
      name: json['name']?.toString() ?? '',
      intervalMinutes: _int(json['interval_minutes']),
      enabled: json['enabled'] == true,
      lastRun: _nullableDate(json['last_run']),
      nextRun: _nullableDate(json['next_run']),
      runCount: _int(json['run_count']),
    );
  }
}

DateTime? _nullableDate(dynamic value) {
  if (value == null || value.toString().isEmpty) {
    return null;
  }

  return DateTime.tryParse(value.toString());
}

int _int(dynamic value) {
  if (value is num) {
    return value.toInt();
  }

  return int.tryParse(value?.toString() ?? '') ?? 0;
}
