# Configuration

Every `notifications.*` config key the package reads, what each one defaults to, and the behaviour behind it.

- [Overview](#overview)
- [Full Config Map Reference](#config-map)
- [notifications.push](#push)
- [Asking for permission](#permission)
- [Describing the user](#attributes)
- [notifications.database](#database)
- [notifications.soft_prompt](#soft-prompt)
- [Environment Variables](#env)
- [Runtime Config Access](#runtime)
- [Related Documentation](#related-documentation)

<a name="overview"></a>
## Overview

All configuration lives in one Dart map returned by `notificationConfig`, by default in `lib/config/notifications.dart`. Magic's config repository merges it at boot, so `Config.get(key)` resolves a value anywhere in the app.

> [!NOTE]
> Create the file with `dart run magic:dowel notifications:publish` or `dart run magic:dowel notifications:install` rather than by hand: the generated file carries a comment on every key. `notifications:configure` edits individual values later.

The generated file also contains a `mail` block. Nothing in the package reads it and the package has no mail channel, so delete it or leave it.

<a name="config-map"></a>
## Full Config Map Reference

```dart
Map<String, dynamic> get notificationConfig => {
  'notifications': {
    'push': {
      'driver': 'onesignal',
      'app_id': env('ONESIGNAL_APP_ID'),
      // 'safari_web_id': 'web.onesignal.auto.xxx', // legacy Safari only
      'service_worker_path': 'OneSignalSDKWorker.js',
      'service_worker_scope': '/onesignal/',
      'notify_button_enabled': false,
      'self_test_enabled': false,
      'auto_request_on_login': false,
      'reprompt_after_hours': 0,
      'fallback_to_settings': true,
      'share_user_attributes': false,
    },
    'push_state': {
      'report_path': null, // e.g. '/devices/push-state'
      'release_path': null, // e.g. '/devices/push-state/release'
      'external_id_prefix': null, // 'user_' when absent
    },
    'database': {
      'enabled': true,
      'polling_interval': 30,
    },
    'soft_prompt': {
      'enabled': true,
    },
  },
};
```

The `push_state` keys are covered in [Telling your backend whether the device can be paged](../basics/shipping-push.md#telling-your-backend-whether-the-device-can-be-paged) and [Laravel Backend Setup](../basics/laravel-backend-setup.md#onesignal-push).

<a name="push"></a>
## notifications.push

Controls the push channel and its driver.

| Key | Type | Default | Description |
| :--- | :--- | :--- | :--- |
| `driver` | `String` | none | Name of the push driver. `'onesignal'` is the only built-in one; an absent key means no push is configured and everything else keeps working. Any other value is logged at error level and push stays off, unless a driver of that name was registered with `Notify.extend`. |
| `app_id` | `String` | none | OneSignal App ID (UUID). Push initialises only when it is non-empty. |
| `safari_web_id` | `String?` | none | Legacy Safari Web Push ID. Modern Safari subscribes over VAPID and needs none. |
| `service_worker_path` | `String?` | none | Web only. Path of the OneSignal service worker. Written as `OneSignalSDKWorker.js` by the installer; an absent key sends nothing, so OneSignal uses its own default. |
| `service_worker_scope` | `String?` | none | Web only. Scope OneSignal registers its worker under. Written as `/onesignal/` by the installer. A Flutter web build already owns the root scope with `flutter_service_worker.js`, and whichever registration lands second wins that scope, so OneSignal needs a scope of its own. |
| `notify_button_enabled` | `bool` | `false` | Web only. Show the floating OneSignal notify button. |
| `auto_request_on_login` | `bool` | `false` | Whether the package may raise the OS permission prompt by itself, once, after an identity is declared with `Notify.initializePush(userId)`. See [Asking for permission](#permission). |
| `reprompt_after_hours` | `int` | `0` | Hours before the app's own reminder may return to somebody who turned it down. `0` and an absent key mean never. Read by `NotificationManager.pushPromptAdvice()`. |
| `fallback_to_settings` | `bool` | `true` | Mobile only. Whether a denied device keeps a route back: the reminder's open-settings button (`Notify.openPushSettings()`) and the SDK's settings fallback on `requestPermission()`. Inert on web. |
| `share_user_attributes` | `bool` | `false` | Whether the email and tags described with `Notify.describePushUserUsing` are sent to OneSignal at all. See [Describing the user](#attributes). |
| `self_test_enabled` | `bool` | `false` | Gates `PushChannel`, the client-triggered send that asks the backend to push a test notification to the caller's own devices. While it is off, `PushChannel.isAvailable` is `false` and the manager skips the channel. The backend carries the matching `magic-starter.onesignal.self_test_enabled` switch, also off by default, and answers `501` while it is off: set both or neither. |

> [!NOTE]
> `NotificationServiceProvider.boot()` reads `notifications.push.driver`. For `'onesignal'` it builds `OneSignalWebDriver` on web and `OneSignalDriver` on iOS and Android, then initialises it with `app_id`, `safari_web_id`, `service_worker_path`, `service_worker_scope` and `notify_button_enabled`. A key that is absent stays out of the map the SDK receives.

<a name="permission"></a>
## Asking for permission

There are two separate cadences here, and conflating them is the mistake this section exists to prevent.

**The OS prompt is a one-shot.** Once a person has answered it, no code can raise it again: on the web `Notification.requestPermission()` against a denied origin resolves immediately with `denied` and shows nothing, and iOS and Android behave the same way. The only route back is the browser's site settings or the OS Settings app. So an automatic request is worth exactly one shot, on a device that has never been asked.

**The app's own reminder is not a one-shot.** It is your UI, and it may appear on whatever cadence you configure, including on a device whose OS permission is denied: on mobile its button opens the app's own notification settings page directly (see `fallback_to_settings`), which is a real route back.

### The automatic request

With `auto_request_on_login: true`, the package raises the platform request once, from `want()` (which `Notify.initializePush(userId)` calls), and only when:

- the OS has never asked on this device (`PushDriver.canRaisePermissionRequest()`),
- the device is not already subscribed (its reachability is `off`),
- and it has not already been raised in this launch.

It is never raised from `reconcilePushIdentity()`, which runs on every auth-state change and on a signed-out boot: a dialog from there arrives with nothing in front of it explaining what it is for.

> [!WARNING]
> On web, browsers require a user gesture for a permission request and a login is not one, so this key can spend the ask without rendering it. Prefer the reminder below, whose button is a tap.

### The reminder, and what its button can do

Ask the package rather than deriving it:

```dart
final advice = await Notify.manager.pushPromptAdvice(
  declinedAt: await myOwnStorage.readPushPromptDeclinedAt(),
);

if (!advice.show) return const SizedBox.shrink();

return switch (advice.action) {
  // A real dialog will appear: Notify.requestPushPermission().
  PushPromptAction.request => MyEnableRow(),
  // The prompt is spent, but this platform can open the app's own
  // notification settings page: Notify.openPushSettings().
  PushPromptAction.openSettings => MyOpenSettingsRow(),
  // Nowhere to send the tap. Say where the switch lives instead.
  PushPromptAction.instructions => MyBlockedInstructionsRow(),
  PushPromptAction.none => const SizedBox.shrink(),
};
```

`advice.show` already accounts for `reachability()`, `reprompt_after_hours`, `soft_prompt.enabled` and the timestamp you passed in. `advice.reachability` is the same four-state read, carried so a status row does not need a second platform call. The package ships this row as `PushPromptHost`; see [Push Prompt Component](../basics/preferences.md#push-prompt).

The decline timestamp stays yours. A decline is your UI's event, recorded wherever you already keep device state; a copy inside this package would be a second answer to drift out of sync with the first.

<a name="attributes"></a>
## Describing the user

OneSignal segments and personalises on what it knows about a person: an email subscription, and tags. This package owns the transport and the identity lifecycle; your app owns the values, because "email, first name, last name" is one product's answer and the next app has different fields or is not permitted to send an address at all.

Register the description once, at boot, next to wherever you register the driver:

```dart
Notify.describePushUserUsing((String externalId) {
  final user = Auth.user<User>();
  if (user == null) return null; // nothing to describe for this identity

  return PushUserAttributes(
    email: user.email,
    tags: <String, String>{
      'first_name': user.firstName,
      'last_name': user.lastName,
    },
  );
});
```

`User` is your own model. `externalId` is the string you passed to `Notify.initializePush()`, so an app that keeps its user state elsewhere can look the right person up. The resolver is called on every login and every account switch, so nothing re-registers per login. Returning `null` says there is nothing to describe, which is the answer for a guest or for somebody who has not consented.

Nothing is sent until `share_user_attributes` is `true`. An app that registers no description sends nothing either.

### What an account switch does

Everything this package wrote is removed **before** the `login` or `logout` that moves the device on, while the SDK still points at the person it was written for. The SDK's own migration guide is the reason (`onesignal_flutter`, `MIGRATION_GUIDE.md`): a `login` to an id that does not exist yet creates the user *and applies the operations already performed under the device-scoped user to it*, and a `logout` leaves exactly such a device-scoped user behind. A removal issued after the switch therefore follows the next person onto their record, and on a shared device that is the whole problem.

The cost is that the previous person's tags come off their OneSignal record when they leave this device, and the resolver puts them straight back on their next login anywhere. The alternative is leaving a name and an email address attached to a subscription that has moved to somebody else.

Only what this package wrote is ever removed. A tag set from the OneSignal dashboard, from your backend, or from another client is not this device's to delete.

### Two things to get right

**A tag written from a client is user-tamperable.** Anybody holding the app can call the SDK from a browser console and write whatever they like under any key. That is fine for choosing an audience and fine for personalising a message. It is not fine for anything a backend later trusts: a plan tier, an entitlement, a role, a quota. Those belong in a server-side tag write over OneSignal's REST API, from the system that already owns the fact. This package ships no such path.

**An email address and a name are personal data going to a third party.** That is what `share_user_attributes` gates, and why it ships off. It gates the whole seam rather than the email alone, because this package cannot tell one tag from another: `{'first_name': 'Ada'}` is as personal as an address and `{'plan': 'pro'}` is not, and both arrive here as two strings.

### Platform parity

Both OneSignal drivers implement the same four calls (`setTags`, `removeTags`, `addEmail`, `removeEmail`) against the same v16 user model, so a description behaves identically on mobile and on the web. The one difference is a browser's to make: the web SDK is whatever script your `web/index.html` loads, so the driver checks that `User.addEmail` exists before it uses it and reports through the log when it does not, instead of accepting an address that went nowhere.

A custom `PushDriver` inherits `removeTags` (a loop over `removeTag`) and an `addEmail` that sends nothing and says so in the log.

<a name="database"></a>
## notifications.database

Controls polling for in-app notifications.

| Key | Type | Default | Description |
| :--- | :--- | :--- | :--- |
| `enabled` | `bool` | `true` | Written by the installer and shown by `notifications:channels`. The runtime does not read it: `DatabaseChannel` is always registered and always available. |
| `polling_interval` | `int` | `30` | Seconds between `GET /notifications` requests. Supported range: 5 to 600. |

Change the interval with:

```bash
dart run magic:dowel notifications:configure --polling-interval 60
```

The runtime reads this key when it builds the poller, which is the first `startPolling()` and any `startPolling()` after a `stopPolling()`, including the automatic handoff when a realtime socket drops (that path stops the poller first). A change therefore takes effect on the next start.

It does not take effect across `pausePolling()` and `resumePolling()`: those keep the same poller instance, so it keeps the interval it was constructed with. Call `stopPolling()` and then `startPolling()` to apply a new value to a poller that is already running.

A value the reader cannot use is logged rather than thrown, because this is a timer wired to your auth state and a mistyped number must not take notification delivery down:

| Configured | Used | Why |
| :--- | :--- | :--- |
| absent | 30 | the default |
| below 5, including `0` and negatives | 5 | `Timer.periodic` accepts `0` and then fires on every event-loop turn |
| above 600 | 600 | the supported range, enforced |
| not an `int` (`'30'`, `30.0`) | 30 | the value is type-checked rather than cast, so it reads as absent |

<a name="soft-prompt"></a>
## notifications.soft_prompt

| Key | Type | Default | Description |
| :--- | :--- | :--- | :--- |
| `enabled` | `bool` | `true` | Whether your own soft prompt should show before `Notify.requestPushPermission()`. `NotificationManager.pushPromptAdvice()` honours it (`false` answers `show: false`), so a call site using that API does not check it a second time. |

The installer writes `title` and `message` keys beside `enabled` as copy suggestions for a prompt you build yourself. The package never reads them; `PushPrompt` takes its strings from translation keys (see [Push Prompt Component](../basics/preferences.md#push-prompt)).

A call site that needs the raw device state reads `reachability()` on the resolved driver (see [Drivers](../basics/drivers.md#abstract)); one deciding whether to interrupt somebody asks `pushPromptAdvice()` instead, which folds this key, the re-prompt interval and the platform's route back into one answer.

```dart
final reachability = await Notify.manager.pushDriver.reachability();

if (reachability == PushReachability.blocked) {
  // The OS will not re-prompt. Point at the platform setting instead.
}
```

<a name="env"></a>
## Environment Variables

The installer writes the App ID as a literal. To keep it out of source control, read it from `.env` with Magic's `env` helper:

```dart
'app_id': env('ONESIGNAL_APP_ID'),
```

```
ONESIGNAL_APP_ID=12345678-1234-1234-1234-123456789012
```

`notifications:doctor` recognises `env('KEY')`, `env<String>('KEY')` and an `envString('KEY', fallback)` wrapper. It cannot read the value a build will see, so it reports the key it comes from, and warns when `.env` is missing or carries nothing for that key. A form it does not recognise, such as `String.fromEnvironment`, reads as an App ID that is not configured.

Magic loads `.env` as a Flutter asset; see [Magic configuration](https://anilcancakir.com/magic/docs/getting-started/configuration).

<a name="runtime"></a>
## Runtime Config Access

After Magic boots, any value is available through `Config.get`:

```dart
final appId = Config.get<String>('notifications.push.app_id');
final interval = Config.get<int>('notifications.database.polling_interval');
final softPrompt = Config.get<bool>('notifications.soft_prompt.enabled');
```

`Config.get` returns `null` when the key is absent or has another type; use `??` for a default:

```dart
final selfTest = Config.get<bool>('notifications.push.self_test_enabled') ?? false;
```

<a name="related-documentation"></a>
## Related Documentation

- [Installation](./installation.md): how the config file gets into the app.
- [Service Provider](../architecture/service-provider.md): which keys `boot()` reads.
- [CLI Reference](../basics/cli.md): `configure` and `publish`.
- [Preferences](../basics/preferences.md): the push prompt component and its translation keys.
- [Shipping push in a release build](../basics/shipping-push.md): service worker settings and device reachability reports.
