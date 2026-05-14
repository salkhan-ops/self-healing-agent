class Report {
  const Report({
    required this.id,
    required this.timestamp,
    required this.problem,
    required this.rootCause,
    required this.fixApplied,
    required this.beforeHallucination,
    required this.afterHallucination,
    required this.beforeRelevance,
    required this.afterRelevance,
    required this.beforeLatency,
    required this.afterLatency,
    required this.improvementPercent,
    required this.humanNeeded,
    required this.contentText,
  });

  final int id;
  final DateTime timestamp;
  final String problem;
  final String rootCause;
  final String fixApplied;
  final double beforeHallucination;
  final double afterHallucination;
  final double beforeRelevance;
  final double afterRelevance;
  final double beforeLatency;
  final double afterLatency;
  final double improvementPercent;
  final bool humanNeeded;
  final String contentText;

  factory Report.fromJson(Map<String, dynamic> json) {
    return Report(
      id: _int(json['id']),
      timestamp: _date(json['timestamp']),
      problem: json['problem']?.toString() ?? '',
      rootCause: json['root_cause']?.toString() ?? '',
      fixApplied: json['fix_applied']?.toString() ?? '',
      beforeHallucination: _double(json['before_hallucination']),
      afterHallucination: _double(json['after_hallucination']),
      beforeRelevance: _double(json['before_relevance']),
      afterRelevance: _double(json['after_relevance']),
      beforeLatency: _double(json['before_latency']),
      afterLatency: _double(json['after_latency']),
      improvementPercent: _double(json['improvement_percent']),
      humanNeeded: json['human_needed'] == true,
      contentText: json['content_text']?.toString() ?? '',
    );
  }
}

DateTime _date(dynamic value) {
  return DateTime.tryParse(value?.toString() ?? '') ?? DateTime.now();
}

double _double(dynamic value) {
  if (value is num) {
    return value.toDouble();
  }

  return double.tryParse(value?.toString() ?? '') ?? 0;
}

int _int(dynamic value) {
  if (value is num) {
    return value.toInt();
  }

  return int.tryParse(value?.toString() ?? '') ?? 0;
}
