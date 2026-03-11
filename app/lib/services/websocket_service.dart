import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';

class WebSocketService {
  WebSocketChannel? _channel;
  String? _sessionId;
  Function(String)? onChunk;
  Function(Map<String, dynamic>)? onDone;
  Function(String)? onStatus;
  Function(String)? onSessionId;
  Function(String)? onError;

  String? get sessionId => _sessionId;
  bool get isConnected => _channel != null;

  Future<bool> connect(String sessionId, String token) async {
    try {
      final wsUrl = 'ws://46.224.150.45/claude-remote/api/sessions/ws/$sessionId';
      _channel = WebSocketChannel.connect(Uri.parse(wsUrl));

      // Send auth token
      _channel!.sink.add(jsonEncode({'token': token}));

      _channel!.stream.listen(
        (data) {
          final msg = jsonDecode(data);
          final type = msg['type'] ?? '';

          switch (type) {
            case 'auth_ok':
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
          }
        },
        onError: (e) {
          onError?.call(e.toString());
        },
        onDone: () {
          _channel = null;
        },
      );

      // Wait a moment for auth response
      await Future.delayed(const Duration(milliseconds: 500));
      return true;
    } catch (e) {
      onError?.call(e.toString());
      return false;
    }
  }

  void sendMessage(String message) {
    if (_channel != null) {
      _channel!.sink.add(jsonEncode({'message': message}));
    }
  }

  void disconnect() {
    _channel?.sink.close();
    _channel = null;
  }
}
