import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../services/websocket_service.dart';
import '../models/message_model.dart';

/// An event in the agent conversation
class _AgentEvent {
  final String type; // 'user', 'text', 'tool_use', 'tool_result', 'status'
  String text;
  String? toolName;
  String? toolInput;
  String? toolOutput;
  bool isError;
  bool isStreaming;

  _AgentEvent({
    required this.type,
    this.text = '',
    this.toolName,
    this.toolInput,
    this.toolOutput,
    this.isError = false,
    this.isStreaming = false,
  });
}

class ChatScreen extends StatefulWidget {
  final ApiService apiService;
  final String sessionId;
  final String title;

  const ChatScreen({
    super.key,
    required this.apiService,
    required this.sessionId,
    required this.title,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> with WidgetsBindingObserver {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  final _ws = WebSocketService();
  List<_AgentEvent> _events = [];
  bool _loading = true;
  bool _sending = false;
  String _status = '';
  WsState _wsState = WsState.disconnected;
  late String _sessionId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _sessionId = widget.sessionId;
    _loadHistory();
    _connectWs();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _wsState != WsState.connected) {
      _connectWs();
    }
  }

  Future<void> _loadHistory() async {
    if (_sessionId != 'new') {
      final msgs = await widget.apiService.getMessages(_sessionId);
      setState(() {
        _events = msgs.map((m) => _AgentEvent(
          type: m.isUser ? 'user' : 'text',
          text: m.text,
        )).toList();
        _loading = false;
      });
      _scrollToBottom();
    } else {
      setState(() => _loading = false);
    }
  }

  Future<void> _connectWs() async {
    _ws.onText = (text) {
      setState(() {
        // Append to last text event if streaming, or create new
        if (_events.isNotEmpty && _events.last.type == 'text' && _events.last.isStreaming) {
          _events.last.text += text;
        } else {
          _events.add(_AgentEvent(type: 'text', text: text, isStreaming: true));
        }
      });
      _scrollToBottom();
    };

    _ws.onToolUse = (data) {
      setState(() {
        _events.add(_AgentEvent(
          type: 'tool_use',
          toolName: data['name'] ?? 'Tool',
          toolInput: data['input'] ?? '',
          isStreaming: true,
        ));
        _status = 'running ${data['name']}';
      });
      _scrollToBottom();
    };

    _ws.onToolResult = (data) {
      setState(() {
        // Find the matching tool_use and update it, or add standalone
        final toolId = data['tool_id'];
        _AgentEvent? matchingTool;
        for (int i = _events.length - 1; i >= 0; i--) {
          if (_events[i].type == 'tool_use' && _events[i].isStreaming) {
            matchingTool = _events[i];
            break;
          }
        }
        if (matchingTool != null) {
          matchingTool.toolOutput = data['output'] ?? '';
          matchingTool.isError = data['is_error'] == true;
          matchingTool.isStreaming = false;
        } else {
          _events.add(_AgentEvent(
            type: 'tool_result',
            toolName: data['name'] ?? 'Tool',
            toolOutput: data['output'] ?? '',
            isError: data['is_error'] == true,
          ));
        }
        _status = '';
      });
      _scrollToBottom();
    };

    _ws.onDone = (result) {
      final error = result['error'];
      setState(() {
        if (error != null) {
          _events.add(_AgentEvent(type: 'text', text: 'Error: $error', isError: true));
        } else {
          // Mark any streaming text as complete
          for (var e in _events) {
            e.isStreaming = false;
          }
          // Add cost info
          final cost = result['cost_usd'];
          final duration = result['duration_ms'];
          if (cost != null && cost > 0) {
            final durSec = duration != null ? (duration / 1000).toStringAsFixed(1) : '?';
            _events.add(_AgentEvent(
              type: 'status',
              text: '\$${cost.toStringAsFixed(4)} · ${durSec}s',
            ));
          }
        }
        _sending = false;
        _status = '';
      });
      _scrollToBottom();
    };

    _ws.onStatus = (status) {
      setState(() => _status = status);
    };

    _ws.onSessionId = (id) {
      setState(() => _sessionId = id);
    };

    _ws.onError = (error) {
      setState(() {
        _sending = false;
        _status = '';
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $error'), duration: const Duration(seconds: 2)),
        );
      }
    };

    _ws.onStateChange = (state) {
      if (mounted) setState(() => _wsState = state);
    };

    await _ws.connect(_sessionId, widget.apiService.token!);
  }

  void _sendMessage() {
    final text = _controller.text.trim();
    if (text.isEmpty || _sending) return;

    setState(() {
      _events.add(_AgentEvent(type: 'user', text: text));
      _sending = true;
      _status = 'thinking';
    });
    _controller.clear();
    _ws.sendMessage(text);
    _scrollToBottom();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ws.disconnect();
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1a1a2e),
      appBar: AppBar(
        title: Text(
          _sessionId == 'new' ? 'New Session' : widget.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 16),
        ),
        backgroundColor: const Color(0xFF16213e),
        foregroundColor: Colors.white,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Icon(
              Icons.circle,
              size: 10,
              color: _wsState == WsState.connected
                  ? Colors.green
                  : _wsState == WsState.connecting
                      ? Colors.orange
                      : Colors.red,
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          if (_wsState == WsState.connecting)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 4),
              color: Colors.orange.withValues(alpha: 0.2),
              child: const Text(
                'Connecting...',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.orange, fontSize: 12),
              ),
            ),
          if (_wsState == WsState.disconnected)
            GestureDetector(
              onTap: _connectWs,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 4),
                color: Colors.red.withValues(alpha: 0.2),
                child: const Text(
                  'Disconnected. Tap to reconnect.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.red, fontSize: 12),
                ),
              ),
            ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator(color: Color(0xFFe94560)))
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(10),
                    itemCount: _events.length,
                    itemBuilder: (ctx, i) => _buildEvent(_events[i]),
                  ),
          ),
          if (_status.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
              child: Row(
                children: [
                  const SizedBox(
                    width: 14, height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFFe94560)),
                  ),
                  const SizedBox(width: 8),
                  Text(_status, style: TextStyle(color: Colors.grey[500], fontSize: 13)),
                ],
              ),
            ),
          _buildInput(),
        ],
      ),
    );
  }

  Widget _buildEvent(_AgentEvent event) {
    switch (event.type) {
      case 'user':
        return _buildUserBubble(event);
      case 'text':
        return _buildTextBubble(event);
      case 'tool_use':
        return _buildToolCard(event);
      case 'tool_result':
        return _buildToolResultCard(event);
      case 'status':
        return _buildStatusLine(event);
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _buildUserBubble(_AgentEvent event) {
    return Align(
      alignment: Alignment.centerRight,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.85,
        ),
        decoration: BoxDecoration(
          color: const Color(0xFFe94560),
          borderRadius: BorderRadius.circular(16),
        ),
        child: SelectableText(
          event.text,
          style: const TextStyle(color: Colors.white, fontSize: 15, height: 1.4),
        ),
      ),
    );
  }

  Widget _buildTextBubble(_AgentEvent event) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.92,
        ),
        decoration: BoxDecoration(
          color: event.isError ? const Color(0xFF3a1020) : const Color(0xFF16213e),
          borderRadius: BorderRadius.circular(16),
        ),
        child: SelectableText(
          event.text + (event.isStreaming ? ' \u258c' : ''),
          style: TextStyle(
            color: event.isError ? const Color(0xFFff6b8a) : Colors.white,
            fontSize: 14,
            height: 1.5,
          ),
        ),
      ),
    );
  }

  Widget _buildToolCard(_AgentEvent event) {
    final hasOutput = event.toolOutput != null && event.toolOutput!.isNotEmpty;
    final icon = event.isStreaming
        ? Icons.hourglass_top
        : event.isError
            ? Icons.cancel
            : Icons.check_circle;
    final iconColor = event.isStreaming
        ? Colors.orange
        : event.isError
            ? const Color(0xFFe94560)
            : const Color(0xFF4ade80);

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFF0f1829),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.04),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
            ),
            child: Row(
              children: [
                Icon(icon, size: 16, color: iconColor),
                const SizedBox(width: 8),
                Text(
                  event.toolName ?? 'Tool',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
                if (event.isStreaming) ...[
                  const SizedBox(width: 8),
                  const SizedBox(
                    width: 12, height: 12,
                    child: CircularProgressIndicator(strokeWidth: 1.5, color: Colors.orange),
                  ),
                ],
              ],
            ),
          ),
          // Input/command
          if (event.toolInput != null && event.toolInput!.isNotEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Text(
                  event.toolInput!,
                  style: TextStyle(
                    color: Colors.grey[400],
                    fontSize: 12,
                    fontFamily: 'monospace',
                    height: 1.4,
                  ),
                ),
              ),
            ),
          // Output
          if (hasOutput)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
              constraints: const BoxConstraints(maxHeight: 200),
              child: SingleChildScrollView(
                child: Text(
                  event.toolOutput!,
                  style: TextStyle(
                    color: event.isError ? const Color(0xFFff6b8a) : Colors.grey[500],
                    fontSize: 11,
                    fontFamily: 'monospace',
                    height: 1.3,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildToolResultCard(_AgentEvent event) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFF0f1829),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      constraints: const BoxConstraints(maxHeight: 200),
      child: SingleChildScrollView(
        child: Text(
          event.toolOutput ?? '',
          style: TextStyle(
            color: event.isError ? const Color(0xFFff6b8a) : Colors.grey[500],
            fontSize: 11,
            fontFamily: 'monospace',
            height: 1.3,
          ),
        ),
      ),
    );
  }

  Widget _buildStatusLine(_AgentEvent event) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Text(
        event.text,
        textAlign: TextAlign.center,
        style: TextStyle(color: Colors.grey[600], fontSize: 11),
      ),
    );
  }

  Widget _buildInput() {
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
      color: const Color(0xFF16213e),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _controller,
                style: const TextStyle(color: Colors.white, fontSize: 15),
                maxLines: 4,
                minLines: 1,
                decoration: InputDecoration(
                  hintText: 'Message Claude...',
                  hintStyle: TextStyle(color: Colors.grey[600]),
                  filled: true,
                  fillColor: const Color(0xFF1a1a2e),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(20),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                ),
                onSubmitted: (_) => _sendMessage(),
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              icon: Icon(
                Icons.send,
                color: _sending ? Colors.grey[600] : const Color(0xFFe94560),
              ),
              onPressed: _sending ? null : _sendMessage,
            ),
          ],
        ),
      ),
    );
  }
}
