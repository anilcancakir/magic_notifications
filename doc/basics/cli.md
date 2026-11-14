# CLI Reference

Every `notifications:*` command Magic Notifications adds to dowel, with its flags, defaults and what it changes in the project.

- [Overview](#overview)
- [install](#install)
- [configure](#configure)
- [doctor](#doctor)
- [test](#test)
- [channels](#channels)
- [uninstall](#uninstall)
- [publish](#publish)
- [Gotchas](#gotchas)
- [Related Documentation](#related-documentation)

<a name="overview"></a>
## Overview

The package has no executable of its own. Its commands run through the host app's dowel binary, and they exist once `plugin:install` has registered the package:

```bash
dart run magic:dowel plugin:install magic_notifications
dart run magic:dowel notifications:<command> [options]
```

| Command | Purpose |
| :--- | :--- |
| `notifications:install` | Wizard that writes the config, the platform files and the wiring |
| `notifications:configure` | Show or change single values in the config file |
| `notifications:doctor` | Health check of the install and the config |
| `notifications:test` | Preview a test notification payload |
| `notifications:channels` | Print the channel settings from the config file |
| `notifications:uninstall` | Remove what `install` wired into Dart files |
| `notifications:publish` | Copy the config stub without any wizard |

Every command finds the project root by walking up from the current directory to the nearest `pubspec.yaml`, so it can run from any subdirectory. `doctor` and `channels` are also exposed as read-only MCP tools (`notifications_doctor`, `notifications_channels`); the commands that change files are not.

<a name="install"></a>
## install

Sets up the integration: config file, platform files, provider injection and config factory injection.

```bash
dart run magic:dowel notifications:install
```

### Flags and Options

| Flag / Option | Type | Default | Description |
| :--- | :--- | :--- | :--- |
| `--non-interactive` | flag | `false` | Skip all prompts; every required value comes from flags |
| `--app-id` | option | none | OneSignal App ID (UUID); required in non-interactive mode |
| `--platforms` | option | `android,ios,web` | Comma-separated target platforms (non-interactive mode) |
| `--no-soft-prompt` | flag | `false` | Write `soft_prompt.enabled` as `false` (it is `true` otherwise) |
| `--safari-web-id` | option | none | Legacy Safari Web ID; modern Safari uses VAPID and needs none |
| `--notify-button` | flag | `false` | Enable the OneSignal notify button on web |
| `--force` | flag | `false` | Overwrite an existing `lib/config/notifications.dart` |
| `--dry-run` | flag | `false` | Print the staged operations without writing; the iOS entitlement work is not listed |
| `--no-bootstrap` | flag | `false` | Shared install flag; this package declares no bootstrap command |

### Examples

```bash
# Interactive wizard
dart run magic:dowel notifications:install

# CI: minimal
dart run magic:dowel notifications:install \
  --non-interactive \
  --app-id 12345678-1234-1234-1234-123456789012

# CI: web extras, overwriting an existing config
dart run magic:dowel notifications:install \
  --non-interactive \
  --app-id 12345678-1234-1234-1234-123456789012 \
  --platforms android,ios,web \
  --safari-web-id web.onesignal.auto.xxx \
  --notify-button \
  --force
```

### What Install Produces

1. `lib/config/notifications.dart` with your App ID and choices. An existing file is kept with a warning unless `--force` is passed.
2. Android: `POST_NOTIFICATIONS` in `AndroidManifest.xml`.
3. iOS: `remote-notification` in `UIBackgroundModes` of `ios/Runner/Info.plist`; `aps-environment` in `ios/Runner/Runner.entitlements` (`development`) and `ios/Runner/RunnerRelease.entitlements` (`production`); `CODE_SIGN_ENTITLEMENTS` pointed at the right file per build configuration in `project.pbxproj`.
4. Web: `web/OneSignalSDKWorker.js`, and the SDK `<script>` in `web/index.html`, injected once.
5. `NotificationServiceProvider` in `lib/config/app.dart`.
6. The config import and a `() => notificationConfig,` entry in `lib/main.dart`'s `configFactories`. When no config getter can be read from the file, `main.dart` is left alone and the command prints what to add.

The provider injection and the platform edits are written as the install runs and are not rolled back if a later step fails; the config file and the web worker are written transactionally. After a `--force` run that replaces an existing config, `main.dart` is re-pointed at the regenerated getter.

> [!NOTE]
> The APNs key upload and the Apple Developer Portal steps cannot be automated; the CLI wires only the project-file side. See [Installation](../getting-started/installation.md#platform-setup).

<a name="configure"></a>
## configure

Reads or updates single settings in `lib/config/notifications.dart` without re-running the wizard.

```bash
dart run magic:dowel notifications:configure [options]
```

### Flags and Options

| Flag / Option | Type | Default | Description |
| :--- | :--- | :--- | :--- |
| `--show` | flag | `false` | Print the current values and exit |
| `--app-id` | option | none | Replace the OneSignal App ID |
| `--polling-interval` | option | none | Polling interval in seconds; valid range 5 to 600 |
| `--soft-prompt` | flag | none | Set `soft_prompt.enabled` to `true` |
| `--no-soft-prompt` | flag | none | Set `soft_prompt.enabled` to `false` |

### Examples

```bash
dart run magic:dowel notifications:configure --show
dart run magic:dowel notifications:configure --app-id 12345678-1234-1234-1234-123456789012
dart run magic:dowel notifications:configure --polling-interval 60
dart run magic:dowel notifications:configure --no-soft-prompt
```

> [!NOTE]
> The config file must already exist; run `install` or `publish` first. A polling interval that is not a number, or is outside 5 to 600, exits with code `1`.

<a name="doctor"></a>
## doctor

Health check of the plugin install, the config and the platform setup. It exits `0` when no requirement is missing and `1` when one is. A warning alone still exits `0`, but the summary never claims everything passed.

```bash
dart run magic:dowel notifications:doctor [--verbose]
```

| Flag | Type | Default | Description |
| :--- | :--- | :--- | :--- |
| `--verbose` | flag | `false` | Show file paths, required keys and per-platform issue details |

### Checks Performed

| Check | Pass condition |
| :--- | :--- |
| Plugin installed | `magic_notifications` is under `dependencies` in `pubspec.yaml` |
| Config file | `lib/config/notifications.dart` exists |
| App ID | A literal is a UUID (`xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx`), non-empty and not a placeholder; a value read with `env(...)` counts as configured |
| Polling interval | A literal `polling_interval` is within 5 to 600 |
| `soft_prompt` | The section is present in the config |
| Android | `POST_NOTIFICATIONS` is in `AndroidManifest.xml` |
| iOS | `UIBackgroundModes` in `Info.plist` lists `remote-notification`, `aps-environment` is declared in `Runner.entitlements`, and `CODE_SIGN_ENTITLEMENTS` is set in `project.pbxproj` so Xcode reads the file |
| Web | `web/OneSignalSDKWorker.js` exists |

### Warnings (exit code stays `0`)

| Warning | Meaning |
| :--- | :--- |
| App ID read from the environment | The config reads the App ID with `env(...)` and `.env` is missing or carries no value for that key, so push would initialise with an empty App ID |
| APNs environment | A build configuration signs against an entitlements file whose `aps-environment` its provisioning profile cannot use (Release needs `production`, Debug and Profile `development`), or a configuration name it cannot judge |
| Notification Service Extension | No extension target exists in the Xcode project, or one exists without the shared App Group in `Runner.entitlements` |

<a name="test"></a>
## test

Previews a test notification and simulates sending it. It makes no network request and creates nothing in a backend.

```bash
dart run magic:dowel notifications:test [options]
```

### Flags and Options

| Flag / Option | Type | Default | Description |
| :--- | :--- | :--- | :--- |
| `--dry-run` | flag | `false` | Print the preview and stop |
| `--title` | option | `Test Notification` | Notification title |
| `--body` | option | `This is a test notification from the CLI` | Notification body |
| `--channel` | option | `database` | Channel label to preview: `database` or `push` |
| `--api-url` | option | none | Backend URL echoed in the output; for `push`, omitting it prints a warning and skips the simulated send |

### Examples

```bash
# Preview only
dart run magic:dowel notifications:test --dry-run

# Preview with a custom message on the database channel
dart run magic:dowel notifications:test --title "Hello" --body "World" --channel database

# Preview the push path against a backend URL
dart run magic:dowel notifications:test --channel push --api-url http://localhost:8000
```

> [!TIP]
> To check that push really reaches a phone, use the device and the backend, not this command: [Shipping push in a release build](./shipping-push.md) covers what a release build changes.

<a name="channels"></a>
## channels

Prints the channel settings found in `lib/config/notifications.dart`.

```bash
dart run magic:dowel notifications:channels
```

The command has no flags. It prints:

- **push**: driver name, the App ID masked to its first eight characters, and the notify button state.
- **database**: enabled state and polling interval in seconds.

The values are read from the file's text, not from a running app, so an App ID read with `env(...)` prints as `NOT SET`. The config file must exist.

<a name="uninstall"></a>
## uninstall

Removes what `install` wired into Dart files.

```bash
dart run magic:dowel notifications:uninstall [--force]
```

| Flag | Type | Default | Description |
| :--- | :--- | :--- | :--- |
| `--force` | flag | `false` | Skip the confirmation prompt |

### What Uninstall Removes

| Artifact | Action |
| :--- | :--- |
| `lib/config/notifications.dart` | Deleted |
| `magic_notifications` in `pubspec.yaml` | Dependency entry removed |
| `NotificationServiceProvider` in `lib/config/app.dart` | Import and provider line removed |
| Config import and `() => <getter>,` in `lib/main.dart` | Removed, using the getter name read from the config before it is deleted; when that name cannot be read, `main.dart` is left untouched and the command says what to remove by hand |

> [!NOTE]
> Platform files are **not** reverted. Remove by hand:
> - `POST_NOTIFICATIONS` from `AndroidManifest.xml`
> - the OneSignal `<script>` tags in `web/index.html` and `web/OneSignalSDKWorker.js`
> - `aps-environment` from the entitlements files, `RunnerRelease.entitlements` and its `CODE_SIGN_ENTITLEMENTS` setting when nothing else needs them

<a name="publish"></a>
## publish

Copies the config stub to `lib/config/notifications.dart` without a wizard or platform setup. The Laravel `vendor:publish` equivalent.

```bash
dart run magic:dowel notifications:publish [--force]
```

| Flag | Type | Default | Description |
| :--- | :--- | :--- | :--- |
| `--force` | flag | `false` | Overwrite an existing `lib/config/notifications.dart` |

Without `--force`, an existing file is kept and the command exits `0` with a warning. The published file carries `YOUR_ONESIGNAL_APP_ID` as the App ID. After publishing:

1. Replace `YOUR_ONESIGNAL_APP_ID` with your App ID, or read it with `env('ONESIGNAL_APP_ID')`.
2. Run `dart run magic:dowel notifications:install` to inject the provider and set up the platforms.

> [!TIP]
> Use `publish` when you want to edit the config before `install` runs; use `install` alone for the end-to-end setup.

<a name="gotchas"></a>
## Gotchas

| Mistake | Fix |
| :--- | :--- |
| Running `dart run magic_notifications install` | The package has no executable. Use `dart run magic:dowel notifications:install`, after `dart run magic:dowel plugin:install magic_notifications`. |
| Expecting `notifications:test` to deliver something | It only prints a preview and simulates the send. Test delivery with a real device and your backend. |
| `notifications:configure --app-id` on a config that reads the App ID with `env('...')` | `configure`, `channels` and `doctor` edit and read the file's text, and `configure` only rewrites a quoted literal. Change the `.env` value instead. |
| Omitting `--app-id` with `--non-interactive` | The command exits `1`; the flag is required there, and a value that is not a UUID also exits `1` before anything is written. |
| Re-running `install` to change the config | An existing config is kept with a warning. Pass `--force` to regenerate it, or use `configure` for single values. |
| Expecting `uninstall` to clean the platform folders | It touches only the config, `pubspec.yaml`, `app.dart` and `main.dart`. The platform files are listed for manual removal. |

<a name="related-documentation"></a>
## Related Documentation

- [Installation](../getting-started/installation.md): the install flow end to end.
- [Configuration](../getting-started/configuration.md): the keys these commands edit.
- [Shipping push in a release build](./shipping-push.md): what `doctor` warns about on iOS.
- [Channels](./channels.md): the channels the runtime registers.
- [Magic CLI](https://anilcancakir.com/magic/docs/packages/magic-cli): the dowel commands that ship with Magic.
