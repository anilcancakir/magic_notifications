# Preferences

How a person's notification opt-ins are modelled, which backend endpoints the shipped preferences screen talks to, and the push prompt component that asks for permission.

- [Overview](#overview)
- [NotificationPreference Model](#model)
- [ChannelPreference Model](#channel-preference)
- [Global Toggles vs Per-Type Preferences](#global-vs-type)
- [API Endpoints](#api)
- [UI Integration](#ui)
- [Push Prompt Component](#push-prompt)
- [Translation Keys](#translation-keys)
- [Gotchas](#gotchas)
- [Related Documentation](#related-documentation)

<a name="overview"></a>
## Overview

Two things share the word "preferences" in this package, and they take different shapes:

| Piece | Shape | Used by |
| :--- | :--- | :--- |
| `NotificationPreference` model | Flat: global toggles plus per-type overrides | `PushChannel`, through `Notifiable.notificationPreference`. You load and attach it yourself. |
| Preferences screen (`NotificationPreferencesView`) | A type by channel matrix, read from and written to the backend | People changing their settings |

`NotificationPreference` represents opt-in and opt-out decisions across channels: global toggles (push, email, in-app) and per-type overrides (`typePreferences`). Its `isEnabled` method combines both layers to answer "should this notification be delivered through this channel?". The package fetches nothing into this model.

<a name="model"></a>
## NotificationPreference Model

```dart
import 'package:magic_notifications/magic_notifications.dart';

class NotificationPreference {
  final bool pushEnabled;
  final bool emailEnabled;
  final bool inAppEnabled;
  final Map<String, ChannelPreference> typePreferences;

  const NotificationPreference({
    this.pushEnabled = true,
    this.emailEnabled = true,
    this.inAppEnabled = true,
    this.typePreferences = const {},
  });
}
```

### Properties

| Property | Type | Default | Description |
| :--- | :--- | :--- | :--- |
| `pushEnabled` | `bool` | `true` | Global push toggle |
| `emailEnabled` | `bool` | `true` | Global email toggle, for a backend that honours it; the package has no mail channel |
| `inAppEnabled` | `bool` | `true` | Global in-app (database) toggle |
| `typePreferences` | `Map<String, ChannelPreference>` | `{}` | Per-notification-type channel overrides |

### Deserialisation

```dart
import 'package:magic_notifications/magic_notifications.dart';

NotificationPreference deserialise() {
  final pref = NotificationPreference.fromMap({
    'push_enabled': true,
    'email_enabled': false,
    'in_app_enabled': true,
    'type_preferences': {
      'monitor_down': {'push': true, 'email': true, 'in_app': true},
      'monitor_up': {'push': false, 'email': false, 'in_app': true},
    },
  });

  return pref;
}
```

A missing toggle reads as `true`.

### Serialisation

```dart
import 'package:magic_notifications/magic_notifications.dart';

Map<String, dynamic> serialise(NotificationPreference pref) {
  final map = pref.toMap();
  // {
  //   'push_enabled': true,
  //   'email_enabled': false,
  //   'in_app_enabled': true,
  //   'type_preferences': {...},
  // }

  return map;
}
```

### copyWith

```dart
import 'package:magic_notifications/magic_notifications.dart';

NotificationPreference enableEmail(NotificationPreference pref) {
  final updated = pref.copyWith(emailEnabled: true);

  return updated;
}
```

<a name="channel-preference"></a>
## ChannelPreference Model

```dart
class ChannelPreference {
  final bool push;
  final bool email;
  final bool inApp;

  const ChannelPreference({
    this.push = true,
    this.email = true,
    this.inApp = true,
  });
}
```

`ChannelPreference` holds the per-type override for each channel. It deserialises from one entry of the `type_preferences` map:

```dart
import 'package:magic_notifications/magic_notifications.dart';

ChannelPreference monitorDownPreference() {
  final monitorDown = ChannelPreference.fromMap({
    'push': true,
    'email': true,
    'in_app': false,
  });

  return monitorDown;
}
```

<a name="global-vs-type"></a>
## Global Toggles vs Per-Type Preferences

`isEnabled(notificationType, channel)` applies a two-stage gate:

```dart
import 'package:magic_notifications/magic_notifications.dart';

abstract class PreferenceGate {
  Map<String, ChannelPreference> get typePreferences;

  bool _isGlobalChannelEnabled(String channel);

  bool _isTypeChannelEnabled(ChannelPreference preference, String channel);

  bool isEnabled(String notificationType, String channel) {
    // Stage 1: global toggle
    final globalEnabled = _isGlobalChannelEnabled(channel);
    if (!globalEnabled) return false;

    // Stage 2: type-specific override
    final typePref = typePreferences[notificationType];
    if (typePref == null) return true; // default: enabled

    return _isTypeChannelEnabled(typePref, channel);
  }
}
```

**Channel alias resolution:**

| Argument | Maps to |
| :--- | :--- |
| `'push'` | `pushEnabled` / `ChannelPreference.push` |
| `'mail'` or `'email'` | `emailEnabled` / `ChannelPreference.email` |
| `'database'` or `'in_app'` | `inAppEnabled` / `ChannelPreference.inApp` |
| anything else | `false` |

**Example**: global push is `true` but `monitor_up.push` is `false`, so `isEnabled('monitor_up', 'push')` returns `false` and `PushChannel` skips delivery.

`PushChannel.send` runs this check when the `Notifiable` has a non-null `notificationPreference`:

```dart
import 'package:magic_notifications/magic_notifications.dart';

Future<void> send(Notifiable notifiable, Notification notification) async {
  final preference = notifiable.notificationPreference;
  if (preference != null) {
    if (!preference.isEnabled(notification.type, 'push')) return;
  }
}
```

<a name="api"></a>
## API Endpoints

The preferences screen needs two endpoints from the backend:

| Method | Path | Description |
| :--- | :--- | :--- |
| `GET` | `/notification-preferences` | The type by channel matrix for the signed-in user |
| `PUT` | `/notification-preferences` | Change one cell, or a batch of them |

`magic-starter-laravel` implements both. It differs from the contract only on the inbox: its `unread-count` shape and its `per_page` query key do not match what the client reads and sends, and a backend written to the contract is not affected. See [Laravel Backend Setup](./laravel-backend-setup.md#overview).

### GET /notification-preferences Response

A type by channel matrix. Each cell carries `enabled` and `locked`; a locked cell is one the backend refuses to change (a security mail, an account alert), and the screen renders its switch disabled rather than letting a tap earn a 422. The channel names are whatever your backend offers; the screen has labels for `mail`, `database`, `push` and `sms`, and capitalises any other.

```json
{
  "data": {
    "monitor_down": {
      "label": "Monitor down",
      "channels": {
        "mail": { "enabled": true, "locked": false },
        "database": { "enabled": true, "locked": true },
        "push": { "enabled": false, "locked": false }
      }
    }
  },
  "meta": { "push_provisioned": true }
}
```

`meta.push_provisioned` is the backend saying whether it has a push `app_id` at all. When it is `false` the push row still renders, with a hint under it, because the preference is a real choice even while nothing can deliver it yet. A response without the flag leaves the hint off.

### PUT /notification-preferences Request Body

One cell, which is what a switch in the matrix sends:

```json
{ "type": "monitor_down", "channel": "push", "is_enabled": false }
```

Or a batch, which is what the bulk row above the matrix sends:

```json
{
  "preferences": [
    { "type": "monitor_down", "channel": "push", "is_enabled": false },
    { "type": "monitor_up", "channel": "push", "is_enabled": false }
  ]
}
```

> [!IMPORTANT]
> The bulk row needs the batch shape. A backend that accepts only the single shape answers 422 and the control is dead, so a hand-rolled endpoint has to add it.
>
> The batch is one request on purpose. A loop of one request per type can half-succeed, and a half-succeeded bulk renders exactly like a complete one: the switch reads "off" while the one type that failed keeps delivering. Locked cells and cells already in the wanted state are left out of the batch.

<a name="ui"></a>
## UI Integration

The package ships `NotificationPreferencesView` and registers it under `notifications.preferences`. Mount it through the view registry, and replace or wrap it by registering your own builder under the same key:

```dart
import 'package:flutter/widgets.dart' hide Notification;
import 'package:magic_notifications/magic_notifications.dart';

// Once, at boot: wrap the default with a back route.
void registerPreferencesView() {
  Notify.view.register('notifications.preferences', () {
    return const NotificationPreferencesView(backRoute: '/settings');
  });
}

// In the page that hosts it:
class NotificationPreferencesPage extends StatelessWidget {
  const NotificationPreferencesPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Notify.view.make('notifications.preferences');
  }
}
```

`contentClassName` takes `''` when the screen sits inside a page container that already carries the app's padding. [Translation Keys](#translation-keys) lists every key the screen needs.

> [!TIP]
> To make `PushChannel` respect per-type preferences, attach a `NotificationPreference` you have loaded to your `User` model by overriding `Notifiable.notificationPreference`:
>
> ```dart
> import 'package:magic/magic.dart';
> import 'package:magic_notifications/magic_notifications.dart';
>
> class User extends Model with Notifiable {
>   @override
>   String get table => 'users';
>
>   @override
>   String get resource => 'users';
>
>   NotificationPreference? _cachedPreference;
>
>   @override
>   String get notifiableId => id.toString();
>
>   @override
>   dynamic get notificationPreference => _cachedPreference;
>
>   void setPreference(NotificationPreference pref) {
>     _cachedPreference = pref;
>   }
> }
> ```

<a name="push-prompt"></a>
## Push Prompt Component

`PushPrompt`, `PushPromptHost` and `PushOffNotice` (`lib/src/ui/components/push_prompt/`) are the package's own push-permission soft prompt: a row asking for push before the platform's one-shot prompt is spent, built on `NotificationManager.pushPromptAdvice()`.

- **`PushPrompt`** is presentational: given `reachability`, `action`, `declined` and `busy`, it renders the presentation for the device's state and reports `onEnable` and `onDecline`. It touches no platform API itself.
- **`PushPromptHost`** wires it to the live device. It owns nothing about when to ask (`pushPromptAdvice` does), but it owns the one thing the package refuses to decide: the key the decline is recorded under on this device. That is why it takes a `declinedVaultKey` constructor parameter rather than a fixed key:

  ```dart
  import 'package:flutter/widgets.dart';
  import 'package:magic_notifications/magic_notifications.dart';

  Widget pushPrompt() {
    return const PushPromptHost(declinedVaultKey: 'my_app.push_prompt_declined');
  }
  ```

  It writes the decline as an ISO-8601 UTC instant and reads only that shape; a value some other shape wrote reads as "never declined", so an app carrying an older value migrates it once before constructing this widget.

- **`PushOffNotice`** is a quiet shell marker (a sidebar row, or a compact glyph with `compact: true` for a mobile top bar) that tells a person, on a screen they were already looking at, that this device cannot be reached by push. Tapping it calls the required `onOpenPreferences` callback, which a host wires to wherever `PushPromptHost` and its controls live:

  ```dart
  import 'package:flutter/widgets.dart';
  import 'package:magic/magic.dart';
  import 'package:magic_notifications/magic_notifications.dart';

  Widget offNotice() {
    return PushOffNotice(
      onOpenPreferences: () => MagicRoute.to('/settings/notifications'),
    );
  }
  ```

`PushPrompt` and `PushOffNotice` resolve every string through `trans('notifications.push_prompt.*')`; [Translation Keys](#translation-keys) lists each one with its English reference copy.

The components expose no per-instance `className` override. A host that wants a different look copies the component's recipe file into its own source and registers its own builder.

<a name="translation-keys"></a>
## Translation Keys

The package ships no translation catalogue. Every string the inbox screen, the preferences screen, `NotificationDropdown`, `PushPrompt` and `PushOffNotice` show goes through Magic's `trans()`, so a host adds each key below to every locale it ships; a missing key renders as the key itself. The English column is reference copy for your own `en` file, not text the package carries. A `:name` in the copy is a placeholder the widget fills.

| Key | Where it shows | English reference copy |
| :--- | :--- | :--- |
| `notifications.title` | Inbox header title, dropdown panel heading, the dropdown bell's accessible name, and the title of the error shown when a delete fails | Notifications |
| `notifications.list_subtitle` | Inbox header subtitle | Everything we sent you |
| `notifications.mark_all_read` | Inbox header action and dropdown heading link, while something is unread | Mark all as read |
| `notifications.empty` | Inbox and dropdown with no rows | Nothing here yet |
| `notifications.load_failed` | The inbox when its read failed; the dropdown only when its `notificationStream` emits an error (with `Notify.notifications()` a failed `fetchNotifications()` is logged and the bell keeps its held list) | Could not load notifications |
| `notifications.delete` | Screen-reader label of an inbox row's delete control | Delete notification |
| `notifications.delete_failed` | The error `Magic.error` shows when an inbox delete fails | Could not delete the notification |
| `notifications.view_all` | Dropdown footer, only with `onViewAll` | View all |
| `notifications.badge_overflow` | Dropdown badge above nine unread rows | 9+ |
| `notifications.preferences_title` | Preferences header title | Notification preferences |
| `notifications.preferences_description` | Preferences header subtitle | Choose how we reach you |
| `notifications.no_preferences` | Preferences screen when the matrix is empty | Nothing to configure |
| `notifications.fetch_error` | `NotificationPreferencesController` error when `GET /notification-preferences` answers a failure status; the shipped screen shows `no_preferences` instead | Could not load your preferences |
| `notifications.bulk_title` | Heading of the bulk card above the matrix | Every notification type |
| `notifications.bulk_description` | Text of the bulk card | Turn a channel on or off at once |
| `notifications.channel_email` | Label of the `mail` row | Email |
| `notifications.channel_in_app` | Label of the `database` row | In app |
| `notifications.channel_push` | Label of the `push` row | Push |
| `notifications.channel_sms` | Label of the `sms` row | SMS |
| `notifications.channel_push_unconfigured` | Hint under the `push` row while `meta.push_provisioned` is `false` | Push is not set up yet |
| `notifications.push_prompt.unavailable_body` | `PushPrompt` on a build with no push | This build has no push notifications. |
| `notifications.push_prompt.on_body` | `PushPrompt` once push reaches the device | You're all set to receive push notifications. |
| `notifications.push_prompt.blocked_title` | `PushPrompt` title on a blocked device | Notifications are blocked |
| `notifications.push_prompt.blocked_body_settings` | `PushPrompt` on a blocked device that can open its settings | Turn notifications back on in your device settings. |
| `notifications.push_prompt.blocked_body_web` | `PushPrompt` on a blocked browser | Open the padlock icon in your browser's address bar to allow notifications. |
| `notifications.push_prompt.blocked_body_ios` | `PushPrompt` on a blocked iOS or macOS device without a settings route | Open Settings, then Notifications, to allow notifications for this app. |
| `notifications.push_prompt.blocked_body_android` | `PushPrompt` on any other blocked device without a settings route | Open this app's notification settings to allow notifications. |
| `notifications.push_prompt.declined_body` | `PushPrompt` after the reminder was turned down | You turned off this reminder. You can still enable push any time. |
| `notifications.push_prompt.ask_title` | `PushPrompt` title while asking | Turn on notifications |
| `notifications.push_prompt.ask_body` | `PushPrompt` text while asking | Get notified the moment something needs your attention. |
| `notifications.push_prompt.open_settings` | `PushPrompt` button when it opens the settings page | Open settings |
| `notifications.push_prompt.enable` | `PushPrompt` button when it raises the request | Enable |
| `notifications.push_prompt.not_now` | `PushPrompt` decline button | Not now |
| `notifications.push_prompt.shell_notice` | `PushOffNotice` label | Push is off |
| `notifications.push_prompt.shell_notice_a11y` | `PushOffNotice` screen-reader label | Push notifications are off |

The keys cover the package's own labels only. The dropdown and the inbox draw each notification's `title` and `body` exactly as the backend sent them, without `trans()`, so localising that content is the backend's or the host's job.

The same widgets also read these keys outside the `notifications.*` namespace. An app whose other screens already define them shares them; any other app adds them too.

| Key | Where it shows | English reference copy |
| :--- | :--- | :--- |
| `time.just_now` | Row time in the inbox and dropdown, under a minute old | Just now |
| `time.minutes_ago` | Row time under an hour old | :minutes min ago |
| `time.hours_ago` | Row time under a day old | :hours h ago |
| `time.days_ago` | Row time under a week old | :days d ago |
| `time.date_format` | Row time a week old or more | :day/:month/:year |
| `common.page_of` | Inbox pager | Page :current of :total |
| `common.back` | Preferences back control, only with `backRoute` | Back |
| `errors.unexpected` | `NotificationPreferencesController` error when the preferences read throws | Something went wrong |

<a name="gotchas"></a>
## Gotchas

| Mistake | Fix |
| :--- | :--- |
| Passing the `GET /notification-preferences` matrix to `NotificationPreference.fromMap` | They are different shapes. The matrix feeds the shipped screen; `NotificationPreference` is flat, and you build it from whatever endpoint of your own supplies it. |
| A backend that accepts only the single-cell `PUT` | The bulk row sends `{"preferences": [...]}` and gets a 422. Accept both shapes. |
| Shipping the screen or the prompt without translation keys | Missing keys render as the key text. Add every key in [Translation Keys](#translation-keys) to every locale. |
| Asking `isEnabled` about a channel name it does not know | It returns `false`. Use `push`, `mail` or `email`, `database` or `in_app`. |
| Reusing one `declinedVaultKey` for something else | `PushPromptHost` reads the key as an ISO-8601 timestamp and treats anything else as "never declined". Give it a key of its own. |

<a name="related-documentation"></a>
## Related Documentation

- [Channels](./channels.md): `PushChannel` and where `isEnabled` is consulted.
- [Notification Manager](../architecture/notification-manager.md): `pushPromptAdvice` and the optimistic read-state changes behind the inbox screen.
- [Configuration](../getting-started/configuration.md#permission): `reprompt_after_hours`, `soft_prompt.enabled` and the automatic request.
- [Laravel Backend Setup](./laravel-backend-setup.md): the backend contract for the preferences endpoints.
