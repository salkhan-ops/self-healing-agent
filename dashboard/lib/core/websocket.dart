import 'dart:async';

import 'package:web_socket_channel/web_socket_channel.dart';

import 'app_config.dart';

class WebSocketClient {
  WebSocketClient({String? url}) : url = url ?? AppConfig.wsUrl;

  final String url;
  final StreamController<String> _messageController =
      StreamController<String>.broadcast();
  WebSocketChannel? _channel;
  Timer? _reconnectTimer;
  bool _manualDisconnect = false;

  Stream<String> get messageStream => _messageController.stream;

  void connect() {
    _manualDisconnect = false;
    _reconnectTimer?.cancel();

    try {
      _channel = WebSocketChannel.connect(Uri.parse(url));
      _channel!.stream.listen(
        (message) => _messageController.add(message.toString()),
        onError: (_) => _scheduleReconnect(),
        onDone: _scheduleReconnect,
        cancelOnError: true,
      );
    } catch (error) {
      _messageController.add('WebSocket connection failed: $error');
      _scheduleReconnect();
    }
  }

  void disconnect() {
    _manualDisconnect = true;
    _reconnectTimer?.cancel();
    _channel?.sink.close();
    _channel = null;
  }

  void _scheduleReconnect() {
    if (_manualDisconnect || _reconnectTimer?.isActive == true) {
      return;
    }

    _reconnectTimer = Timer(const Duration(seconds: 3), connect);
  }

  void dispose() {
    disconnect();
    _messageController.close();
  }
}
