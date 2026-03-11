import 'dart:async';
import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';

enum WsState { disconnected, connecting, connected }

class WebSocketService {
  WebSocketChannel? _channel;
  String? _sessionId;
  String? _token;
  String? _connectSessionId;
  WsState _state = WsState.disconnected;

  // Structured event callbacks
  Function(String)? onText;
  Function(Map<String, dynamic>)? onToolUse;
  Function(Map<String, dynamic>)? onToolResult;
  Function(Map<String, dynamic>)? onDone;
  Function(String)? onStatus;
  Function(String)? onSessionId;
  Function(String)? onError;
  Function(WsState)? onStateChange;

  String? get sessionId => _sessionId;
  WsState get state => _state;

  bool _disposed = false;
  int _reconnectAttempts = 0;
  static const _maxReconnectAttempts = 15;
  Completer<bool>? _authCompleter;
  final List<String> _pendingMessages = [];

  void _setState(WsState s) {
    _state = s;
    onStateChange?.call(s);
  }

  Future<bool> connect(String sessionId, String token) async {
    _connectSessionId = sessionId;
    _token = token;
    _disposed = false;
    _reconnectAttempts = 0;
    return _doConnect();
  }

  Future<bool> _doConnect() async {
    if (_disposed) return false;
    _setState(WsState.connecting);

    try {
      final sid = _sessionId ?? _connectSessionId!;
      final wsUrl = 'ws://46.224.150.45/claude-remote/api/sessions/ws/$sid';
      _channel = WebSocketChannel.connect(Uri.parse(wsUrl));

      _authCompleter = Completer<bool>();

      _channel!.sink.add(jsonEncode({'token': _token}));

      _channel!.stream.listen(
        (data) {
          _reconnectAttempts = 0;
          final msg = jsonDecode(data);
          final type = msg['type'] ?? '';

          switch (type) {
            case 'auth_ok':
              _setState(WsState.connected);
              if (_authCompleter != null && !_authCompleter!.isCompleted) {
                _authCompleter!.complete(true);
              }
              _flushPending();
              break;
            case 'session_id':
              _sessionId = msg['session_id'];
              onSessionId?.call(_sessionId!);
              break;
            case 'text':
              onText?.call(msg['text'] ?? '');
              break;
            case 'tool_use':
              onToolUse?.call(msg);
              break;
            case 'tool_result':
              onToolResult?.call(msg);
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
              _channel?.sink.add(jsonEncode({'type': 'pong'}));
              break;
          }
        },
        onError: (e) {
          _channel = null;
          _setState(WsState.disconnected);
          if (_authCompleter != null && !_authCompleter!.isCompleted) {
            _authCompleter!.complete(false);
          }
          _tryReconnect();
        },
        onDone: () {
          _channel = null;
          _setState(WsState.disconnected);
          if (_authCompleter != null && !_authCompleter!.isCompleted) {
            _authCompleter!.complete(false);
          }
          _tryReconnect();
        },
      );

      final ok = await _authCompleter!.future
          .timeout(const Duration(seconds: 10), onTimeout: () => false);

      if (!ok && !_disposed) {
        _channel?.sink.close();
        _channel = null;
        _setState(WsState.disconnected);
        _tryReconnect();
      }
      return ok;
    } catch (e) {
      _channel = null;
      _setState(WsState.disconnected);
      if (_authCompleter != null && !_authCompleter!.isCompleted) {
        _authCompleter!.complete(false);
      }
      _tryReconnect();
      return false;
    }
  }

  void _flushPending() {
    while (_pendingMessages.isNotEmpty && _channel != null) {
      _channel!.sink.add(_pendingMessages.removeAt(0));
    }
  }

  void _tryReconnect() {
    if (_disposed || _token == null) return;
    if (_reconnectAttempts >= _maxReconnectAttempts) {
      onError?.call('Connection lost after $_maxReconnectAttempts attempts');
      return;
    }
    _reconnectAttempts++;
    _setState(WsState.connecting);
    final secs = _reconnectAttempts < 5 ? _reconnectAttempts : 5;
    Future.delayed(Duration(seconds: secs), () => _doConnect());
  }

  void sendMessage(String message) {
    final payload = jsonEncode({'message': message});
    if (_state == WsState.connected && _channel != null) {
      _channel!.sink.add(payload);
    } else {
      _pendingMessages.add(payload);
      if (_state == WsState.disconnected) {
        _tryReconnect();
      }
    }
  }

  void disconnect() {
    _disposed = true;
    _pendingMessages.clear();
    _channel?.sink.close();
    _channel = null;
    _setState(WsState.disconnected);
  }
}
