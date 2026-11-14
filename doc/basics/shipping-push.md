# Shipping push in a release build

The differences between a development build and a release build that stop push from arriving without any error, and how to check each before you submit.

- [Release signs against a different APNs environment](#release-apns-environment)
- [.env is compiled into the app](#env-compiled)
- [The APNs key has to be on the OneSignal side](#apns-key)
- [On the web, the dashboard's site type decides whether your worker config is read](#web-site-type)
- [Telling your backend whether the device can be paged](#telling-your-backend-whether-the-device-can-be-paged)
- [Before you submit](#before-you-submit)
- [Gotchas](#gotchas)
- [Related Documentation](#related-documentation)

[Installation](../getting-started/installation.md) gets push working on a device you build to from your own machine. A release build is a different set of conditions, and each difference below is silent: nothing errors, nothing logs, and the first evidence is a notification nobody receives.

<a name="release-apns-environment"></a>
## Release signs against a different APNs environment

A development provisioning profile carries `aps-environment: development`. A distribution profile carries `production`. They are not interchangeable, so one entitlements file cannot serve both and the project needs two:

```
ios/Runner/Runner.entitlements         aps-environment  development   Debug, Profile
ios/Runner/RunnerRelease.entitlements  aps-environment  production    Release
```

**`notifications:install` writes both and points each configuration at its own**, so a project installed through it starts out correct. The Release twin is a copy of the development file, because every other key has to be identical between them. An existing twin is never overwritten.

It declines these cases, and prints what to do instead:

- **A project that already names a different entitlements file.** Moving some configurations and not the rest is worse than moving none, so nothing is repointed. That includes every project an earlier run of this installer touched: both files are written there, and the Release build setting is yours to point.
- **A project whose configurations are none of Debug, Profile or Release.** Flavours are handled, by base name, so `Release-production` gets the twin. A name outside that shape is left alone, since nothing here can tell which profile it signs with.
- **A file it cannot read.** An entitlements plist with no root `<dict>` or one that does not parse, and a `project.pbxproj` the editor will not rewrite byte for byte. The install itself still succeeds and exits `0`; only the entitlement wiring is left to you.

None of them ends the install. They print a warning naming what stopped them and the manual step that clears it, because by the time this runs the rest of the install has already landed.

To do it by hand, set `CODE_SIGN_ENTITLEMENTS = Runner/RunnerRelease.entitlements` on the Release configuration (Xcode: select the Runner target, Build Settings, Code Signing Entitlements, expand the row, edit the Release line).

The trap that makes this worth a section: Xcode's Signing and Capabilities tab writes to whichever configuration is selected, and that is Debug, so a capability added the obvious way reaches every build except the one that ships.

`notifications:doctor` reads the value each configuration signs against and warns about the ones a profile cannot use:

```
IOS: ✓ Configured, 1 warning
      ⚠ the Release configuration signs against ios/Runner/Runner.entitlements,
        which declares aps-environment development where a distribution
        provisioning profile carries production
```

Flavours are read by base name, so `Release-production` and `Release-staging` are both judged as a Release: `aps-environment` follows the provisioning profile, and every flavour of a release build signs with a distribution one. A configuration whose name is neither Debug, Profile nor Release is named as unchecked rather than passed over, and it is named even when its siblings were checked. A warning does not fail the command, but the summary never claims everything passed.

What it costs to get wrong: the export fails, or it succeeds and the app registers a sandbox APNs token that a production build can never deliver to.

<a name="env-compiled"></a>
## .env is compiled into the app

Magic reads `.env` at startup, and the file is a Flutter asset (see [Magic configuration](https://anilcancakir.com/magic/docs/getting-started/configuration)). Whatever sits in it at build time is baked into the binary, and there is no later chance to correct it.

A development `.env` usually points at a local API. On a phone `localhost` is the phone, so the app reaches nothing, and if your Sentry DSN lives in the same file the failure is also unreported.

`Magic.init` takes the filename, so select it by build mode:

```dart
await Magic.init(
  envFileName: kReleaseMode ? '.env.production' : '.env',
  configFactories: [...],
);
```

Register both files as assets in `pubspec.yaml` when you do. The alternative is a release script that swaps the file in, builds, restores it, and then reads the built artifact back to confirm what actually shipped; either way, no gate catches this on your behalf.

<a name="apns-key"></a>
## The APNs key has to be on the OneSignal side

Creating the `.p8` in the Apple Developer portal is step one of two. Until it is uploaded to OneSignal (Settings, Platforms, Apple iOS), OneSignal cannot authenticate to APNs and every token it tries is invalid.

One key covers Sandbox and Production, it is team-wide, and it downloads exactly once. A key created for development work is the same key a release build needs; there is nothing to redo.

No CLI can check this for you: it is dashboard state behind an authenticated API, and `notifications:doctor` reads your repository.

<a name="web-site-type"></a>
## On the web, the dashboard's site type decides whether your worker config is read

`notifications.push.service_worker_path` and `service_worker_scope` are sent to the Web SDK as `serviceWorkerPath` and `serviceWorkerParam`. OneSignal's own documentation states that `serviceWorkerPath` does not apply to a **Typical Site** app; it applies to **Custom Code**. A dashboard app left on Typical Site ignores both, registers its worker at the root scope, and then whichever of it and `flutter_service_worker.js` registers second wins.

If web push works intermittently, or the app's own service worker stops updating, check the site type before the config.

The same split decides what a click does with a tab that is already open. On Custom Code the driver initialises the SDK with `notificationClickHandlerMatch: 'origin'` and `notificationClickHandlerAction: 'focus'`: a click focuses any open tab of the app and hands it the click, so `Notify.manager.onPushClicked` fires there and your deep link handler routes the push. With no tab open, the browser opens the push's `web_url`. The SDK's defaults (`exact`, `navigate`) would ignore every open tab whose url is not the launch url exactly and open a second tab, where no Dart is running yet to receive the click. A Typical Site app reads this from the dashboard's web settings instead; set the same pair there.

<a name="telling-your-backend-whether-the-device-can-be-paged"></a>
## Telling your backend whether the device can be paged

Everything above decides whether a push can arrive. Whether your backend knows is a separate question: OneSignal accepts a push for a subscription that is denied, opted out or gone, and reports nothing back. If your backend escalates on push alone, `Notify.pushState` gives it the device's own answer. Configure both endpoints (see [Laravel Backend Setup](./laravel-backend-setup.md#onesignal-push) for the server half), arm the watch once, and release before the token goes:

```dart
// In a provider's boot(), once auth is registered.
Notify.pushState.watch();

// On sign-out, BEFORE Auth.logout(): a release after it is a guaranteed 401.
if (Notify.pushState.isConfigured) await Notify.pushState.release();
await Auth.logout();
```

`watch()` reports after every identity reconcile for the signed-in person (`<external_id_prefix><Auth.id()>`, `user_` by default), whenever the driver's permission or subscription moves, and once as `unavailable` for a build with no push driver at all. A memo stops repeats and is forgotten on every `AuthLogout`. Skip the release and the server keeps vouching for a handset the person has left, under their name, until its own freshness horizon expires.

`isConfigured` is `true` only when both `notifications.push_state.report_path` and `release_path` are set. With only one of them, `watch()` logs an error and stays off.

<a name="before-you-submit"></a>
## Before you submit

- `dart run magic:dowel notifications:doctor` is clean, including the iOS configuration rows.
- If your backend reads device reachability, a sign-out from the release build posts to `notifications.push_state.release_path` before the token is gone.
- The `.env` inside the built artifact is the production one. Unzip the `.ipa` and read `Payload/*.app/Frameworks/App.framework/flutter_assets/.env`.
- The signed binary carries the production entitlement: `codesign -d --entitlements :- Payload/*.app` reports `aps-environment: production`.
- A push sent to the build's own subscription arrives on a device that installed it from TestFlight, not from Xcode.

<a name="gotchas"></a>
## Gotchas

| Mistake | Fix |
| :--- | :--- |
| Adding the Push capability in Xcode's Signing and Capabilities tab and calling it done | The tab writes to the selected configuration, which is Debug. Point `CODE_SIGN_ENTITLEMENTS` on Release at `RunnerRelease.entitlements`, and let `notifications:doctor` confirm it. |
| Reading a clean `notifications:doctor` as proof push works | It reads your repository. It cannot see whether the `.p8` key is uploaded to OneSignal or which site type the dashboard app uses. |
| Building a release with the development `.env` | Select the file with `Magic.init(envFileName: ...)` and check the built artifact. |
| Calling `Notify.pushState.release()` after `Auth.logout()` | The token is gone and the request is a guaranteed 401. Release first. |
| Setting only one of `report_path` and `release_path` | `watch()` logs an error and stays off. Set both or neither. |

<a name="related-documentation"></a>
## Related Documentation

- [Installation](../getting-started/installation.md): the development-build setup this page builds on.
- [CLI Reference](./cli.md#doctor): what `notifications:doctor` checks and warns about.
- [Laravel Backend Setup](./laravel-backend-setup.md#onesignal-push): the server half of device reachability.
- [Drivers](./drivers.md#opening-a-screen-from-a-tap): routing a tapped push.
- [Configuration](../getting-started/configuration.md): the `push` and `push_state` keys.
