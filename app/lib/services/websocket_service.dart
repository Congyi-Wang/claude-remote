import 'dart:async';
import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';

class WebSocketService {
  WebSocketChannel? _channel;
  String? _sessionId;
  String? _token;
  String? _connectSessionId;
  Function(String)? onChunk;
  Function(Map<String, dynamic>)? onDone;
  Function(String)? onStatus;
  Function(String)? onSessionId;
  Function(String)? onError;
  Function()? onConnected;

  String? get sessionId => _sessionId;
  bool get isConnected => _channel != null;

  bool _disposed = false;
  int _reconnectAttempts = 0;
  static const _maxReconnectAttempts = 10;

  Future<bool> connect(String sessionId, String token) async {
    _connectSessionId = sessionId;
    _token = token;
    _disposed = false;
    _reconnectAttempts = 0;
    return _doConnect();
  }

  Future<bool> _doConnect() async {
    if (_disposed) return false;
    try {
      final sid = _sessionId ?? _connectSessionId!;
      final wsUrl = 'ws://46.224.150.45/claude-remote/api/sessions/ws/$sid';
      _channel = WebSocketChannel.connect(Uri.parse(wsUrl));

      _channel!.sink.add(jsonEncode({'token': _token}));

      _channel!.stream.listen(
        (data) {
          _reconnectAttempts = 0;
          final msg = jsonDecode(data);
          final type = msg['type'] ?? '';

          switch (type) {
            case 'auth_ok':
              onConnected?.call();
              break;
            case 'session_id':
              _sessionId = msg['session_id'];
              onSessionId?.call(_sessionId!);
              break;
            case 'chunk':
              onChunk?.call(msg['text'] ?? '');
              break;
            case 'done':
              onDone?.call(msg);
              break;
            case 'status':
              onStatus?.call(msg['text'] ?? '');
              break;
            case 'error':
              onError?.call(msg['text'] ?? 'Unknown error');
              break;
            case 'ping':
              // Respond to server keepalive
              _channel?.sink.add(jsonEncode({'type': 'pong'}));
              break;
          }
        },
        onError: (e) {
          _channel = null;
          _tryReconnect();
        },
        onDone: () {
          _channel = null;
          _tryReconnect();
        },
      );

      await Future.delayed(const Duration(milliseconds: 500));
      return true;
    } catch (e) {
      _channel = null;
      onError?.call(e.toString());
      return false;
    }
  }

  void _tryReconnect() {
    if (_disposed || _token == null) return;
    if (_reconnectAttempts >= _maxReconnectAttempts) {
      onError?.call('Connection lost. Please go back and reopen the chat.');
      return;
    }
    _reconnectAttempts++;
    // Backoff: 1s, 2s, 3s, 4s, 5s, 5s, 5s...
    final secs = _reconnectAttempts < 5 ? _reconnectAttempts : 5;
    Future.delayed(Duration(seconds: secs), () => _doConnect());
  }

  void sendMessage(String message) {
    if (_channel != null) {
      _channel!.sink.add(jsonEncode({'message': message}));
    } else {
      onError?.call('Not connected. Reconnecting...');
      _tryReconnect();
    }
  }

  void disconnect() {
    _disposed = true;
    _channel?.sink.close();
    _channel = null;
  }
}
