# Service Provider

How `NotificationServiceProvider` binds the notification manager into Magic's container and wires the push driver during boot.

- [Overview](#overview)
- [Two-Phase Bootstrap Pattern](#two-phase)
- [register(): IoC Binding](#register)
- [boot(): Channels and Push Driver](#boot)
- [Config Loading from ConfigRepository](#config-loading)
- [IoC Integration](#ioc)
- [Registering the Provider](#registration)
- [Related Documentation](#related-documentation)

<a name="overview"></a>
## Overview

`NotificationServiceProvider` is the plugin's bootstrap entry point. It extends Magic's `ServiceProvider`, binds `NotificationManager` into the container, registers the channels and initialises the push driver from config.

Excerpt of `lib/src/providers/notification_service_provider.dart`:

```dart
class NotificationServiceProvider extends ServiceProvider {
  NotificationServiceProvider(super.app);

  @override
  void register() { ... }

  @override
  Future<void> boot() async { ... }
}
```

<a name="two-phase"></a>
## Two-Phase Bootstrap Pattern

Magic's provider contract splits bootstrapping into two phases:

| Phase | Method | Timing | Purpose |
| :--- | :--- | :--- | :--- |
| 1 | `register()` | Synchronous, early | Bind services into the container |
| 2 | `boot()` | Asynchronous, after every provider registered | Wire what depends on other bindings |

`register()` runs for every provider before `boot()` runs for any of them, so by the time `boot()` runs, every binding another provider made in `register()` is available.

<a name="register"></a>
## register(): IoC Binding

Excerpt of `lib/src/providers/notification_service_provider.dart`:

```dart
@override
void register() {
  app.singleton('notifications', () => NotificationManager());
}
```

`register()` binds one string-keyed singleton and does nothing else. It runs before any other provider has bound anything, so a driver resolved here would be resolved against a half-built container.

```dart
import 'package:magic/magic.dart';
import 'package:magic_notifications/magic_notifications.dart';

NotificationManager resolveManager(MagicApp app) {
  final manager = app.make<NotificationManager>('notifications');

  return manager;
}
```

<a name="boot"></a>
## boot(): Channels and Push Driver

`boot()` runs these steps in order:

1. Resolves the manager through the container (`app.make`), which proves `register()` bound what a consumer will resolve, and clears the failure recorded by any earlier boot.
2. Registers `DatabaseChannel`. It is available with or without push.
3. Loads the persisted push intent from `Vault` (key `magic_notifications.push_intent`) when `vault` is bound, before a driver exists. Resolving a driver attaches the manager's push listeners, and the SDK can replay a cold start from a notification tap while `initialize` runs; compared against an intent nothing had read yet, a push for the person holding the phone would read as addressed to somebody else and be dropped.
4. Resolves the push driver (below). When there is one, registers `PushChannel` on it and initialises it.
5. Calls `reconcilePushIdentity()` once, unconditionally. A signed-out cold boot fires no auth event, so without this pass a device signed out while offline would stay subscribed as the previous person until somebody signed in. It is safe with no driver and when the intent already matches the device.

### Resolving the driver

| Situation | Result |
| :--- | :--- |
| A driver was set with `setPushDriver` or registered with `Notify.extend` and selected | It is used; config does not outrank it |
| `notifications.push.driver` is absent or empty | No push driver; everything except push keeps working |
| `notifications.push.driver` is `'onesignal'` | The built-in factory is registered with `extend('onesignal', createOneSignalDriver)` and resolved through the manager |
| Any other value with nothing registered under it | Logged at error level; push stays off and the app still boots |

### Initialising the driver

The driver is initialised only when `isSupported` is `true` and `notifications.push.app_id` is non-empty. The config map is built by `OneSignalWebDriver.buildConfigFromEnv`, which carries `app_id`, `notify_button_enabled` and whichever of `safari_web_id`, `service_worker_path` and `service_worker_scope` the config declares; an undeclared key stays out of the map.

A failure is not rethrown, so a failed push initialisation never stops the app from starting. It is logged at error level and kept on `NotificationServiceProvider.pushInitializationError`, which is what tells a broken setup apart from a build with no push at all. The static is cleared at the start of every boot.

> [!NOTE]
> `boot()` does not start polling. Start it from your authenticated layout with `Notify.startPolling()` so it only runs while somebody is signed in.

<a name="config-loading"></a>
## Config Loading from ConfigRepository

`Config.get` is Magic's static accessor for the merged config map. The provider reads these keys at boot:

```dart
import 'package:magic/magic.dart';

void readBootKeys() {
  Config.get<String>('notifications.push.driver');               // 'onesignal'
  Config.get<String>('notifications.push.app_id');
  Config.get<String>('notifications.push.safari_web_id');        // nullable
  Config.get<bool>('notifications.push.notify_button_enabled');  // false when absent
  Config.get<String>('notifications.push.service_worker_path');  // nullable
  Config.get<String>('notifications.push.service_worker_scope'); // nullable
}
```

Other parts of the package read their own keys when they need them (for example `notifications.database.polling_interval` when a poller is built). [Configuration](../getting-started/configuration.md) lists every key.

`Config.get` returns `null` when a key is absent or has another type. The values come from the `notificationConfig` getter in `lib/config/notifications.dart`, registered as a config factory:

```dart
import 'package:magic/magic.dart';

import 'config/app.dart'; // The host's own config: declares `appConfig`.
import 'config/notifications.dart';

Future<void> boot() async {
  await Magic.init(
    configFactories: [
      () => appConfig,
      () => notificationConfig,
    ],
  );
}
```

<a name="ioc"></a>
## IoC Integration

`app.singleton` registers a lazy singleton factory: the factory runs once on first resolution and the result is cached.

```dart
import 'package:magic/magic.dart';
import 'package:magic_notifications/magic_notifications.dart';

// By key
final manager = Magic.make<NotificationManager>('notifications');

// Through the facade
final same = Notify.manager;

// The factory constructor
final alsoSame = NotificationManager();
```

All three return the same instance, because `NotificationManager()` is itself a Dart-level singleton regardless of the container binding.

<a name="registration"></a>
## Registering the Provider

Add `NotificationServiceProvider` to the provider list in `lib/config/app.dart`:

```dart
import 'package:magic_notifications/magic_notifications.dart';

final providers = [
  // ... other providers
  (app) => NotificationServiceProvider(app),
];
```

> [!TIP]
> `dart run magic:dowel plugin:install magic_notifications` injects the provider and its import for you.

<a name="related-documentation"></a>
## Related Documentation

- [Notification Manager](./notification-manager.md): what the provider wires up.
- [Configuration](../getting-started/configuration.md): the keys `boot()` reads.
- [Drivers](../basics/drivers.md): the push drivers and the custom driver path.
- [Installation](../getting-started/installation.md): the install flow that registers the provider.
- [Magic service providers](https://anilcancakir.com/magic/docs/getting-started/service-providers): the two-phase contract this provider follows.
