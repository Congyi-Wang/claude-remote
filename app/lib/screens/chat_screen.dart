import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../services/websocket_service.dart';
import '../models/message_model.dart';
import '../widgets/message_bubble.dart';

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

class _ChatScreenState extends State<ChatScreen> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  final _ws = WebSocketService();
  List<MessageModel> _messages = [];
  String _streamingText = '';
  bool _loading = true;
  bool _sending = false;
  String _status = '';
  late String _sessionId;

  @override
  void initState() {
    super.initState();
    _sessionId = widget.sessionId;
    _loadHistory();
    _connectWs();
  }

  Future<void> _loadHistory() async {
    if (_sessionId != 'new') {
      final msgs = await widget.apiService.getMessages(_sessionId);
      setState(() {
        _messages = msgs;
        _loading = false;
      });
      _scrollToBottom();
    } else {
      setState(() => _loading = false);
    }
  }

  Future<void> _connectWs() async {
    _ws.onChunk = (text) {
      setState(() {
        _streamingText += text;
      });
      _scrollToBottom();
    };

    _ws.onDone = (result) {
      final error = result['error'];
      if (error != null) {
        setState(() {
          _streamingText = '';
          _sending = false;
          _status = '';
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error: $error')),
          );
        }
        return;
      }
      final text = _streamingText.isNotEmpty
          ? _streamingText
          : result['text'] ?? '';
      setState(() {
        if (text.isNotEmpty) {
          _messages.add(MessageModel(role: 'assistant', text: text));
        }
        _streamingText = '';
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
          SnackBar(content: Text('Error: $error')),
        );
      }
    };

    await _ws.connect(_sessionId, widget.apiService.token!);
  }

  void _sendMessage() {
    final text = _controller.text.trim();
    if (text.isEmpty || _sending) return;

    setState(() {
      _messages.add(MessageModel(role: 'user', text: text));
      _sending = true;
      _streamingText = '';
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
        ),
        backgroundColor: const Color(0xFF16213e),
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          Expanded(
            child: _loading
                ? const Center(
                    child: CircularProgressIndicator(color: Color(0xFFe94560)))
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(12),
                    itemCount: _messages.length + (_streamingText.isNotEmpty ? 1 : 0),
                    itemBuilder: (ctx, i) {
                      if (i < _messages.length) {
                        return MessageBubble(message: _messages[i]);
                      }
                      // Streaming message
                      return MessageBubble(
                        message: MessageModel(
                          role: 'assistant',
                          text: _streamingText,
                        ),
                        isStreaming: true,
                      );
                    },
                  ),
          ),
          if (_status.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Row(
                children: [
                  const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Color(0xFFe94560),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _status,
                    style: TextStyle(color: Colors.grey[500], fontSize: 13),
                  ),
                ],
              ),
            ),
          _buildInput(),
        ],
      ),
    );
  }

  Widget _buildInput() {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      color: const Color(0xFF16213e),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _controller,
                style: const TextStyle(color: Colors.white),
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
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
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
