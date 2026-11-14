# Installation

Add Magic Notifications to a Magic app, register its provider, and wire the platform files a push needs to reach a device.

- [Quick Start](#overview)
- [Dependency Setup](#pubdev)
- [CLI Installation Wizard](#cli-wizard)
- [Service Provider Registration](#service-provider)
- [Config Factory in main.dart](#main-dart)
- [Platform Setup Summary](#platform-setup)
- [Related Documentation](#related-documentation)

<a name="overview"></a>
## Quick Start

```bash
flutter pub add magic_notifications
dart run magic:dowel plugin:install magic_notifications
dart run magic:dowel notifications:install
dart run magic:dowel notifications:doctor
```

| Step | What it does |
| :--- | :--- |
| `plugin:install` | Injects `NotificationServiceProvider` into `lib/config/app.dart` and registers the package's commands with dowel |
| `notifications:install` | Writes `lib/config/notifications.dart` and the platform files, then wires the config into `lib/main.dart` |
| `notifications:doctor` | Reports what is still missing |

> [!NOTE]
> The wizard is the recommended path. A manual setup has to repeat every step it performs; use it only when a pipeline needs fully scripted control.

<a name="pubdev"></a>
## Dependency Setup

```bash
flutter pub add magic_notifications
```

The package builds on `magic`, `magic_socket` (realtime delivery), `dowel` (the CLI), `onesignal_flutter` and `wind_kit`; `pub` resolves all of them. For local development inside a monorepo, point the dependency at the checkout:

```yaml
dependencies:
  magic_notifications:
    path: ./plugins/magic_notifications
```

<a name="cli-wizard"></a>
## CLI Installation Wizard

Run the wizard from the Flutter project root, after `plugin:install`:

```bash
dart run magic:dowel notifications:install
```

It asks for:

1. **OneSignal App ID**: a UUID, from the [OneSignal Dashboard](https://onesignal.com/). The wizard asks again until the format is valid.
2. **Platforms**: it detects the platform directories the project has and asks to confirm each one.
3. **Web options** (only when web is selected): an optional legacy Safari Web ID and the OneSignal notify button.
4. **Soft prompt**: whether `soft_prompt.enabled` is written as `true`.

### Non-Interactive Mode

```bash
dart run magic:dowel notifications:install \
  --non-interactive \
  --app-id 12345678-1234-1234-1234-123456789012 \
  --platforms android,ios,web
```

```bash
# Web extras
dart run magic:dowel notifications:install \
  --non-interactive \
  --app-id 12345678-1234-1234-1234-123456789012 \
  --platforms web \
  --safari-web-id web.onesignal.auto.xxx \
  --notify-button
```

```bash
# Disable the soft prompt and overwrite an existing config
dart run magic:dowel notifications:install \
  --non-interactive \
  --app-id 12345678-1234-1234-1234-123456789012 \
  --no-soft-prompt \
  --force
```

`--app-id` is required in non-interactive mode and an invalid UUID stops the command before anything is written. See the [CLI reference](../basics/cli.md#install) for every flag.

### What the CLI Produces

| Artifact | Path |
| :--- | :--- |
| Notification config | `lib/config/notifications.dart` (skipped with a warning when it exists, unless `--force`) |
| Android permission | `android/app/src/main/AndroidManifest.xml` (`POST_NOTIFICATIONS`) |
| iOS background mode | `ios/Runner/Info.plist` (`UIBackgroundModes` gains `remote-notification`) |
| iOS entitlements | `ios/Runner/Runner.entitlements` (`aps-environment` `development`) and `ios/Runner/RunnerRelease.entitlements` (`production`), both created if absent |
| iOS build setting | `ios/Runner.xcodeproj/project.pbxproj` (`CODE_SIGN_ENTITLEMENTS` per configuration) |
| Web service worker | `web/OneSignalSDKWorker.js` |
| Web SDK script | `web/index.html` (injected once) |
| Provider injection | `lib/config/app.dart` |
| Config factory | `lib/main.dart` (import plus a `configFactories` entry) |

> [!TIP]
> Run `dart run magic:dowel notifications:doctor` straight after the install to see every artifact it checks.

<a name="service-provider"></a>
## Service Provider Registration

`plugin:install` has already edited `lib/config/app.dart`. For a manual setup, add the import and the provider entry:

```dart
import 'package:magic_notifications/magic_notifications.dart';

final providers = [
  // ... other providers
  (app) => NotificationServiceProvider(app),
];
```

`NotificationServiceProvider` runs two phases during framework boot:

- `register()` binds `NotificationManager` as a singleton under the `'notifications'` key.
- `boot()` registers the database channel, loads the persisted push intent, resolves the push driver named by `notifications.push.driver`, registers the push channel and initialises the driver when an App ID is set, then reconciles the device's push identity once. It starts no polling.

See [Service Provider](../architecture/service-provider.md) for the full boot sequence.

<a name="main-dart"></a>
## Config Factory in main.dart

The notification config reaches `Magic.init` as a config factory:

```dart
import 'package:flutter/widgets.dart';
import 'package:magic/magic.dart';

import 'config/app.dart'; // The host's own config: declares `appConfig`.
import 'config/notifications.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Magic.init(
    configFactories: [
      () => appConfig,
      () => notificationConfig, // added by notifications:install
    ],
  );

  runApp(const MyApp()); // `MyApp` is the host's own root widget.
}
```

The `notificationConfig` getter lives in `lib/config/notifications.dart`, written by `notifications:install` or `notifications:publish`. Its core shape:

```dart
Map<String, dynamic> get notificationConfig => {
  'notifications': {
    'push': {
      'driver': 'onesignal',
      'app_id': '12345678-1234-1234-1234-123456789012',
      'service_worker_path': 'OneSignalSDKWorker.js',
      'service_worker_scope': '/onesignal/',
      'notify_button_enabled': false,
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

The generated file carries more keys than this and comments on each; [Configuration](./configuration.md) documents all of them. To keep the App ID out of source control, read it with `env('ONESIGNAL_APP_ID')` instead of a literal, as described there.

<a name="platform-setup"></a>
## Platform Setup Summary

### iOS

The CLI writes the project-file markers a push needs, without opening Xcode: `UIBackgroundModes` gains `remote-notification` in `Info.plist`, `aps-environment` is declared in both entitlements files (`development` for Debug and Profile, `production` for Release), and `CODE_SIGN_ENTITLEMENTS` is pointed at the right file per build configuration. Xcode never reads an entitlements file that no build setting names, which is why the doctor checks the setting and not just the file.

What stays manual, because it needs an Apple or OneSignal account rather than a project-file edit:

1. Run `cd ios && pod install --repo-update && cd ..`.
2. Create an APNs key in the [Apple Developer Portal](https://developer.apple.com/account/resources/authkeys/list) (a `.p8` file, its Key ID and your Team ID). One key covers Sandbox and Production, it is team-wide, and it downloads exactly once.
3. Upload the `.p8` key to the OneSignal Dashboard (Settings, Platforms, Apple iOS (APNs)) with the Key ID, your Team ID and your bundle identifier.

The installer declines to repoint a project that already names a different entitlements file, one whose configurations are none of Debug, Profile or Release, and one whose project file it cannot rewrite. Each case prints what to do by hand; [Shipping push in a release build](../basics/shipping-push.md#release-apns-environment) covers them.

#### The Notification Service Extension

Push works without the next two steps, which is why they need saying: a build with no extension delivers notifications normally and quietly reports no confirmed deliveries, no rich media and no badge counts. `notifications:doctor` warns when either half is missing. Neither can be automated from a pub package, because both add or change an Xcode target:

4. **App Group.** In Xcode, add the App Groups capability to the **Runner** target with a container named `group.<your.bundle.id>.onesignal`.
5. **Notification Service Extension.** File, New, Target, Notification Service Extension, named `OneSignalNotificationServiceExtension`. Add the **same** App Group to that new target and follow OneSignal's current [Flutter SDK setup](https://documentation.onesignal.com/docs/flutter-sdk-setup) for the extension's source and deployment target.

The two halves fail independently. An extension with no shared App Group still gives rich media but no confirmed delivery, because the container is how the extension hands what it saw back to the app.

> [!WARNING]
> Test the cold-start path with a **profile or release** build. iOS refuses to launch a debug Flutter build outside the Flutter tooling, and OneSignal documents that on iOS in Debug a force-closed app opened from a notification does not register the click listener at all. A cold tap that appears to do nothing in Debug is usually this, not your wiring.

### Android

The CLI injects `POST_NOTIFICATIONS` into `android/app/src/main/AndroidManifest.xml`:

```xml
<uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>
```

### Web

The CLI writes the service worker and injects the SDK script. Done by hand:

**`web/OneSignalSDKWorker.js`**:

```javascript
importScripts("https://cdn.onesignal.com/sdks/web/v16/OneSignalSDK.sw.js");
```

**`web/index.html`**, inside `<head>`:

```html
<script src="https://cdn.onesignal.com/sdks/web/v16/OneSignalSDK.page.js" defer></script>
<script>
  window.OneSignalDeferred = window.OneSignalDeferred || [];
</script>
```

> [!NOTE]
> The worker file uses `OneSignalSDK.sw.js` and the page uses `OneSignalSDK.page.js`: they are different build targets. Do not call `OneSignal.init()` in `index.html`; the Dart driver initialises the SDK from `lib/config/notifications.dart`.

> [!IMPORTANT]
> **iOS Safari only receives web push after the site is added to the Home Screen.** Per [OneSignal's documentation](https://documentation.onesignal.com/docs/en/web-push-for-ios), this "will work on iOS devices only after users add your site to their home screen and open it from there. This is Apple's design requirement." There is no workaround for a plain Safari tab; the app has to tell the person to add the site to their Home Screen first.

<a name="related-documentation"></a>
## Related Documentation

- [Configuration](./configuration.md): every `notifications.*` key.
- [CLI Reference](../basics/cli.md): the full command and flag list.
- [Shipping push in a release build](../basics/shipping-push.md): the differences a development build hides.
- [Service Provider](../architecture/service-provider.md): what `boot()` does.
- [Channels](../basics/channels.md) and [Drivers](../basics/drivers.md): sending and the push SDK layer.
- [Laravel Backend Setup](../basics/laravel-backend-setup.md): the API this package talks to.
- [Magic installation](https://anilcancakir.com/magic/docs/getting-started/installation): the framework this plugin extends.
- [Realtime delivery with magic_socket](https://anilcancakir.com/magic_socket/docs/getting-started/installation): the socket layer behind `Notify.startRealtime`.
