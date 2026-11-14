# magic_notifications example

A Magic app that boots `NotificationServiceProvider` and shows what notifications do without a backend or a OneSignal account: which channels the provider registered, what the push driver reports about this device, one `Notify.send` through a channel of the app's own, and one `Notify.startRealtime` call.

```bash
cd example
flutter create --platforms=web .
flutter run -d chrome
```

`flutter create` adds the platform folder once; it leaves `lib/` and `pubspec.yaml` as they are.

What you will see:

- `database channel: true` and `push channel: true`: the provider registered both. The database channel is always on; the push channel is registered because the config names the `onesignal` driver.
- `push reachability: unavailable`: the config carries no `app_id`, so the driver is never initialised and cannot reach this device.
- **Send** hands a notification to the channels its `via()` names. `console` is registered by `lib/main.dart` and records it. `database` accepts it and does nothing, since the backend creates inbox rows. `push` is skipped, because it stays off until `notifications.push.self_test_enabled` is `true`.
- **Try realtime** answers `refused, keep polling`: the app configures no broadcast driver, so `Notify.startRealtime` returns `false` and changes nothing.

What this example does not show, because it needs something outside the repository:

- The inbox itself (`Notify.notifications()`, `NotificationsListView`) reads `GET /notifications` from your Laravel backend, so there is nothing to list here.
- Push needs a OneSignal App ID in `notifications.push.app_id`, and a device or browser that can receive it. Keep the App ID out of source control with `env('ONESIGNAL_APP_ID')`.
- Realtime needs `magic_socket` registered and a `broadcasting.default` connection.
