import 'package:flutter_test/flutter_test.dart';
import 'package:magic_notifications/magic_notifications.dart';

void main() {
  group('DatabaseNotification', () {
    test('fromMap() parses API response', () {
      final map = {
        'id': 'uuid-123',
        'type': 'monitor_down',
        'data': {
          'title': 'Monitor Down',
          'body': 'api.example.com is not responding',
          'action_url': '/monitors/1',
        },
        'created_at': '2026-02-03T12:00:00.000Z',
        'read_at': null,
      };

      final notification = DatabaseNotification.fromMap(map);

      expect(notification.id, 'uuid-123');
      expect(notification.type, 'monitor_down');
      expect(notification.title, 'Monitor Down');
      expect(notification.body, 'api.example.com is not responding');
      expect(notification.actionUrl, '/monitors/1');
      expect(notification.isRead, isFalse);
      expect(notification.createdAt, isA<DateTime>());
    });

    test('fromMap() handles read notification', () {
      final map = {
        'id': 'uuid-123',
        'type': 'monitor_up',
        'data': {'title': 'Monitor Up', 'body': 'Back online'},
        'created_at': '2026-02-03T12:00:00.000Z',
        'read_at': '2026-02-03T12:05:00.000Z',
      };

      final notification = DatabaseNotification.fromMap(map);
      expect(notification.isRead, isTrue);
      expect(notification.readAt, isA<DateTime>());
    });

    test('fromMap() handles missing optional fields', () {
      final map = {
        'id': 'uuid-123',
        'type': 'test',
        'data': {'title': 'Test', 'body': 'Body'},
        'created_at': '2026-02-03T12:00:00.000Z',
      };

      final notification = DatabaseNotification.fromMap(map);
      expect(notification.actionUrl, isNull);
      expect(notification.readAt, isNull);
    });

    group('inAppActionPath', () {
      DatabaseNotification withActionUrl(String? actionUrl) {
        return DatabaseNotification(
          id: '1',
          type: 'test',
          title: 'Test',
          body: 'Body',
          data: {},
          actionUrl: actionUrl,
          createdAt: DateTime(2026, 2, 3),
        );
      }

      const accepted = <String>['/', '/x', '/x/y?a=1#f', '/monitors/1'];

      for (final path in accepted) {
        test('returns $path as it is', () {
          expect(withActionUrl(path).inAppActionPath, path);
        });
      }

      const rejected = <String, String?>{
        'null': null,
        'an empty string': '',
        'an https URL': 'https://evil.example/x',
        'a protocol-relative URL': '//evil.example/x',
        'a javascript: URL': 'javascript:x',
        'an upper-case scheme URL': 'HTTP://evil.example/admin',
        'a mailto: URL': 'mailto:a@b.c',
        'a relative path': 'x/y',
        'a leading backslash host': r'/\evil.example',
        'a backslash inside the path': r'/x\y',
        'a tab': '/\t/evil.example',
        'a newline': '/x\ny',
        'a carriage return': '/x\ry',
        'a NUL': '/x\u0000y',
        'a DEL': '/x\u007fy',
        'a dot segment that resolves to a host': '/.//evil.example/x',
        'two dot segments that resolve to a host': '/..//evil.example/x',
        'a path that climbs out to a host': '/x/../..//evil.example',
        'an absolute URL to the same origin': 'https://app.example.com/x',
      };

      rejected.forEach((label, value) {
        test('returns null for $label', () {
          expect(withActionUrl(value).inAppActionPath, isNull);
        });
      });

      test('leaves actionUrl as the raw value', () {
        expect(
          withActionUrl('https://evil.example/x').actionUrl,
          'https://evil.example/x',
        );
      });
    });

    test('copyWith() creates modified copy', () {
      final original = DatabaseNotification(
        id: '1',
        type: 'test',
        title: 'Test',
        body: 'Body',
        data: {},
        createdAt: DateTime(2026, 2, 3, 12, 0),
      );

      final modified = original.copyWith(readAt: DateTime(2026, 2, 3, 12, 5));

      expect(original.isRead, isFalse);
      expect(original.readAt, isNull);
      expect(modified.isRead, isTrue);
      expect(modified.readAt, isNotNull);
      expect(modified.id, original.id);
      expect(modified.title, original.title);
    });

    test('copyWith() preserves unchanged fields', () {
      final original = DatabaseNotification(
        id: '1',
        type: 'test',
        title: 'Test',
        body: 'Body',
        data: {'key': 'value'},
        actionUrl: '/test',
        createdAt: DateTime(2026, 2, 3),
      );

      final modified = original.copyWith();

      expect(modified.id, original.id);
      expect(modified.type, original.type);
      expect(modified.title, original.title);
      expect(modified.body, original.body);
      expect(modified.actionUrl, original.actionUrl);
    });

    test('toMap() serializes correctly', () {
      final notification = DatabaseNotification(
        id: 'uuid-123',
        type: 'monitor_down',
        title: 'Monitor Down',
        body: 'Error',
        data: {'monitor_id': 1},
        actionUrl: '/monitors/1',
        createdAt: DateTime(2026, 2, 3, 12, 0),
        readAt: DateTime(2026, 2, 3, 12, 5),
      );

      final map = notification.toMap();

      expect(map['id'], 'uuid-123');
      expect(map['type'], 'monitor_down');
      expect(map['data']['title'], 'Monitor Down');
      expect(map['data']['body'], 'Error');
      expect(map['data']['action_url'], '/monitors/1');
      expect(map['data']['monitor_id'], 1);
      expect(map['created_at'], isA<String>());
      expect(map['read_at'], isA<String>());
    });
  });
}
