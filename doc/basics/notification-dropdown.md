# Notification Dropdown

The `NotificationDropdown` bell: an unread badge over a notification stream, a popover panel listing the rows, its callbacks and how to restyle it.

- [Mounting the Bell](#mounting)
- [Constructor Parameters](#parameters)
- [What the Panel Shows](#panel)
- [Restyling](#restyling)
- [Type Icons](#type-icons)
- [Gotchas](#gotchas)
- [Related Documentation](#related-documentation)

<a name="mounting"></a>
## Mounting the Bell

```dart
import 'package:flutter/widgets.dart' hide Notification;
import 'package:magic/magic.dart';
import 'package:magic_notifications/magic_notifications.dart';

Widget notificationBell() {
  return NotificationDropdown(
    notificationStream: Notify.notifications(),
    onMarkAsRead: (String id) => Notify.markAsRead(id),
    onMarkAllAsRead: () => Notify.markAllAsRead(),
    onNotificationTap: (DatabaseNotification notification) {
      final String? path = notification.inAppActionPath;
      if (path != null) MagicRoute.to(path);
    },
    // `/notifications` is the host's own route to the inbox screen.
    onViewAll: () => MagicRoute.to('/notifications'),
  );
}
```

The widget holds no state of its own and calls no backend: it renders whatever `notificationStream` emits and hands every action to a callback. `Notify.notifications()` emits the manager's held list at once and every later change, so the bell fills once something reads the inbox (`Notify.fetchNotifications()`, `Notify.startPolling()` or `Notify.startRealtime(channel: ...)`; realtime answers `false` and reads nothing without a channel or a broadcast driver, so keep polling then), and `Notify.markAsRead` changes the held list before the request, so the badge drops on the tap.

<a name="parameters"></a>
## Constructor Parameters

| Parameter | Type | Default | Meaning |
| :--- | :--- | :--- | :--- |
| `notificationStream` | `Stream<List<DatabaseNotification>>` | required | The rows to list and count. The unread count is the rows whose `isRead` is `false`. |
| `onMarkAsRead` | `Future<void> Function(String id)?` | `null` | Awaited on every row tap, before `onNotificationTap`. |
| `onMarkAllAsRead` | `Future<void> Function()?` | `null` | The heading's mark-all link; without it the link is not drawn. |
| `onNotificationTap` | `void Function(DatabaseNotification)?` | `null` | Called after `onMarkAsRead`; the panel closes afterwards. |
| `onViewAll` | `VoidCallback?` | `null` | The footer link; without it the footer is not drawn. |
| `panelClassName` | `String` | `kNotificationDropdownPanelClassName` | The popover panel, width (`w-80`) included. |
| `triggerClassName` | `String` | `kNotificationDropdownTriggerClassName` | The box around the bell, its `hover:` and `active:` tones included. |
| `triggerIconClassName` | `String` | `kNotificationDropdownTriggerIconClassName` | The bell glyph; its size (`text-2xl`) lives here. |
| `triggerHitClassName` | `String?` | `null` | An invisible tap box around the trigger, for a trigger drawn smaller than a finger needs. |
| `panelOffset` | `Offset` | `Offset(0, 4)` | Where the panel sits relative to the trigger's bottom-right corner. |
| `badgeClassName` | `String` | `kNotificationDropdownBadgeClassName` | The unread pill. |
| `badgeTextClassName` | `String` | `kNotificationDropdownBadgeTextClassName` | The count inside the pill. |
| `semanticLabel` | `String?` | `null` | The bell's accessible name; `null` uses `notifications.title`, or `Notifications` when the catalogue lacks that key. A shell that names its controls itself passes its name here instead of wrapping the bell in a labelled `Semantics`, which would read the bell twice. |

<a name="panel"></a>
## What the Panel Shows

| Stream state | Bell | Panel |
| :--- | :--- | :--- |
| Waiting for its first list | No badge | A spinning Wind icon |
| An error | No badge | `notifications.load_failed` |
| An empty list | No badge | `notifications.empty` |
| Rows | The unread count, or `notifications.badge_overflow` above nine | `notifications.title`, the mark-all link while something is unread, one row per notification (title, body, relative time) and the view-all footer |

The bell is one button for assistive technology, named by `semanticLabel`, else `notifications.title` (`Notifications` when the key is missing, never the raw key), and read with the unread count after it; it reports itself expanded while the panel is open. The panel is capped at 400 logical pixels high and scrolls inside. Every string comes from a translation key the host supplies; [Translation Keys](./preferences.md#translation-keys) lists them with English reference copy.

<a name="restyling"></a>
## Restyling

The defaults are Wind's own palette (`bg-white`, `text-gray-500`, `bg-red-500`). Each className parameter replaces its default outright rather than appending to it, so an override restates the layout tokens and the `dark:` pair it still wants. The defaults are exported as `kNotificationDropdown*ClassName` constants to read from.

```dart
import 'package:flutter/widgets.dart' hide Notification;
import 'package:magic_notifications/magic_notifications.dart';

Widget compactBell() {
  return NotificationDropdown(
    notificationStream: Notify.notifications(),
    triggerClassName:
        'w-9 h-9 rounded-lg flex items-center justify-center '
        'bg-transparent hover:bg-gray-100 dark:hover:bg-gray-800',
    triggerIconClassName: 'text-[18px] text-gray-500 dark:text-gray-400',
    triggerHitClassName: 'w-11 h-11 flex items-center justify-center',
    panelOffset: const Offset(-4, 0),
  );
}
```

A 36 pixel trigger centred in a 44 pixel tap box: the panel anchors to the whole box, so `panelOffset` pulls it back by the box's inset to line it up with the drawn trigger. The badge count is clamped to a maximum text scale whatever `badgeClassName` says, so a taller pill scales less than it could but never clips.

<a name="type-icons"></a>
## Type Icons

Each row leads with the icon registered for its `type` in the `notifications.icon` slot family, then with the `default` slot, then with a neutral bell. The inbox screen reads the same slots.

```dart
import 'package:flutter/widgets.dart' hide Notification;
import 'package:magic/magic.dart';
import 'package:magic_notifications/magic_notifications.dart';
// The host adds material_ui to its own pubspec for `Icons`.
import 'package:material_ui/material_ui.dart' show Icons;

void registerTypeIcons() {
  Notify.view.slot(
    NotificationViewRegistry.typeIconSlotView,
    'monitor_down',
    (BuildContext context) {
      return WIcon(
        Icons.error_outline,
        className: 'text-lg text-red-500 dark:text-red-400',
      );
    },
  );
}
```

<a name="gotchas"></a>
## Gotchas

| Mistake | Fix |
| :--- | :--- |
| A bell that stays empty | The stream only carries what something read. Call `Notify.fetchNotifications()`, or start polling or realtime from the authenticated layout. `Notify.startRealtime()` needs a `channel:` and answers `false` without one, so check the result and keep polling. |
| Overriding `panelClassName` with a colour only | The override replaces the default, width and `dark:` pair included. Restate `w-80` and the dark tone. |
| Expecting a tap on a read row to skip `onMarkAsRead` | It runs on every tap. `Notify.markAsRead` on a read row posts the request again; guard it in the callback if that matters. |
| No mark-all link or footer | Both appear only when their callback is set, and the mark-all link only while something is unread. |
| Passing `notification.actionUrl` to `MagicRoute.to` | The backend owns the value, and it can be a URL, a `//host` or a `javascript:` string; the router takes paths and opens a route for whatever it is given. Use `inAppActionPath`, which is `null` unless the value is a path inside the app. |
| Raw keys such as `notifications.view_all` in the panel | Add every key in [Translation Keys](./preferences.md#translation-keys) to every locale. |

<a name="related-documentation"></a>
## Related Documentation

- [Preferences](./preferences.md): the preferences screen, `PushPrompt` and the translation keys.
- [Notification Manager](../architecture/notification-manager.md): the held list behind `Notify.notifications()` and the optimistic read-state changes.
- [Configuration](../getting-started/configuration.md): `polling_interval`, which sets how often a polling bell refreshes.
