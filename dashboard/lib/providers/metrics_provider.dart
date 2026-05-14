import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/api_client.dart';
import '../models/metric.dart';

class MetricsProvider extends ChangeNotifier {
  MetricsProvider({ApiClient? apiClient})
    : _apiClient = apiClient ?? ApiClient() {
    _refreshTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      loadSummary();
      loadChartData(selectedPeriod);
    });
  }

  final ApiClient _apiClient;
  Timer? _refreshTimer;

  MetricSummary? summary;
  List<MetricPoint> chartData = [];
  String selectedPeriod = 'day';

  Future<void> loadSummary() async {
    final data = await _apiClient.getMetricsSummary();
    if (data['error'] == true) {
      return;
    }

    summary = MetricSummary.fromJson(data);
    notifyListeners();
  }

  Future<void> loadChartData(String period) async {
    selectedPeriod = period;
    final data = await _apiClient.getMetricsRange(period);
    if (data['error'] == true) {
      notifyListeners();
      return;
    }

    final points = data['points'];
    chartData = points is List
        ? points
              .whereType<Map<String, dynamic>>()
              .map(MetricPoint.fromJson)
              .toList()
        : <MetricPoint>[];
    notifyListeners();
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _apiClient.close();
    super.dispose();
  }
}
