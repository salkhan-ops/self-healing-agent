import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/api_client.dart';
import '../core/app_config.dart';
import '../core/browser_storage.dart';
import '../core/websocket.dart';

class AgentProvider extends ChangeNotifier {
  AgentProvider({ApiClient? apiClient, WebSocketClient? webSocketClient})
    : _apiClient = apiClient ?? ApiClient(),
      _webSocketClient = webSocketClient ?? WebSocketClient();

  final ApiClient _apiClient;
  final WebSocketClient _webSocketClient;
  StreamSubscription<String>? _subscription;

  Map<String, dynamic> status = {};
  bool isRunning = false;
  bool isStopping = false;
  List<String> liveOutput = [];

  static const _publicRunUsedKey = 'public_agent_control_used';
  static const _publicRunCountKey = 'public_agent_control_run_count';
  static const _publicRunLocalLimit = 3;

  Future<Map<String, dynamic>> runNow() async {
    if (AppConfig.publicDemoMode && _publicRunsUsed() >= _publicRunLocalLimit) {
      final result = {
        'run_id': '',
        'status': 'disabled',
        'message':
            'Public mode allows $_publicRunLocalLimit full Agent Control runs per browser.',
      };
      liveOutput.add(result['message']!);
      notifyListeners();
      return result;
    }

    final result = await _apiClient.runAgentNow();
    if (result['status'] == 'disabled') {
      liveOutput.add(result['message']?.toString() ?? 'Agent run disabled.');
      await loadStatus();
      notifyListeners();
      return result;
    }

    if (result['error'] != true) {
      isRunning = true;
      liveOutput.add('Agent run started: ${result['run_id'] ?? ''}');
      if (AppConfig.publicDemoMode && result['status'] == 'started') {
        BrowserStorage.setInt(_publicRunCountKey, _publicRunsUsed() + 1);
        BrowserStorage.setBool(_publicRunUsedKey, true);
      }
      await loadStatus();
      notifyListeners();
    }
    return result;
  }

  int _publicRunsUsed() {
    final count = BrowserStorage.getInt(_publicRunCountKey);
    if (count > 0) {
      return count;
    }
    return BrowserStorage.getBool(_publicRunUsedKey) ? 1 : 0;
  }

  Future<Map<String, dynamic>> stopNow() async {
    final result = await _apiClient.stopAgentNow();
    if (result['error'] != true) {
      isStopping = result['status'] == 'stopping';
      liveOutput.add('Stop requested for agent run: ${result['run_id'] ?? ''}');
      await loadStatus();
      notifyListeners();
    }
    return result;
  }

  Future<void> loadStatus() async {
    final data = await _apiClient.getAgentStatus();
    if (data['error'] == true) {
      return;
    }

    status = data;
    final statusText = data['status']?.toString() ?? '';
    isRunning =
        data['running'] == true ||
        statusText == 'running' ||
        statusText == 'stopping';
    isStopping = statusText == 'stopping';
    notifyListeners();
  }

  void connectWebSocket() {
    _subscription?.cancel();
    _subscription = _webSocketClient.messageStream.listen((message) {
      liveOutput = [...liveOutput, message];
      if (message.contains(':stop_requested')) {
        isStopping = true;
        isRunning = true;
      }
      if (message.contains(':completed') ||
          message.contains(':error') ||
          message.contains(':stopped')) {
        isStopping = false;
        loadStatus();
      }
      notifyListeners();
    });
    _webSocketClient.connect();
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _webSocketClient.dispose();
    _apiClient.close();
    super.dispose();
  }
}
