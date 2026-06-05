import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/api_client.dart';
import '../core/websocket.dart';
import '../models/metric.dart';

class MetricsProvider extends ChangeNotifier {
  MetricsProvider({ApiClient? apiClient})
    : _apiClient = apiClient ?? ApiClient() {
    _refreshTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      loadSummary();
      loadChartData(selectedPeriod);
    });
    _listenForUpdates(_webSocketClient.messageStream);
    _webSocketClient.connect();
  }

  final ApiClient _apiClient;
  final WebSocketClient _webSocketClient = WebSocketClient();
  Timer? _refreshTimer;
  StreamSubscription<String>? _webSocketSubscription;

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

  void _listenForUpdates(Stream<String> messageStream) {
    _webSocketSubscription?.cancel();
    _webSocketSubscription = messageStream.listen((message) {
      if (message == 'metrics_updated' ||
          message.contains('completed') ||
          message.contains('prompt_updated')) {
        loadChartData(selectedPeriod);
        loadSummary();
      }
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _webSocketSubscription?.cancel();
    _webSocketClient.dispose();
    _apiClient.close();
    super.dispose();
  }
}
