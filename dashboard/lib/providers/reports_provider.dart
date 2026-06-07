import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/api_client.dart';
import '../core/websocket.dart';
import '../models/report.dart';

class ReportsProvider extends ChangeNotifier {
  ReportsProvider({ApiClient? apiClient})
    : _apiClient = apiClient ?? ApiClient() {
    _listenForUpdates(_webSocketClient.messageStream);
    _webSocketClient.connect();
  }

  final ApiClient _apiClient;
  final WebSocketClient _webSocketClient = WebSocketClient();
  StreamSubscription<String>? _webSocketSubscription;

  List<Report> reports = [];
  Report? selectedReport;
  bool isLoading = false;
  bool isClearing = false;

  Future<void> loadReports() async {
    isLoading = true;
    notifyListeners();

    final data = await _apiClient.getReports();
    reports = data
        .whereType<Map<String, dynamic>>()
        .map(Report.fromJson)
        .toList();

    isLoading = false;
    notifyListeners();
  }

  Future<void> loadReport(int id) async {
    isLoading = true;
    notifyListeners();

    final data = await _apiClient.getReport(id);
    selectedReport = data['error'] == true ? null : Report.fromJson(data);

    isLoading = false;
    notifyListeners();
  }

  Future<Map<String, dynamic>> clearReports() async {
    isClearing = true;
    notifyListeners();

    final result = await _apiClient.clearReports();
    if (result['error'] != true) {
      reports = [];
      selectedReport = null;
    }

    isClearing = false;
    notifyListeners();
    return result;
  }

  void _listenForUpdates(Stream<String> messageStream) {
    _webSocketSubscription?.cancel();
    _webSocketSubscription = messageStream.listen((message) {
      if (message == 'reports_updated' || message.contains('completed')) {
        loadReports();
      }
    });
  }

  @override
  void dispose() {
    _webSocketSubscription?.cancel();
    _webSocketClient.dispose();
    _apiClient.close();
    super.dispose();
  }
}
