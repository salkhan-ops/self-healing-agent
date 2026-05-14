class MetricPoint {
  const MetricPoint({
    required this.timestamp,
    required this.hallucination,
    required this.relevance,
    required this.latencyMs,
    required this.improvementPercent,
    required this.runId,
  });

  final DateTime timestamp;
  final double hallucination;
  final double relevance;
  final double latencyMs;
  final double improvementPercent;
  final String runId;

  factory MetricPoint.fromJson(Map<String, dynamic> json) {
    return MetricPoint(
      timestamp: _date(json['timestamp']),
      hallucination: _double(json['hallucination_score']),
      relevance: _double(json['relevance_score']),
      latencyMs: _double(json['latency_ms']),
      improvementPercent: _double(json['improvement_percent']),
      runId: json['run_id']?.toString() ?? '',
    );
  }
}

class MetricSummary {
  const MetricSummary({
    required this.healthScore,
    required this.avgHallucination,
    required this.avgRelevance,
    required this.avgLatency,
    required this.totalRuns,
  });

  final double healthScore;
  final double avgHallucination;
  final double avgRelevance;
  final double avgLatency;
  final int totalRuns;

  factory MetricSummary.fromJson(Map<String, dynamic> json) {
    return MetricSummary(
      healthScore: _double(json['health_score']),
      avgHallucination: _double(json['hallucination_score']),
      avgRelevance: _double(json['relevance_score']),
      avgLatency: _double(json['latency_ms']),
      totalRuns: _int(json['snapshot_count']),
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
