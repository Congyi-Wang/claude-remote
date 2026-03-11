class SessionModel {
  final String id;
  final String title;
  final String slug;
  final int messageCount;
  final String updatedAt;
  final bool active;

  SessionModel({
    required this.id,
    required this.title,
    this.slug = '',
    this.messageCount = 0,
    this.updatedAt = '',
    this.active = false,
  });

  factory SessionModel.fromJson(Map<String, dynamic> json) {
    return SessionModel(
      id: json['id'] ?? '',
      title: json['title'] ?? '',
      slug: json['slug'] ?? '',
      messageCount: json['message_count'] ?? 0,
      updatedAt: json['updated_at'] ?? '',
      active: json['active'] ?? false,
    );
  }
}
