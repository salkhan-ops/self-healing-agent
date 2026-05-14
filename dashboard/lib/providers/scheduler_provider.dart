import 'package:flutter/foundation.dart';

import '../core/api_client.dart';
import '../models/schedule.dart';

class SchedulerProvider extends ChangeNotifier {
  SchedulerProvider({ApiClient? apiClient})
    : _apiClient = apiClient ?? ApiClient();

  final ApiClient _apiClient;

  List<Schedule> schedules = [];
  bool isLoading = false;

  Future<void> loadSchedules() async {
    isLoading = true;
    notifyListeners();

    final data = await _apiClient.getSchedules();
    schedules = data
        .whereType<Map<String, dynamic>>()
        .map(Schedule.fromJson)
        .toList();

    isLoading = false;
    notifyListeners();
  }

  Future<void> createSchedule(
    String name,
    int intervalMinutes, {
    bool enabled = true,
  }) async {
    await _apiClient.createSchedule(name, intervalMinutes, enabled: enabled);
    await loadSchedules();
  }

  Future<void> toggleSchedule(int id) async {
    await _apiClient.toggleSchedule(id);
    await loadSchedules();
  }

  Future<void> deleteSchedule(int id) async {
    await _apiClient.deleteSchedule(id);
    await loadSchedules();
  }

  @override
  void dispose() {
    _apiClient.close();
    super.dispose();
  }
}
