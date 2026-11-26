# Drivers

The push driver layer: the `PushDriver` contract, the OneSignal drivers for mobile and web, how the right one is chosen, and how to supply your own.

- [Driver Concept](#concept)
- [PushDriver Abstract Class](#abstract)
- [OneSignalDriver (iOS and Android)](#onesignal-mobile)
- [OneSignalWebDriver (Web)](#onesignal-web)
- [Conditional Imports via onesignal_factory.dart](#conditional)
- [Creating a Custom Driver](#custom)
- [Gotchas](#gotchas)
- [Related Documentation](#related-documentation)

<a name="concept"></a>
## Driver Concept

A push driver wraps a platform push SDK behind one API, so the manager and `PushChannel` never touch SDK internals. The manager resolves the driver lazily from a name-keyed registry (see [Push Driver Setup](../architecture/notification-manager.md#push-driver)); `notifications.push.driver` selects the name, and `'onesignal'` is the only driver the package ships.

```dart
import 'package:magic_notifications/magic_notifications.dart';

final PushDriver? driver = Notify.manager.pushDriverOrNull; // null when push is not configured
```

<a name="abstract"></a>
## PushDriver Abstract Class

### Key Members

| Member | Description |
| :--- | :--- |
| `name` | Driver identifier (for example `'onesignal'`) |
| `isSupported` | Synchronous platform check; `PushChannel.isAvailable` depends on it |
| `isInitialized` | Whether `initialize` brought the SDK up. `true` by default. Both OneSignal drivers answer `false` before `initialize` and after a failed one, and the provider never starts them when `app_id` is blank. |
| `permissionState()` | Current `PushPermissionState` (`notDetermined`, `denied`, `authorized`, `provisional`). Mobile reads the native permission; web reads the browser's `Notification.permission`. |
| `isOptedIn` | Whether the person is actively subscribed |
| `initialize(config)` | One-time SDK initialisation; call it before everything else |
| `login(externalId)` / `logout()` | Associate or release the account on the subscription |
| `currentExternalId()` | The external id the device is subscribed as, or `null`. It closes the loop on `login` and `logout`: without it nothing can tell whether the SDK acted on the identity it was given. |
| `currentSubscriptionId()` | The platform subscription id, or `null`. A push cannot be addressed without one, which is why `reachability()` consults it. |
| `requestPermission()` | Raises the OS permission dialog; `true` when granted |
| `canRaisePermissionRequest()` | `true` only while the OS has never asked (`permissionState()` is `notDetermined`) |
| `canOpenPlatformSettings` / `openPlatformSettings()` | Whether the driver can open the app's own notification settings, and doing so. The base class answers `false` and throws `UnsupportedPlatformException`. |
| `optIn()` / `optOut()` | Re-subscribe or unsubscribe without clearing the external id |
| `setTags(tags)` / `removeTag(key)` / `removeTags(keys)` | Segmentation tags; `removeTags` defaults to a loop over `removeTag` |
| `addEmail(email)` / `removeEmail(email)` | Email subscription on the user. The base class logs that it has no email transport and sends nothing. |
| `onNotificationReceived` | Broadcast stream; a push arrived while the app was in the foreground |
| `onNotificationClicked` | Broadcast stream; the person tapped a notification |
| `onPermissionChanged` | Broadcast stream; the OS permission state moved |
| `onIdentityChanged` | Broadcast stream of `PushIdentityChange`; the SDK reports that the user or subscription changed underneath the app. The only trustworthy confirmation that a `login` or `logout` landed. |
| `subjectGuard` / `mayDisplay(data)` | Set by the manager. A push that arrives while the app is in the foreground and whose `subject` names somebody other than the signed-in identity is neither drawn nor republished: the drivers apply the guard in their foreground-display listener. In the background or with the app closed that listener does not run and the OS draws the notification with no client code involved, so the guard cannot stop it; only the server can, by no longer addressing a subscription that belongs to a previous person. |
| `reachability()` | Whether push can reach this device right now (below). Implemented once in the base class. |

### PushNotificationEvent

```dart
class PushNotificationEvent {
  final Map<String, dynamic> data;
  const PushNotificationEvent(this.data);
}
```

`data` is the notification's `additionalData` payload (mobile) or the same field from the JS event (web).

### PushIdentityChange

```dart
class PushIdentityChange {
  final String? externalId;
  final String? subscriptionId;
  final bool? optedIn;
  const PushIdentityChange({this.externalId, this.subscriptionId, this.optedIn});
}
```

Every field is nullable because one SDK event reports only part of the state: a user change carries the external id, a subscription change carries the subscription id and the opt-in flag. A `null` field means "this event did not report it", never "it is empty".

### Reachability

`PushDriver.reachability()` derives a four-state answer, so every driver answers the same way:

| State | Meaning |
| :--- | :--- |
| `PushReachability.unavailable` | No platform driver here (`isSupported` is `false`), or one whose SDK never started (`isInitialized` is `false`), so a request would only be refused. |
| `PushReachability.blocked` | Permission was denied and the platform will not re-prompt. The app has to point at the OS or browser setting. `requestPermission()` raises no OS dialog: on iOS and Android it shows OneSignal's settings fallback while `fallback_to_settings` is on, and on web, or with it off, nothing at all. |
| `PushReachability.off` | Never asked, or asked and not opted in. Safe to call `requestPermission()`. |
| `PushReachability.on` | Permitted, opted in and holding a subscription id: the only state a push can reach. |

```dart
import 'package:magic_notifications/magic_notifications.dart';

Future<PushReachability> currentReachability() async {
  final reachability = await Notify.manager.pushDriver.reachability();

  return reachability;
}
```

This is the read a soft prompt gates on before showing itself, and the read that answers "can I send this device a push" without raising the OS dialog.

<a name="onesignal-mobile"></a>
## OneSignalDriver (iOS and Android)

`OneSignalDriver` wraps the `onesignal_flutter` package.

| Behaviour | Detail |
| :--- | :--- |
| `isSupported` | `true` on iOS and Android only; `false` on tvOS, which reports as iOS but has no OneSignal SDK |
| `initialize` | Throws `NotificationException` with code `PLATFORM_NOT_SUPPORTED` on another platform and `MISSING_APP_ID` when `app_id` is blank; otherwise starts the SDK and attaches the foreground, click, permission and user observers |
| `login` and `requestPermission` | Throw `NOT_INITIALIZED` when called before `initialize`; `logout`, `optIn` and `optOut` return quietly |
| `permissionState()` | Maps the native permission; on platforms that report a denied state without a tri-state it asks the SDK whether a prompt would still show, so a never-asked device reads `notDetermined` |
| `requestPermission()` | Passes `notifications.push.fallback_to_settings` to the SDK as its settings fallback for a denied device |
| `canOpenPlatformSettings` | Follows `fallback_to_settings` (default `true`) |
| `openPlatformSettings()` | Opens the app's own notification settings page |

> [!NOTE]
> The `NotificationException` codes are programmer errors: handle them at app startup. The provider catches an initialisation failure, logs it and records it on `NotificationServiceProvider.pushInitializationError`, so a broken push setup can be told apart from a build with no push.

### Listening to Events

Prefer the manager's streams over the driver's own. They are filtered to the signed-in identity, and `onPushClicked` holds taps that arrive before anything listens, which is the cold-start case, and replays them when a listener attaches.

```dart
import 'package:magic/magic.dart';
import 'package:magic_notifications/magic_notifications.dart';

void listenToPush() {
  Notify.manager.onPushReceived.listen((event) {
    final title = event.data['title'];
    // show an in-app banner
  });

  Notify.manager.onPushClicked.listen((event) {
    // `event.data` is the notification's `additionalData`, so a destination is
    // only here when the backend put it there. Four keys, first match wins,
    // because that is what `magic_deeplink`'s own handler looks for.
    final url = event.data['url'] ??
        event.data['deep_link'] ??
        event.data['link'] ??
        event.data['uri'];

    // Guarded: a notification with nowhere to go is a valid notification.
    if (url is String && url.isNotEmpty) MagicRoute.to(url);
  });
}
```

A push received in the foreground also triggers a `fetchNotifications()`, so the in-app list catches up.

> [!WARNING]
> OneSignal's Launch URL and `additionalData` are different fields. `OneSignalMessage::setUrl(...)` sets the first, which the SDK acts on itself on every platform and which never reaches `event.data`. A destination your own code routes from has to go through `setData(...)`, which is also OneSignal's own recommendation for mobile push. See [Laravel Backend Setup](./laravel-backend-setup.md#onesignal-push) for the `toOneSignal` shape and for what sending both costs on iOS.

### Opening a screen from a tap

The snippet above is the whole of what this package does about a tap: it hands you the payload and stops. **Nothing here routes anywhere**, and a tapped push that opens the app on its own initial route rather than on the notification's screen is this package working as built.

The ecosystem's answer is `magic_deeplink`, and the wiring between the two is already done in both directions:

- `DeeplinkServiceProvider` attaches `OneSignalDeeplinkHandler` to this package's click stream whenever `notifications` is bound, so no consumer code joins them.
- That handler reads the first of `url`, `deep_link`, `link` or `uri` it finds in the payload, which is the same key list the `magic-starter-laravel` OneSignal channel writes.

What is not done for you is the last link: **an app has to register a handler of its own**, because `magic_deeplink` publishes no handler stubs at install time. Without one, `DeeplinkManager.handleUri` walks an empty list, returns `false`, and nothing is logged. A pipeline that is correct at every step and does nothing at the end looks exactly like a notification that was never tapped.

```dart
import 'package:magic/magic.dart';
import 'package:magic_deeplink/magic_deeplink.dart';

class AppServiceProvider extends ServiceProvider {
  AppServiceProvider(super.app);

  @override
  void register() {}

  @override
  Future<void> boot() async {
    app.make<DeeplinkManager>('deeplinks').registerHandler(
      RouteDeeplinkHandler(paths: const ['/notifications', '/orders/:id']),
    );
  }
}
```

`RouteDeeplinkHandler` navigates to the path the link names through `MagicRoute.to`, so the paths you list are your own in-app routes. Handlers form a first-match chain in registration order; write your own `DeeplinkHandler` when a tap has to do something other than navigate.

See [magic_deeplink handlers](https://anilcancakir.com/magic/docs/deeplink/basics/handlers) and its [installation guide](https://anilcancakir.com/magic/docs/deeplink/getting-started/installation) for the handler chain and the platform association files (`apple-app-site-association`, `assetlinks.json`) a Universal or App Link needs before any of this is reached.

<a name="onesignal-web"></a>
## OneSignalWebDriver (Web)

`OneSignalWebDriver` talks to the OneSignal Web SDK v16 through JavaScript interop (`OneSignalJsInterop`).

| Behaviour | Detail |
| :--- | :--- |
| `isSupported` | `true` on web only |
| `initialize` | Throws `PLATFORM_NOT_SUPPORTED` off web, `MISSING_APP_ID` for a blank `app_id`, and `SDK_NOT_AVAILABLE` when the OneSignal script is not loaded in `web/index.html`. It passes `safari_web_id`, `notify_button_enabled`, `service_worker_path` and `service_worker_scope` to the SDK, plus a click handler that matches by origin and focuses an open tab. |
| `login` and `requestPermission` | Throw `NOT_INITIALIZED` before `initialize` |
| `permissionState()` | Reads the browser's own `Notification.permission` |
| `oneSignalId` | The OneSignal internal user id, or `null` before initialisation |

`OneSignalWebDriver` is not exported from the package barrel, so reach the web driver through the `PushDriver` contract (`Notify.manager.pushDriver`); `oneSignalId` is a member of the concrete class only.

The page must load the SDK script, and must not call `OneSignal.init()` itself: the driver initialises from config. The installer adds the right `<script>` tag; see [Installation](../getting-started/installation.md#platform-setup).

<a name="conditional"></a>
## Conditional Imports via onesignal_factory.dart

The provider never imports `OneSignalDriver` or `OneSignalWebDriver` directly. It calls `createOneSignalDriver()` from `onesignal_factory.dart`, which selects an implementation with Dart's conditional imports:

```dart
import 'onesignal_stub.dart'
    if (dart.library.js_interop) 'onesignal_web.dart'
    if (dart.library.io) 'onesignal_io.dart';
```

- **Web** (`dart.library.js_interop`): `onesignal_web.dart` returns `OneSignalWebDriver()`. The guard is `js_interop` rather than the legacy HTML library because the latter is absent from a wasm compile.
- **Any `dart:io` build** (`dart.library.io`): `onesignal_io.dart` returns `OneSignalDriver()`. Desktop builds take this arm too; there `OneSignalDriver.isSupported` is `false`, so `PushChannel.isAvailable` is `false` and `initialize` throws `PLATFORM_NOT_SUPPORTED`.
- **Neither guard matches**: the stub throws `UnsupportedPlatformException`. No Flutter build target reaches it; it is the default the conditional import falls back to.

Each build therefore compiles only the driver arm it selects.

<a name="custom"></a>
## Creating a Custom Driver

To add FCM or another push service, extend `PushDriver`:

```dart
import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:magic_notifications/magic_notifications.dart';

class FcmDriver extends PushDriver {
  final StreamController<PushNotificationEvent> _receivedController =
      StreamController<PushNotificationEvent>.broadcast();
  final StreamController<PushNotificationEvent> _clickedController =
      StreamController<PushNotificationEvent>.broadcast();
  final StreamController<PushPermissionState> _permissionController =
      StreamController<PushPermissionState>.broadcast();
  final StreamController<PushIdentityChange> _identityController =
      StreamController<PushIdentityChange>.broadcast();

  @override
  String get name => 'fcm';

  @override
  bool get isSupported => !kIsWeb && (Platform.isIOS || Platform.isAndroid);

  @override
  Future<PushPermissionState> permissionState() async =>
      PushPermissionState.notDetermined;

  @override
  bool get isOptedIn => false;

  @override
  Future<void> initialize(Map<String, dynamic> config) async {
    // FirebaseMessaging.instance.getToken(); and so on.
  }

  @override
  Future<void> login(String externalId) async {/* store the token */}

  @override
  Future<void> logout() async {/* remove the token */}

  @override
  Future<String?> currentExternalId() async => null;

  @override
  Future<String?> currentSubscriptionId() async => null;

  @override
  Future<bool> requestPermission() async => false;

  @override
  Future<void> optIn() async {}

  @override
  Future<void> optOut() async {}

  @override
  Future<void> setTags(Map<String, String> tags) async {}

  @override
  Future<void> removeTag(String key) async {}

  @override
  Stream<PushNotificationEvent> get onNotificationReceived =>
      _receivedController.stream;

  @override
  Stream<PushNotificationEvent> get onNotificationClicked =>
      _clickedController.stream;

  @override
  Stream<PushPermissionState> get onPermissionChanged =>
      _permissionController.stream;

  @override
  Stream<PushIdentityChange> get onIdentityChanged =>
      _identityController.stream;

  // reachability() is inherited from the base class.
}
```

Register it in code before `NotificationServiceProvider` boots (a provider's `register()` always runs before any `boot()`), and select it by name in the config:

```dart
import 'package:magic/magic.dart';
import 'package:magic_notifications/magic_notifications.dart';

class FcmServiceProvider extends ServiceProvider {
  FcmServiceProvider(super.app);

  @override
  void register() {
    Notify.extend('fcm', () => FcmDriver());
  }
}
```

```dart
// In `notificationConfig`, under the `notifications` key.
Map<String, dynamic> get notificationConfig => {
  'notifications': {
    'push': {
      'driver': 'fcm',
    },
  },
};
```

The provider then resolves your driver by that name, registers `PushChannel` on it and reconciles the push identity through it. A value of `driver` that nothing was registered under is logged at error level and push stays off. When `notifications.push.app_id` is non-empty the provider also calls `initialize` with the OneSignal-shaped config map; leave `app_id` unset and call `initialize` yourself when your driver takes other settings.

<a name="gotchas"></a>
## Gotchas

| Mistake | Fix |
| :--- | :--- |
| Expecting a tapped push to open a screen | Nothing routes for you. Register a `magic_deeplink` handler (see [Opening a screen from a tap](#opening-a-screen-from-a-tap)) or route from `Notify.manager.onPushClicked`. |
| Sending the destination with OneSignal's `setUrl` | That is the Launch URL; it never reaches `event.data`. Put the route in `setData('url', ...)`. |
| Calling `requestPermission()` on a denied device | No OS dialog appears. On iOS and Android OneSignal shows its own English dialog offering the settings page (`fallback_to_settings`, on by default); on web, or with that key `false`, nothing is shown. Read `reachability()` or `Notify.manager.pushPromptAdvice()` first, and point at the settings when it is `blocked`. |
| Calling `login` or `requestPermission` before `initialize` | Both throw `NOT_INITIALIZED`. Let the provider initialise the driver, and check `NotificationServiceProvider.pushInitializationError` when it did not come up. |
| Blank `notifications.push.app_id` | The provider skips initialisation, `isInitialized` stays `false` and `reachability()` answers `unavailable`. Set the App ID. |
| Initialising the web SDK in `index.html` as well | The driver initialises from config; a second `OneSignal.init()` call duplicates it. The page only loads the SDK script. |

<a name="related-documentation"></a>
## Related Documentation

- [Channels](./channels.md): `PushChannel` and how a driver backs it.
- [Notification Manager](../architecture/notification-manager.md): driver resolution and identity reconcile.
- [Service Provider](../architecture/service-provider.md): where the driver is initialised.
- [Configuration](../getting-started/configuration.md): the `notifications.push` keys the drivers read.
- [Handlers in magic_deeplink](https://anilcancakir.com/magic/docs/deeplink/basics/handlers): routing a tapped push.
