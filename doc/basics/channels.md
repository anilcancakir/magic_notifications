# Channels

How a notification reaches its channels: the `NotificationChannel` contract, the database and push channels the package registers, and how to add your own.

- [Channel Concept](#concept)
- [NotificationChannel Interface](#interface)
- [DatabaseChannel](#database-channel)
- [PushChannel](#push-channel)
- [Creating Custom Channels](#custom-channels)
- [Channel Registration](#registration)
- [Gotchas](#gotchas)
- [Related Documentation](#related-documentation)

<a name="concept"></a>
## Channel Concept

A channel is a delivery mechanism. `NotificationManager.send` asks the notification which channels it wants through `Notification.via()`, then dispatches to each registered channel in turn.

```dart
import 'package:magic_notifications/magic_notifications.dart';

class MonitorDownNotification extends Notification {
  @override
  List<String> via(Notifiable notifiable) => ['database', 'push'];
}

Future<void> alert(Notifiable user) async {
  await Notify.send(user, MonitorDownNotification());
}
```

Channels are identified by a string name. For each name the manager:

1. skips it with a logged warning when no channel is registered under it,
2. skips it when `isAvailable` is `false`,
3. awaits `channel.send(notifiable, notification)`.

Channels run one after another. A channel that throws does not stop the rest: the manager finishes the list, logs every later failure, and rethrows the first error once all channels have been tried.

Declaring a channel in `via()` is therefore safe without knowing at compile time whether the device supports it.

<a name="interface"></a>
## NotificationChannel Interface

```dart
import 'package:magic_notifications/magic_notifications.dart';

abstract class NotificationChannel {
  String get name;
  bool get isAvailable;
  Future<void> send(Notifiable notifiable, Notification notification);
}
```

| Member | Contract |
| :--- | :--- |
| `name` | The key used in `via()` and by `registerChannel` |
| `isAvailable` | A synchronous guard checked before every `send`; `false` skips the channel silently |
| `send` | The delivery logic; receives the target entity and the notification |

<a name="database-channel"></a>
## DatabaseChannel

`NotificationServiceProvider.boot()` registers `DatabaseChannel` whether or not push is configured. It is always available, and its `send` does nothing:

```dart
import 'package:magic_notifications/magic_notifications.dart';

class DatabaseChannel extends NotificationChannel {
  @override
  String get name => 'database';

  @override
  bool get isAvailable => true;

  @override
  Future<void> send(Notifiable notifiable, Notification notification) async {
    // Returns without doing anything: the backend owns the rows.
  }
}
```

### How It Works

The database channel is asymmetric:

1. **The backend creates**: the Laravel backend calls `$user->notify(new SomeNotification())`, which persists a row in the `notifications` table.
2. **The client reads**: `NotificationPoller` calls `NotificationManager.fetchNotifications()` every 30 seconds by default (`notifications.database.polling_interval`), which hits `GET /notifications`. With a socket, `Notify.startRealtime()` applies each pushed row instead.
3. **A stream emits**: results go to the broadcast stream behind `Notify.notifications()`.
4. **The UI reacts**: any widget listening to that stream receives the updated list.

`DatabaseChannel.send` exists for parity with Laravel's `via()` vocabulary. A client-created row is not supported by this channel; post to your backend's own endpoint for that.

**`DatabaseNotification` fields:**

| Field | Type | Description |
| :--- | :--- | :--- |
| `id` | `String` | Id from the backend |
| `type` | `String` | Notification type (for example `monitor_down`) |
| `title` | `String` | Read from `data['title']` |
| `body` | `String` | Read from `data['body']` |
| `data` | `Map<String, dynamic>` | The full `data` payload |
| `actionUrl` | `String?` | Read from `data['action_url']` |
| `createdAt` | `DateTime` | Creation timestamp |
| `readAt` | `DateTime?` | `null` while unread |
| `isRead` | `bool` | `readAt != null` |

<a name="push-channel"></a>
## PushChannel

`PushChannel` is registered when a push driver resolves. It is **self-addressed** and ships **switched off**.

| Property | Behaviour |
| :--- | :--- |
| `name` | `'push'` |
| `isAvailable` | `driver.isSupported` and `notifications.push.self_test_enabled` is `true`. With the switch off the manager skips the channel, so the other channels in `via()` still deliver. |
| Recipient | None. It posts to `POST /notifications/push-test` and the backend derives the recipient from the session, so the only person it can page is the authenticated one. A `Notifiable` whose `notifiableId` is not the signed-in user's id throws `NotificationException` with code `PUSH_RECIPIENT_NOT_AUTHENTICATED_USER`. |
| Payload | `title` (`heading`), `body` (`content`) and `data` from `toPush()`; a `url` set on the `PushMessage` is folded into `data['url']` unless `data` already has one. |
| Failure | A non-successful response throws `NotificationException` with code `HTTP_<status>`. |

Ordinary push to other people is sent by your backend through OneSignal; see [Laravel Backend Setup](./laravel-backend-setup.md#onesignal-push). This channel exists so a person can find out whether push reaches their own phone before an incident rather than during one. The backend carries the matching `magic-starter.onesignal.self_test_enabled` switch; enable both or neither.

### How It Works

1. With the switch off, `send` logs a debug line and returns.
2. A foreign recipient is refused with the exception above.
3. `toPush()` is called on the notification; a `null` return exits early.
4. When the `Notifiable` has a `notificationPreference`, `isEnabled(notification.type, 'push')` must be `true` (see [Preferences](./preferences.md#global-vs-type)).
5. The request is sent.

> [!TIP]
> Build the `toPush()` payload with `PushMessage`:
> ```dart
> import 'package:magic_notifications/magic_notifications.dart';
>
> /// The host app's model.
> class Monitor {
>   const Monitor(this.id);
>
>   final int id;
> }
>
> class MonitorDownNotification extends Notification {
>   MonitorDownNotification(this.monitor);
>
>   final Monitor monitor;
>
>   @override
>   List<String> via(Notifiable notifiable) => ['push'];
>
>   @override
>   PushMessage? toPush(Notifiable notifiable) {
>     return PushMessage()
>         .heading('Monitor Down')
>         .content('api.example.com is not responding')
>         .data({'monitor_id': monitor.id})
>         .url('/monitors/${monitor.id}');
>   }
> }
> ```

<a name="custom-channels"></a>
## Creating Custom Channels

Extend `NotificationChannel` for any other delivery mechanism:

```dart
import 'package:magic/magic.dart';
import 'package:magic_notifications/magic_notifications.dart';

class SlackChannel extends NotificationChannel {
  final String _webhookUrl;

  SlackChannel(this._webhookUrl);

  @override
  String get name => 'slack';

  @override
  bool get isAvailable => _webhookUrl.isNotEmpty;

  @override
  Future<void> send(Notifiable notifiable, Notification notification) async {
    final data = notification.toDatabase(notifiable);
    if (data == null) return;

    await Http.post(_webhookUrl, data: {
      'text': '${data['title']}: ${data['body']}',
    });
  }
}
```

Then name it in `via()`:

```dart
import 'package:magic_notifications/magic_notifications.dart';

class DeployFinishedNotification extends Notification {
  @override
  List<String> via(Notifiable notifiable) => ['database', 'slack'];
}
```

<a name="registration"></a>
## Channel Registration

`NotificationServiceProvider` registers `database` and `push` itself. Register any other channel from the `boot()` of a provider of your own:

```dart
import 'package:magic/magic.dart';
import 'package:magic_notifications/magic_notifications.dart';

// The host's own channel from the section above, and its webhook url.
const String webhookUrl = 'https://hooks.example.com/slack';

class SlackServiceProvider extends ServiceProvider {
  SlackServiceProvider(super.app);

  @override
  void register() {}

  @override
  Future<void> boot() async {
    NotificationManager().registerChannel(SlackChannel(webhookUrl));
  }
}
```

Registering a name that already exists replaces the previous instance, which is how a test swaps in a fake. `hasChannel` answers whether a name is registered:

```dart
import 'package:magic_notifications/magic_notifications.dart';

bool hasPushChannel() {
  final bool exists = NotificationManager().hasChannel('push');

  return exists;
}
```

<a name="gotchas"></a>
## Gotchas

| Mistake | Fix |
| :--- | :--- |
| Expecting `DatabaseChannel.send` to store a row | It does nothing. The backend creates database notifications; the client reads them with `Notify.notifications()` and polling or realtime. |
| Listing `'push'` in `via()` and seeing nothing happen | `PushChannel` is unavailable until `notifications.push.self_test_enabled` is `true` and the driver is supported. It only reaches the signed-in user. Send push to other people from your backend. |
| Listing `'mail'` in `via()` | The package has no mail channel. The manager logs `Unknown notification channel: mail` and skips it; send mail from the backend. |
| Assuming one failing channel blocks the next | It does not. Every channel is tried, then the first error is rethrown from `send`; wrap the call if a failure must not surface. |
| `Notification` is ambiguous after importing Flutter | Flutter's widgets library also exports `Notification`. Import it with `hide Notification` (`import 'package:flutter/widgets.dart' hide Notification;`). |

<a name="related-documentation"></a>
## Related Documentation

- [Drivers](./drivers.md): the push SDK layer behind `PushChannel`.
- [Preferences](./preferences.md): the per-type and per-channel opt-outs `PushChannel` honours.
- [Notification Manager](../architecture/notification-manager.md): dispatch, polling and realtime.
- [Laravel Backend Setup](./laravel-backend-setup.md): the backend that creates the rows and sends the pushes.
- [Realtime channels with magic_socket](https://anilcancakir.com/magic_socket/docs/basics/channels): the socket layer `Notify.startRealtime` subscribes through.
