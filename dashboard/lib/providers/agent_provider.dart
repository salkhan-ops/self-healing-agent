import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/api_client.dart';
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

  Future<void> runNow() async {
    final result = await _apiClient.runAgentNow();
    if (result['error'] != true) {
      isRunning = true;
      liveOutput.add('Agent run started: ${result['run_id'] ?? ''}');
      await loadStatus();
      notifyListeners();
    }
  }

  Future<void> stopNow() async {
    final result = await _apiClient.stopAgentNow();
    if (result['error'] != true) {
      isStopping = result['status'] == 'stopping';
      liveOutput.add('Stop requested for agent run: ${result['run_id'] ?? ''}');
      await loadStatus();
      notifyListeners();
    }
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
