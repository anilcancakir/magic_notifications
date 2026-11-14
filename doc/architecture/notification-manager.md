# Notification Manager

How `NotificationManager` orchestrates channels, the push driver, polling, realtime delivery and the in-app notification stream.

- [Singleton Lifecycle](#singleton)
- [Channel Registration](#channels)
- [Push Driver Setup](#push-driver)
- [Send Dispatch Flow](#send-flow)
- [Polling Orchestration](#polling)
- [Realtime Delivery](#realtime)
- [Stream Management](#streams)
- [Optimistic Updates with Rollback](#optimistic)
- [Push Identity Reconcile Outcomes](#identity-reconciled)
- [Related Documentation](#related-documentation)

<a name="singleton"></a>
## Singleton Lifecycle

`NotificationManager` is a process-level singleton, built with a Dart factory constructor:

Excerpt of `lib/src/notification_manager.dart`:

```dart
class NotificationManager {
  static final NotificationManager _instance = NotificationManager._internal();

  factory NotificationManager() {
    return _instance;
  }

  NotificationManager._internal();
}
```

Every `NotificationManager()` call returns the same `_instance`, and the `Notify` facade delegates to it:

Excerpt of `lib/src/facades/notify.dart`:

```dart
class Notify {
  static NotificationManager get manager => NotificationManager();
}
```

`NotificationManager()`, `Notify.manager` and `Magic.make<NotificationManager>('notifications')` are identical references, so state set through one is visible through the others. The instance lives for the application's lifetime; there is no `dispose`.

> [!NOTE]
> In tests, call `forgetDrivers()` between tests. It clears every channel, every registered push driver factory, every resolved driver, the push intent and the in-flight reads, in one call.

<a name="channels"></a>
## Channel Registration

Channels live in a `Map<String, NotificationChannel>` keyed by `channel.name`:

Excerpt of `lib/src/notification_manager.dart`:

```dart
void registerChannel(NotificationChannel channel) {
  _channels[channel.name] = channel;
}

bool hasChannel(String name) {
  return _channels.containsKey(name);
}
```

Registering a name that exists replaces the previous instance, which is how a test swaps in a fake. `NotificationServiceProvider.boot()` registers the standard channels:

| Name | Class | Registered |
| :--- | :--- | :--- |
| `'database'` | `DatabaseChannel` | Always |
| `'push'` | `PushChannel(driver)` | When a push driver resolves |

<a name="push-driver"></a>
## Push Driver Setup

The push driver resolves lazily through a name-keyed factory registry, not a single field the provider must fill before anything else runs:

Excerpt of `lib/src/notification_manager.dart`:

```dart
void extend(String name, PushDriver Function() factory) {
  _pushFactories[name] = factory;
  _resolvedPushDriver = null;
  if (_pushDriver == null) _detachPushDriver();
}

PushDriver? get pushDriverOrNull {
  if (_pushDriver != null) return _pushDriver;
  if (_resolvedPushDriver != null) return _resolvedPushDriver;

  final factory = _pushFactory();
  if (factory == null) return null;

  final created = factory();
  _resolvedPushDriver = created;
  _attachPushDriver(created);
  return created;
}

PushDriver get pushDriver {
  final driver = pushDriverOrNull;
  if (driver == null) {
    throw NotificationException(
      'Push driver not configured. Register one with Notify.extend(name, '
      'factory), or set one explicitly with setPushDriver().',
      code: 'PUSH_DRIVER_NOT_CONFIGURED',
    );
  }
  return driver;
}
```

Resolution order for `pushDriver` and `pushDriverOrNull`: the instance `setPushDriver()` was given (the escape hatch for a consumer holding an already-built driver), then a previously resolved registry instance, then a fresh build from the registry. `_pushFactory()` picks the factory named by `notifications.push.driver` when that key is set, and falls back to the single registered factory when there is exactly one and no config names another. With two or more factories and no matching name there is no unambiguous answer, and a call site that only asks whether push is configured gets `pushDriverOrNull == null` instead of a throw.

Resolving a driver attaches the manager to its streams: foreground pushes, taps and identity changes. Pushes and taps whose `subject` names somebody other than the signed-in identity are dropped, and the manager republishes the rest on `onPushReceived` and `onPushClicked`. Taps that arrive before anything listens to `onPushClicked` are held and replayed when a listener attaches, which covers a cold start from a notification.

`NotificationServiceProvider.boot()` registers the built-in OneSignal factory through `extend()`, then reads `pushDriverOrNull` and calls `driver.initialize(config)`. `PushChannel` receives the same driver reference, and `PushChannel.isAvailable` is `driver.isSupported` together with the `notifications.push.self_test_enabled` switch.

<a name="send-flow"></a>
## Send Dispatch Flow

Excerpt of `lib/src/notification_manager.dart`:

```dart
Future<void> send(Notifiable notifiable, Notification notification) async {
  final channels = notification.via(notifiable);
  Object? firstError;
  StackTrace? firstStack;

  for (final channelName in channels) {
    final channel = _channels[channelName];

    if (channel == null) {
      NotificationLog.warning('Unknown notification channel: $channelName');
      continue;
    }

    if (!channel.isAvailable) {
      continue;
    }

    try {
      await channel.send(notifiable, notification);
    } catch (error, stack) {
      if (firstError == null) {
        firstError = error;
        firstStack = stack;
      } else {
        NotificationLog.error(
          'The $channelName channel also failed to send ${notification.type}: $error',
        );
      }
    }
  }

  if (firstError != null) {
    Error.throwWithStackTrace(firstError, firstStack!);
  }
}
```

The dispatch flow:

1. Call `notification.via(notifiable)`, which returns a `List<String>` of channel names.
2. Look each name up in the channel map.
3. Skip an unknown name with a logged warning, never a throw.
4. Skip a channel whose `isAvailable` is `false`.
5. Await `channel.send(notifiable, notification)`. Channels run sequentially.
6. After the loop, rethrow the first failure with its original stack.

> [!NOTE]
> A channel that throws does not stop the ones after it. Every available channel is tried first; later failures are logged and the first one is rethrown, so a caller sees that something failed without losing a delivery that would have worked.

<a name="polling"></a>
## Polling Orchestration

The manager owns the `NotificationPoller` lifecycle and delegates all timer logic to the poller:

Excerpt of `lib/src/notification_manager.dart`:

```dart
void startPolling() {
  if (isRealtime) return;
  _poller ??= NotificationPoller(this, interval: _pollingIntervalForPoller());
  _poller!.start();
}

void stopPolling() {
  _poller?.stop();
  _poller = null;
}

void pausePolling() => _poller?.pause();
void resumePolling() => _poller?.resume();
```

`startPolling()` is idempotent: when the poller is already running, `start()` returns immediately. It is also a no-op while realtime is live. The recommended lifecycle hooks:

| App event | Call |
| :--- | :--- |
| User logged in | `Notify.startPolling()` |
| App backgrounded | `Notify.pausePolling()` |
| App foregrounded | `Notify.resumePolling()` |
| User logged out | `Notify.stopPolling()` |

The poller fetches immediately on `start()` and on `resume()` after a pause, then on every interval. The interval comes from `notifications.database.polling_interval` (default 30 seconds, clamped to 5 to 600) when the poller is built; see [Configuration](../getting-started/configuration.md#database).

<a name="realtime"></a>
## Realtime Delivery

Polling is the fallback, not the only path. When the app has a broadcast driver (see [magic_socket](https://anilcancakir.com/magic_socket/docs/basics/channels), which provides `Echo`), the manager can take notification state off the socket instead:

```dart
import 'package:magic_notifications/magic_notifications.dart';

Future<bool> arm(String userId) async {
  final bool live = await Notify.startRealtime(
    channel: 'App.Models.User.$userId',
  );

  return live;
}
```

`startRealtime()` does five things in order, and each one answers a specific failure:

1. **Refuses when there is no driver.** It reads `broadcasting.default` and returns `false` for `null`, empty or the literal `'null'`. It does not subscribe to see what happens: the null driver accepts a subscription and silently delivers nothing, so an attempt-based probe would report success on the one configuration that cannot work, silence the poller, and leave the bell permanently empty. A `null` or empty channel name returns `false` too.
2. **Connects only if nothing is connected.** The check saves a round trip. A connect that fails (the realtime server is down) does not stop it: the next steps run anyway, the driver records the channel and subscribes it on its next handshake, and the poller keeps running until the server confirms the channel. It still returns `true`, since realtime is armed; only a failure to subscribe returns `false`.
3. **Listens for `notification.created` exactly once.** A second `listen()` for one event name replaces the earlier handler rather than adding to it, so registering the same event anywhere else would silently drop this one.
4. **Keeps the poller until the channel is subscribed.** `connected` is emitted before a private channel is authorised, so a connected but unsubscribed socket delivers nothing. The poller stops only when the channel's own `onSubscriptionChanged` reports `true`.
5. **Fetches the existing list once** when that confirmation arrives (at once if the channel is already subscribed). A socket carries only what happens next, and Reverb has no replay.

### The frame is the state

A `notification.created` frame carries the whole row in the shape `GET /notifications` returns, so it is decoded and applied rather than treated as a signal to fetch:

Excerpt of `lib/src/notification_manager.dart`:

```dart
void _applyRealtimeFrame(BroadcastEvent event) {
  final incoming = DatabaseNotification.fromMap(event.data);
  _notifications = _prependKeyedById(incoming, _notifications);
  _notificationController.add(_notifications);
}
```

Newest first, keyed by id, so a redelivery replaces the held row instead of appending a duplicate the bell would count twice. A frame that lands while a fetch is in flight is kept and merged into that fetch's result, so the response cannot erase it. A payload the decoder cannot read is logged and dropped: it must not throw into the driver's listener, and it must not clear what is already held.

### Both directions of degradation

The poller follows the channel's subscription, with `connectionState` watched only to arm it on a drop:

| Signal | What happens |
| :--- | :--- |
| `connectionState` anything but `connected` | The poller is armed as a stand-in; the subscription stays, because realtime is still the intent |
| `connectionState` `connected` | Nothing: the channel is not authorised yet |
| `onSubscriptionChanged` `true` | The poller is dropped and the list is refetched once |
| `onSubscriptionChanged` `false` (drop, leave or failed auth) | The poller is armed again |

Without the stand-in poller, a socket that never comes back (or a channel whose auth fails) is a bell that never updates again.

### Lifecycle hooks

| App event | Call |
| :--- | :--- |
| User logged in | `Notify.startRealtime(channel: ...)` then `Notify.startPolling()` |
| User switched account | `Notify.startRealtime(channel: ...)` with the new channel |
| User logged out | `Notify.stopRealtime()` then `Notify.stopPolling()` |

Both calls on the login row are safe in either order and idempotent per channel, so wiring them to an auth-state listener that fires on every login, logout and restore is the intended shape. `startPolling()` is a no-op while realtime is live, so a consumer never branches on whether a socket is up.

<a name="streams"></a>
## Stream Management

Database notifications are distributed through a broadcast `StreamController`:

Excerpt of `lib/src/notification_manager.dart`:

```dart
final StreamController<List<DatabaseNotification>> _notificationController =
    StreamController<List<DatabaseNotification>>.broadcast();

List<DatabaseNotification> _notifications = [];

Stream<List<DatabaseNotification>> notifications() async* {
  yield _notifications; // emit the cached state immediately
  yield* _notificationController.stream; // then every later update
}
```

`notifications()` yields the current cached list to a new listener at once, then forwards later events, so a widget that subscribes mid-session gets the list without waiting for the next poll.

The stream emits when:

1. `fetchNotifications()` completes a full refresh from the API.
2. `markAsRead(id)`, `markAllAsRead()` or `deleteNotification(id)` applies its optimistic change.
3. A realtime frame arrives.
4. The session is cleared, on sign-out or an account switch, which empties the list so the next person never sees the previous person's rows.

<a name="optimistic"></a>
## Optimistic Updates with Rollback

Read-mutate operations apply the change locally before the HTTP request completes, then revert on failure. Whether the caller is told about the failure differs per operation, and the note below the `deleteNotification` snippet says which is which:

Excerpt of `lib/src/notification_manager.dart`:

```dart
Future<void> markAsRead(String id) async {
  // 1. Optimistic update
  final index = _notifications.indexWhere((n) => n.id == id);
  if (index != -1) {
    _notifications[index] = _notifications[index].copyWith(
      readAt: DateTime.now(),
    );
    _notificationController.add(_notifications);
  }

  // 2. Sync with the backend
  try {
    await Http.post('/notifications/$id/read');
  } catch (e) {
    NotificationLog.error('Failed to mark notification as read: $e');
    // 3. Rollback on failure
    await fetchNotifications();
  }
}
```

`markAllAsRead()` follows the same pattern. Rollback always calls `fetchNotifications()` to restore authoritative server state rather than undoing the local mutation, which avoids edge cases from concurrent updates.

`deleteNotification` keeps the removed items for rollback and then **rethrows**:

Excerpt of `lib/src/notification_manager.dart`:

```dart
Future<void> deleteNotification(String id) async {
  final removed = _notifications.where((n) => n.id == id).toList();
  _notifications.removeWhere((n) => n.id == id);
  _notificationController.add(_notifications);

  try {
    await Http.delete('/notifications/$id');
  } catch (e) {
    NotificationLog.error('Failed to delete notification: $e');
    _notifications.addAll(removed);
    _notificationController.add(_notifications);

    rethrow;
  }
}
```

> [!IMPORTANT]
> `deleteNotification` is the one mutation here that does not swallow, and that is deliberate. Without the rethrow a caller cannot tell a delete that worked from one that did not: the only thing a person would see is the row leaving the list and coming back, with nothing said. The rollback is the same; the future carries the failure.
>
> `markAsRead` and `markAllAsRead` swallow. Their failure is recoverable by looking again and costs a person nothing, while a delete that silently did not happen is the case where the screen and the server disagree about something destructive.
>
> A caller that wants silence adds a `catch`. `NotificationsListView` catches it and reports `notifications.delete_failed` through `Magic.error`, which is a key the host must supply: this package ships no translation catalogue, and a missing key renders as itself.

> [!IMPORTANT]
> **`NotificationsListView.onDelete` is `Future<bool> Function(String id)?`, and the `bool` is load-bearing.** The screen is a separately paginated fetch, so a delete the server accepted has to be followed by a reload: a row leaving page one pulls one up from page two, and only the server knows which. The answer decides whether that reload happens.
>
> | Outcome | Meaning | The list |
> | :--- | :--- | :--- |
> | `true` | The row is gone | Reloads the current page |
> | `false` | The host chose not to go ahead | Is left alone |
> | throws | The request failed and the manager rolled the row back | Reloads, because what the server holds is now unknown |
>
> `false` is what a confirmation dialog needs: a host that asks before deleting does not spend a `GET /notifications` every time somebody declines. A callback that always deletes returns `true`; one that can refuse returns `false` on that path.
>
> Translation keys the host must supply for the same reason: **`notifications.delete`** names the row's delete control for a screen reader (it is a bare glyph with no text of its own), **`notifications.channel_sms`** labels the SMS row on the preferences screen, and **`notifications.bulk_title`** and **`notifications.bulk_description`** head the card above the preference matrix. Without them each renders as its own key.

> [!TIP]
> The `Notify` facade exposes every one of these operations as a static method (`Notify.markAsRead`, `Notify.deleteNotification` and so on), delegating to the same manager.

<a name="identity-reconciled"></a>
## Push Identity Reconcile Outcomes

`reconcilePushIdentity()` brings the device's subscribed identity in line with `pushIntent` (see [Push Driver Setup](#push-driver) for how a driver resolves). `onPushIdentityReconciled` reports the outcome of every pass that had a driver to act on:

```dart
import 'package:magic_notifications/magic_notifications.dart';

// `reportDeviceState` is the host's own function.
void reportDeviceState({required String? intent, required bool converged}) {}

void watchIdentity() {
  Notify.manager.onPushIdentityReconciled.listen((PushIdentityReconciled event) {
    reportDeviceState(intent: event.intent, converged: event.converged);
  });
}
```

Excerpt of `lib/src/models/push_identity_reconciled.dart`:

```dart
class PushIdentityReconciled {
  final String? intent;   // captured when the pass started
  final bool converged;   // whether the device carried it by the end
  final Object? error;    // non-null only when the SDK call itself failed
}
```

This exists for a host that reports device state per person (who this device is subscribed as, posted to the host's own backend). That host needs to know when a pass ran, not only when one converges: a converged-only signal leaves it silent until the next auth change triggers another pass, and the first pass after a driver attaches is the one most likely to throw or read back a mismatch.

Read `converged` and `error` together:

| `converged` | `error` | Meaning |
| :--- | :--- | :--- |
| `true` | `null` | The device carries `intent`. |
| `false` | non-null | The SDK call itself failed (network, driver refusal). |
| `false` | `null` | The call was issued and the read-back did not agree. |

`intent` is `null` on a sign-out pass, not only on a driver-less one, so a listener that treats a `null` intent as "nothing happened" misses every sign-out. Nothing fires for a pass that had no driver to act on (a build with no push configured has nothing to report convergence about), and a pass whose intent moved underneath it (a second login landing mid-pass) does not fire either: the mover's own pass reports for them, so a joiner never double-reports one outcome under two identities.

`onPushDriverAttached` is the companion stream. A cold boot that restores a session normally bumps auth, and with it a login `want()`, before `NotificationServiceProvider.boot()` has resolved a driver, so anything a host does with a driver on that path needs to know when one shows up rather than only when auth changes.

<a name="related-documentation"></a>
## Related Documentation

- [Service Provider](./service-provider.md): where channels, the driver and the first reconcile are wired.
- [Channels](../basics/channels.md): the contract `send` dispatches to.
- [Drivers](../basics/drivers.md): what the manager resolves and listens to.
- [Configuration](../getting-started/configuration.md): the polling and push keys.
- [Shipping push in a release build](../basics/shipping-push.md): `Notify.pushState`, which reports device reachability to a backend.
- [Realtime connection in magic_socket](https://anilcancakir.com/magic_socket/docs/guides/connection): the socket behind `Notify.startRealtime`.
