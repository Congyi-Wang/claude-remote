class MessageModel {
  final String role;
  final String text;
  final String timestamp;

  MessageModel({
    required this.role,
    required this.text,
    this.timestamp = '',
  });

  factory MessageModel.fromJson(Map<String, dynamic> json) {
    return MessageModel(
      role: json['role'] ?? '',
      text: json['text'] ?? '',
      timestamp: json['timestamp'] ?? '',
    );
  }

  bool get isUser => role == 'user';
  bool get isAssistant => role == 'assistant';
}
