import 'package:flutter/material.dart';
import '../models/message_model.dart';

class MessageBubble extends StatelessWidget {
  final MessageModel message;
  final bool isStreaming;

  const MessageBubble({
    super.key,
    required this.message,
    this.isStreaming = false,
  });

  @override
  Widget build(BuildContext context) {
    final isUser = message.isUser;
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.85,
        ),
        decoration: BoxDecoration(
          color: isUser
              ? const Color(0xFFe94560)
              : const Color(0xFF16213e),
          borderRadius: BorderRadius.circular(16),
        ),
        child: SelectableText(
          message.text + (isStreaming ? ' ▌' : ''),
          style: TextStyle(
            color: Colors.white,
            fontSize: 14,
            height: 1.4,
            fontFamily: isUser ? null : 'monospace',
          ),
        ),
      ),
    );
  }
}
