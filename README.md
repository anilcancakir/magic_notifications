<p align="center">
  <img src="https://raw.githubusercontent.com/anilcancakir/magic_notifications/master/screenshots/logo.png" width="120" alt="Magic Notifications logo" />
</p>

<h1 align="center">Magic Notifications</h1>

<p align="center">
  <strong>Show a backend-driven inbox and send push in a Magic app.</strong><br/>
  The <code>Notify</code> facade reads your Laravel backend's notifications, ships the inbox and preferences screens, wires OneSignal push on iOS, Android and web, and takes new rows over <code>magic_socket</code> with polling as the fallback. There is no mail channel.
</p>

<p align="center">
  <a href="https://pub.dev/packages/magic_notifications"><img src="https://img.shields.io/pub/v/magic_notifications.svg" alt="pub package"></a>
  <a href="https://github.com/anilcancakir/magic_notifications/actions/workflows/ci.yml"><img src="https://img.shields.io/github/actions/workflow/status/anilcancakir/magic_notifications/ci.yml?branch=master&label=CI" alt="CI"></a>
  <a href="https://codecov.io/gh/anilcancakir/magic_notifications"><img src="https://codecov.io/gh/anilcancakir/magic_notifications/graph/badge.svg" alt="codecov"></a>
  <a href="https://opensource.org/licenses/MIT"><img src="https://img.shields.io/badge/License-MIT-blue.svg" alt="License: MIT"></a>
  <a href="https://pub.dev/packages/magic_notifications/score"><img src="https://img.shields.io/pub/points/magic_notifications" alt="pub points"></a>
</p>

<p align="center">
  <a href="https://anilcancakir.com/magic/docs/notifications">Documentation</a> ·
  <a href="https://pub.dev/packages/magic_notifications">pub.dev</a> ·
  <a href="https://github.com/anilcancakir/magic_notifications/issues">Issues</a>
</p>

## At a glance

| Fact | Value |
|---|---|
| Package | [`magic_notifications`](https://pub.dev/packages/magic_notifications) |
| Install | `flutter pub add magic_notifications`, then `dart run magic:dowel plugin:install magic_notifications` and `dart run magic:dowel notifications:install` |
| Import | `package:magic_notifications/magic_notifications.dart` |
| Entry points | `Notify` (facade), `NotificationServiceProvider` (wiring), `NotificationManager`, `Notification` and `Notifiable`, `DatabaseChannel` and `PushChannel`, `PushDriver` and `OneSignalDriver`, `NotificationsListView`, `NotificationPreferencesView`, `NotificationDropdown`, `PushPrompt`; `notifications:*` (CLI) |
| Platforms | The inbox runs wherever Flutter does. Push runs on iOS and Android (OneSignal SDK) and on web (OneSignal Web SDK); elsewhere `PushDriver.isSupported` is `false` and reachability reads `unavailable`. |
| Requires | Dart >=3.13, Flutter >=3.47, `magic` ^1.0.0, a backend that serves the notification endpoints |
| Dependencies | `magic`, `magic_socket`, `dowel`, `onesignal_flutter`, `wind_kit`, `material_ui`, `app_settings`, `meta` |
| License | MIT |

## Install

```bash
flutter pub add magic_notifications
dart run magic:dowel plugin:install magic_notifications
dart run magic:dowel notifications:install
dart run magic:dowel notifications:doctor
```

`plugin:install` registers `NotificationServiceProvider` in `lib/config/app.dart` and the package's commands with dowel; the package has no executable of its own. `notifications:install` asks for the OneSignal App ID, writes `lib/config/notifications.dart` and the platform files push needs, and wires the config into `lib/main.dart`. `notifications:doctor` reports what is still missing. In a pipeline:

```bash
dart run magic:dowel notifications:install \
  --non-interactive \
  --app-id 12345678-1234-1234-1234-123456789012 \
  --platforms android,ios,web
```

The APNs key upload, the iOS App Group and the Notification Service Extension stay manual; [Installation](https://anilcancakir.com/magic/docs/notifications/getting-started/installation) lists them.

## Inbox

Notifications are rows your backend creates; the client reads them. Listen to the stream, fetch, and change read state.

```dart
import 'package:flutter/foundation.dart';
import 'package:magic_notifications/magic_notifications.dart';

final ValueNotifier<int> unread = ValueNotifier<int>(0);

Future<void> main() async {
  Notify.notifications().listen((List<DatabaseNotification> rows) {
    unread.value = rows.where((DatabaseNotification n) => !n.isRead).length;
  });

  await Notify.fetchNotifications();
  await Notify.markAsRead('550e8400-e29b-41d4-a716-446655440000');
}
```

| Member | Returns | Meaning |
|--------|---------|---------|
| `Notify.notifications()` | `Stream<List<DatabaseNotification>>` | The cached list at once, then every later change. |
| `Notify.fetchNotifications()` | `Future<void>` | Reads `GET /notifications` into the stream. A failure is logged and the held list stays. |
| `Notify.fetchPaginatedNotifications(page:, perPage:)` | `Future<PaginatedNotifications>` | One page with its meta. Throws `NotificationException` (`NOTIFICATIONS_FETCH_FAILED`, `NOTIFICATIONS_DECODE_FAILED`) instead of answering an empty page. |
| `Notify.unreadCount()` | `Future<int>` | Reads `GET /notifications/unread-count`; `0` on a failure. |
| `Notify.markAsRead(id)`, `Notify.markAllAsRead()` | `Future<void>` | Change the held list first, then post to the backend. |
| `Notify.deleteNotification(id)` | `Future<void>` | Removes the row first, restores it when the request throws, and rethrows. |

Failure modes:

| Situation | What happens |
|-----------|--------------|
| A row whose `data` has no string `title` or `body` | The decode throws: `fetchNotifications` logs it and keeps the previous list; `fetchPaginatedNotifications` throws `NOTIFICATIONS_DECODE_FAILED`. |
| `unread-count` answers `{"data": {"count": 5}}` | The client reads `count` from the top level and returns `0`. Answer `{"count": 5}`. `magic-starter-laravel` answers the wrapped shape; a backend written to the contract is not affected. |
| The backend ignores `perPage` | The client sends `page` and `perPage`; a backend that reads `per_page` always uses its own default. `magic-starter-laravel` reads `per_page`; a backend written to the contract is not affected. |
| `markAsRead` or `markAllAsRead` and the request throws | The list is refetched to the server's state and nothing is rethrown. An HTTP error status does not throw in Magic's `Http`, so it is not rolled back. |
| The signed-in person changes | The held list is cleared, so the next person never sees the previous person's rows. |

## Channels

A `Notification` names its channels in `via()`; `Notify.send` dispatches to each registered channel in turn.

```dart
import 'package:magic_notifications/magic_notifications.dart';

class MonitorDownNotification extends Notification {
  @override
  List<String> via(Notifiable notifiable) => ['database', 'push'];

  @override
  Map<String, dynamic>? toDatabase(Notifiable notifiable) => {
    'title': 'Monitor down',
    'body': 'api.example.com is not responding',
  };

  @override
  PushMessage? toPush(Notifiable notifiable) => PushMessage()
      .heading('Monitor down')
      .content('api.example.com is not responding');
}

Future<void> alert(Notifiable user) => Notify.send(user, MonitorDownNotification());
```

| Channel | Behaviour |
|---------|-----------|
| `database` | Always registered and available. `send` does nothing: the backend creates the row and the client reads it. |
| `push` | Registered when a push driver resolves, and **self-addressed**: it posts to `POST /notifications/push-test` and the backend derives the recipient from the session, so it can only page the signed-in user. It is off until `notifications.push.self_test_enabled` is `true`. Push to other people is sent by your backend. |
| your own | Extend `NotificationChannel` (`name`, `isAvailable`, `send`) and register it with `Notify.manager.registerChannel`. |

Failure modes:

| Situation | What happens |
|-----------|--------------|
| `via()` names a channel nobody registered, `'mail'` included | The manager logs `Unknown notification channel` and skips it. |
| A channel is unavailable | It is skipped without a log; the others still deliver. |
| A channel throws | Every available channel is still tried, later failures are logged, and the first error is rethrown after the last. |
| `PushChannel` is given a `Notifiable` that is not the signed-in user | Throws `NotificationException` with code `PUSH_RECIPIENT_NOT_AUTHENTICATED_USER`. |
| A non-2xx answer from `push-test` | Throws `NotificationException` with code `HTTP_<status>`. |
| `Notification` is ambiguous after importing Flutter | Import widgets with `hide Notification`. |

## Push

The package does **not** declare who the device belongs to: your app does, after sign-in, and takes it back on sign-out. (`magic_starter` already does both; an app without it writes them.)

```dart
import 'package:magic/magic.dart';
import 'package:magic_notifications/magic_notifications.dart';

// Once, from a provider's boot() after auth is registered. Nothing else calls
// `watch()`, so device reachability is never reported until this runs.
void armPushState() {
  Notify.pushState.watch();
}

Future<void> onSignIn(String userId) async {
  await Notify.initializePush('user_$userId');
  await Notify.startRealtime(channel: 'App.Models.User.$userId');
  Notify.startPolling();
}

Future<void> onSignOut() async {
  Notify.stopRealtime();
  Notify.stopPolling();
  if (Notify.pushState.isConfigured) await Notify.pushState.release();
  await Notify.logoutPush();
  await Auth.logout();
}
```

`initializePush` forwards the string unchanged, and your backend addresses the device by the same string, so both sides must agree on the prefix (`user_` by default). A mismatch is accepted by OneSignal and delivered to nobody.

| Member | Meaning |
|--------|---------|
| `Notify.requestPushPermission()` | Raises the OS dialog; `true` when granted. The OS dialog never returns on a device that already answered; on a denied phone OneSignal shows its own open-settings dialog instead, unless `fallback_to_settings` is `false`. |
| `Notify.manager.pushDriver.reachability()` | `PushReachability.unavailable`, `blocked`, `off` or `on`, without raising a dialog. |
| `Notify.manager.pushPromptAdvice(declinedAt:)` | Whether your own reminder may show now, and what its button can do (`PushPromptAction`). |
| `PushPrompt`, `PushPromptHost(declinedVaultKey:)`, `PushOffNotice(onOpenPreferences:)` | The shipped reminder row and the quiet shell marker; see [Push Prompt Component](https://anilcancakir.com/magic/docs/notifications/basics/preferences#push-prompt). |
| `Notify.manager.onPushReceived`, `onPushClicked` | Foreground pushes and taps, filtered to the signed-in identity; taps from a cold start are held until a listener attaches. |
| `Notify.manager.onPushIdentityReconciled` | The outcome of every identity pass; see [Push Identity Reconcile Outcomes](https://anilcancakir.com/magic/docs/notifications/architecture/notification-manager#identity-reconciled). |
| `Notify.pushState` | Posts the device's own reachability to your backend and withdraws it on sign-out; see [Telling your backend whether the device can be paged](https://anilcancakir.com/magic/docs/notifications/basics/shipping-push#telling-your-backend-whether-the-device-can-be-paged). Reports nothing until your app calls `Notify.pushState.watch()` (the provider never does) and both `report_path` and `release_path` are set. |
| `Notify.describePushUserUsing(resolver)` | Describes the signed-in person to OneSignal; nothing is sent until `share_user_attributes` is `true`. |
| `Notify.extend(name, factory)` | Registers a `PushDriver` of your own, selected by `notifications.push.driver`. |

Failure modes:

| Situation | What happens |
|-----------|--------------|
| A tapped push should open a screen | Nothing routes for you: the package hands over the payload. Register a `magic_deeplink` handler or route from `onPushClicked` ([Opening a screen from a tap](https://anilcancakir.com/magic/docs/notifications/basics/drivers#opening-a-screen-from-a-tap)). |
| The destination was sent as OneSignal's Launch URL (`setUrl`) | It never reaches `event.data`; put it in `setData`. |
| `notifications.push.app_id` is blank | The driver is never initialised, `isInitialized` stays `false` and reachability reads `unavailable`. |
| The driver fails to initialise | The app still boots; the failure is on `NotificationServiceProvider.pushInitializationError`. |
| A driver name nothing was registered under | Logged at error level, push stays off. |
| `requestPushPermission` on a denied device | No OS dialog. On iOS and Android OneSignal shows its own English dialog offering the app's settings (`notifications.push.fallback_to_settings`, on by default); on web, or with that key `false`, nothing is shown. Read `reachability()` first and, when it is `blocked`, call `Notify.openPushSettings()` on a phone or point at the browser setting on web. |
| `Notify.pushState.release()` after `Auth.logout()` | The token is gone and the request is a 401. Release first. |
| Web push on iOS Safari in a plain tab | Reaches nobody until the site is added to the Home Screen. |

## Realtime and polling

`Notify.startRealtime` subscribes to the notifiable's private broadcast channel and applies each `notification.created` frame to the stream. `Notify.startPolling` reads `GET /notifications` every 30 seconds by default (`notifications.database.polling_interval`, clamped to 5 to 600) and is a no-op while the socket is live.

```dart
import 'package:magic_notifications/magic_notifications.dart';

Future<void> arm(String userId) async {
  await Notify.startRealtime(channel: 'App.Models.User.$userId');

  // The fallback: a no-op while the socket is live, so no branch is needed.
  Notify.startPolling();
}
```

| Situation | What happens |
|-----------|--------------|
| `broadcasting.default` is unset, empty or `'null'`, or the channel is empty | `startRealtime` returns `false` and changes nothing. |
| The socket cannot connect yet | It subscribes anyway and returns `true`; polling stands in until the channel is subscribed. |
| The socket drops | Polling resumes; on a resubscribe the poller stops and the list is refetched once, since Reverb has no replay. |
| A frame arrives twice | It replaces the held row by id. |
| `NotificationServiceProvider.boot()` | Starts no polling. Start it from an authenticated layout. |

## Screens

```dart
import 'package:magic_notifications/magic_notifications.dart';

void boot() {
  Notify.view.register('notifications.preferences', () {
    return const NotificationPreferencesView(backRoute: '/settings');
  });
}
```

`Notify.view` is a `NotificationViewRegistry` holding `notifications.list` (`NotificationsListView`) and `notifications.preferences` (`NotificationPreferencesView`); register over a key to wrap or replace it, and `Notify.view.slot` supplies a type icon. `NotificationDropdown` is the bell with an unread badge ([Notification Dropdown](https://anilcancakir.com/magic/docs/notifications/basics/notification-dropdown)). The package ships no translation catalogue: a host adds every key the screens, the dropdown and `PushPrompt` read to every locale, and a missing key renders as itself ([Translation Keys](https://anilcancakir.com/magic/docs/notifications/basics/preferences#translation-keys) lists them all). The preferences screen needs `GET` and `PUT /notification-preferences` on the backend.

## CLI Tools

`dart run magic:dowel notifications:<command>`, after `plugin:install`. The [CLI reference](https://anilcancakir.com/magic/docs/notifications/basics/cli) lists every flag.

| Command | Purpose |
|---------|---------|
| `install` | Wizard: config, platform files, provider and config factory. Flags: `--non-interactive`, `--app-id`, `--platforms`, `--no-soft-prompt`, `--safari-web-id`, `--notify-button`, `--force`, `--dry-run`. |
| `configure` | Show or change single values: `--show`, `--app-id`, `--polling-interval`, `--soft-prompt`. |
| `doctor` | Health check of the install, the config and the iOS entitlements; exits `1` when a requirement is missing. |
| `test` | Prints a notification preview; makes no request. |
| `channels` | Prints the channel settings from the config file. |
| `publish` | Copies the config stub without a wizard. |
| `uninstall` | Removes what `install` wired into Dart files; platform files stay. |

`doctor` and `channels` are also read-only MCP tools. `configure`, `channels` and `doctor` read the config file's text, so an App ID read with `env('...')` cannot be changed by `configure --app-id`: change the `.env` value.

## For AI coding agents

Rules for an agent writing code against this package. Each one is a mistake that ships silently.

| Do | Because |
|----|---------|
| Import only `package:magic_notifications/magic_notifications.dart` | Everything under `src/` is private; `cli.dart` carries the dowel provider only. |
| Register `NotificationServiceProvider` (`plugin:install` does) | It binds the manager, registers `DatabaseChannel`, resolves the push driver and runs the first identity reconcile. |
| Run commands as `dart run magic:dowel notifications:<command>` after `plugin:install` | The package has no executable. |
| Call `Notify.initializePush('<prefix><id>')` after sign-in and `Notify.logoutPush()` on sign-out | The package declares no push identity; `magic_starter` does it for its apps. |
| Use one external id prefix on the app and the backend | The id is forwarded unchanged; a mismatch delivers to nobody. |
| Never list `'mail'` in `via()` | There is no mail channel; the manager logs and skips it. |
| Expect `DatabaseChannel.send` to do nothing | The backend creates inbox rows. |
| Send push to other people from the backend | `PushChannel` is self-addressed and off by default. |
| Put a push destination in OneSignal `setData`, not `setUrl` | Only `additionalData` reaches `onPushClicked`. |
| Register a `magic_deeplink` handler to open a screen from a tap | Nothing routes a tapped push on its own. |
| Release push state before `Auth.logout()` | The release needs the token. |
| Answer `{"count": n}` from `unread-count` and read `perPage` on `GET /notifications` | The client reads `count` at the top level and sends `perPage`. |
| Add every key in [Translation Keys](https://anilcancakir.com/magic/docs/notifications/basics/preferences#translation-keys) to every locale | A missing key renders as itself. |
| Call `Notify.forgetDrivers()` in a test's `setUp` | The manager is a process-wide singleton. |

## Dependencies

`magic` for the container, `Config`, `Http`, `Vault` (the persisted push intent) and the service provider base class; `magic_socket` for `Echo`, which carries the realtime path; `onesignal_flutter` for mobile push and JS interop for the OneSignal Web SDK; `wind_kit` and `material_ui` for the shipped screens and icons; `app_settings` to open the app's notification settings; `dowel` to run the `notifications:*` commands, whose provider is also the whole of `package:magic_notifications/cli.dart` for a plain Dart dispatcher.

## Links

- [Documentation](https://anilcancakir.com/magic/docs/notifications/getting-started/installation): installation, configuration, channels, drivers, preferences, the notification dropdown, shipping push, the CLI and the Laravel backend contract
- [API reference](https://pub.dev/documentation/magic_notifications/latest/)
- [llms.txt](llms.txt) and the [agent skill](skills/magic-notifications/SKILL.md) for AI coding agents: `npx skills add anilcancakir/magic_notifications`
- [Changelog](CHANGELOG.md)
- [Report an issue](https://github.com/anilcancakir/magic_notifications/issues)
- [Security policy](SECURITY.md)

## License

MIT, see [LICENSE](LICENSE). Built by [Anılcan Çakır](https://anilcancakir.com).
