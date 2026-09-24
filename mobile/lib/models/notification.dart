/// One message in the user's inbox -- mirrors the backend's
/// NotificationOut exactly.
///
/// `source` is provenance, not behaviour: "manual" for a message an admin
/// wrote, and whatever a future automatic rule stamps. This screen renders
/// every message the same way; the field exists so the two never need to
/// become different kinds of row.
class AppNotification {
  final int id;
  final String? title;
  final String body;
  final String source;
  final bool isRead;
  final DateTime? readAt;
  final DateTime createdAt;

  AppNotification({
    required this.id,
    required this.title,
    required this.body,
    required this.source,
    required this.isRead,
    required this.readAt,
    required this.createdAt,
  });

  factory AppNotification.fromJson(Map<String, dynamic> json) {
    return AppNotification(
      id: json['id'] as int,
      title: json['title'] as String?,
      body: json['body'] as String,
      source: json['source'] as String,
      isRead: json['is_read'] as bool,
      readAt: json['read_at'] == null ? null : DateTime.parse(json['read_at'] as String).toLocal(),
      createdAt: DateTime.parse(json['created_at'] as String).toLocal(),
    );
  }
}

/// The inbox plus the one number the bell's indicator is drawn from -- the
/// backend counts unread messages, this app never does.
class NotificationInbox {
  final int unreadCount;
  final List<AppNotification> items;

  NotificationInbox({required this.unreadCount, required this.items});

  factory NotificationInbox.fromJson(Map<String, dynamic> json) {
    return NotificationInbox(
      unreadCount: json['unread_count'] as int,
      items: (json['items'] as List<dynamic>)
          .map((e) => AppNotification.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}
