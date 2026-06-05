import 'package:flutter/foundation.dart';

import '../core/api_client.dart';
import '../models/report.dart';

class ReportsProvider extends ChangeNotifier {
  ReportsProvider({ApiClient? apiClient})
    : _apiClient = apiClient ?? ApiClient();

  final ApiClient _apiClient;

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

  @override
  void dispose() {
    _apiClient.close();
    super.dispose();
  }
}
