/// Database notification model for in-app notifications.
///
/// Represents a notification stored in the database and displayed
/// in the notification dropdown.
class DatabaseNotification {
  /// Unique identifier
  final String id;

  /// Notification type (e.g., 'monitor_down', 'monitor_up')
  final String type;

  /// Notification title
  final String title;

  /// Notification body/message
  final String body;

  /// Additional data payload
  final Map<String, dynamic> data;

  /// URL to navigate to when notification is clicked (optional)
  final String? actionUrl;

  /// When the notification was created
  final DateTime createdAt;

  /// When the notification was read (null if unread)
  final DateTime? readAt;

  DatabaseNotification({
    required this.id,
    required this.type,
    required this.title,
    required this.body,
    required this.data,
    this.actionUrl,
    required this.createdAt,
    this.readAt,
  });

  /// Whether this notification has been read
  bool get isRead => readAt != null;

  /// [actionUrl] when it is a path inside this app, otherwise `null`.
  ///
  /// The backend owns `action_url`, and a router takes paths, not URLs, so a
  /// value is returned only when it starts with exactly one `/` and holds no
  /// backslash and no ASCII control character (below 0x20, or 0x7f), and its
  /// path still starts with one `/` once dot segments are resolved. A scheme
  /// (`https:`, `javascript:`), a host (`//host`, or `/.//host`, whose resolved
  /// path `//host` reads as a host if a parser takes it on its own) and a
  /// relative `x/y` are all answered with `null`,
  /// and so is an absolute URL to the app's own origin: the backend sends a
  /// path. Backslashes and control characters are refused because a URL parser
  /// reads `/\host` as `//host` and drops a tab or newline from `/<tab>/host`,
  /// which turns an apparent path into a host.
  ///
  /// Navigate with this rather than with [actionUrl]; a `null` means there is
  /// nowhere in the app to go.
  String? get inAppActionPath {
    final String? url = actionUrl;
    if (url == null || !url.startsWith('/') || url.startsWith('//')) {
      return null;
    }

    for (final int unit in url.codeUnits) {
      if (unit < 0x20 || unit == 0x7f || unit == 0x5c) {
        return null;
      }
    }

    final String? path = Uri.tryParse(url)?.path;
    if (path == null || path.startsWith('//')) {
      return null;
    }

    return url;
  }

  /// Parse from API response
  factory DatabaseNotification.fromMap(Map<String, dynamic> map) {
    final data = map['data'] as Map<String, dynamic>;

    return DatabaseNotification(
      id: map['id'] as String,
      type: map['type'] as String,
      title: data['title'] as String,
      body: data['body'] as String,
      data: data,
      actionUrl: data['action_url'] as String?,
      createdAt: DateTime.parse(map['created_at'] as String),
      readAt: map['read_at'] != null
          ? DateTime.parse(map['read_at'] as String)
          : null,
    );
  }

  /// Convert to map for API requests
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'type': type,
      'data': {
        'title': title,
        'body': body,
        if (actionUrl != null) 'action_url': actionUrl,
        ...data,
      },
      'created_at': createdAt.toIso8601String(),
      if (readAt != null) 'read_at': readAt!.toIso8601String(),
    };
  }

  /// Create a copy with modified fields
  DatabaseNotification copyWith({
    String? id,
    String? type,
    String? title,
    String? body,
    Map<String, dynamic>? data,
    String? actionUrl,
    DateTime? createdAt,
    DateTime? readAt,
  }) {
    return DatabaseNotification(
      id: id ?? this.id,
      type: type ?? this.type,
      title: title ?? this.title,
      body: body ?? this.body,
      data: data ?? this.data,
      actionUrl: actionUrl ?? this.actionUrl,
      createdAt: createdAt ?? this.createdAt,
      readAt: readAt ?? this.readAt,
    );
  }
}
