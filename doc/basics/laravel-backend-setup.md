# Laravel Backend Setup

The backend contract Magic Notifications reads from, and a worked Laravel implementation of it: the notifications API, preference matrix, OneSignal push, device reachability and socket delivery.

- [Overview](#overview)
- [Prerequisites](#prerequisites)
- [Database Setup](#database-setup)
- [Models](#models)
- [Notification Class](#notification-class)
- [API Controllers](#api-controllers)
- [API Routes](#api-routes)
- [OneSignal Push Integration](#onesignal-push)
- [Socket Delivery (Broadcast)](#broadcast)
- [Sending Notifications](#sending)
- [API Contract Reference](#api-contract)
- [Testing](#testing)
- [Gotchas](#gotchas)
- [Related Documentation](#related-documentation)

<a name="overview"></a>
## Overview

Magic Notifications works with any backend that serves the REST endpoints listed under [API Contract Reference](#api-contract). This guide builds that backend on **Laravel's built-in notification system**, which is the natural fit. The `magic-starter-laravel` package implements the contract except for two points: its `unread-count` answers `{"data": {"count": n}}` where the client reads a top-level `count` (so `Notify.unreadCount()` returns `0` against it), and its list endpoint reads the page size from `per_page` where the client sends `perPage` (so the list always uses its default of 15). A backend written to this page is not affected. Use this page when you hand-roll the backend or want to see what that package does.

> [!NOTE]
> This guide covers the Laravel side. For the Flutter client, see [Installation](../getting-started/installation.md) and [Configuration](../getting-started/configuration.md). Laravel's own `php artisan` commands appear below because they are Laravel's.

<a name="prerequisites"></a>
## Prerequisites

- A Laravel application with notifications available, and Sanctum (or another token guard) protecting the API routes. The samples use `auth:sanctum`.
- For push: a OneSignal app and its REST API key.
- For socket delivery: Laravel broadcasting with a Reverb-compatible driver.

<a name="database-setup"></a>
## Database Setup

### Notifications Table

Laravel provides a built-in command:

```bash
php artisan make:notifications-table
php artisan migrate
```

This creates the standard `notifications` table:

| Column | Type | Description |
| :--- | :--- | :--- |
| `id` | uuid | Primary key |
| `type` | string | Notification class name |
| `notifiable_type` | string | Model type (for example `App\Models\User`) |
| `notifiable_id` | bigint | Model id |
| `data` | json | Notification payload |
| `read_at` | timestamp | When marked as read (`null` means unread) |
| `created_at` | timestamp | Creation time |
| `updated_at` | timestamp | Last update time |

### Notification Settings Table

The preferences screen stores one override per person, notification type and channel. A missing row means "enabled".

```bash
php artisan make:migration create_notification_settings_table
```

```php
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('notification_settings', function (Blueprint $table) {
            $table->id();
            $table->foreignId('user_id')->constrained()->onDelete('cascade');
            $table->string('type');
            $table->string('channel');
            $table->boolean('is_enabled')->default(true);
            $table->timestamps();

            $table->unique(['user_id', 'type', 'channel']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('notification_settings');
    }
};
```

```bash
php artisan migrate
```

<a name="models"></a>
## Models

### User Model

The `User` model uses Laravel's `Notifiable` trait and answers whether a person allows a type on a channel:

```php
namespace App\Models;

use Illuminate\Database\Eloquent\Relations\HasMany;
use Illuminate\Foundation\Auth\User as Authenticatable;
use Illuminate\Notifications\Notifiable;

class User extends Authenticatable
{
    use Notifiable;

    public function notificationSettings(): HasMany
    {
        return $this->hasMany(NotificationSetting::class);
    }

    public function allows(string $type, string $channel): bool
    {
        $setting = $this->notificationSettings()
            ->where('type', $type)
            ->where('channel', $channel)
            ->first();

        return $setting?->is_enabled ?? true;
    }
}
```

### NotificationSetting Model

```bash
php artisan make:model NotificationSetting
```

```php
namespace App\Models;

use Illuminate\Database\Eloquent\Model;

class NotificationSetting extends Model
{
    protected $fillable = [
        'user_id',
        'type',
        'channel',
        'is_enabled',
    ];

    protected $casts = [
        'is_enabled' => 'boolean',
    ];
}
```

<a name="notification-class"></a>
## Notification Class

```bash
php artisan make:notification MonitorDownNotification
```

```php
namespace App\Notifications;

use App\Models\Monitor;
use Illuminate\Bus\Queueable;
use Illuminate\Notifications\Notification;

class MonitorDownNotification extends Notification
{
    use Queueable;

    public function __construct(
        public Monitor $monitor
    ) {}

    public function via(object $notifiable): array
    {
        return $notifiable->allows('monitor_down', 'database') ? ['database'] : [];
    }

    public function toArray(object $notifiable): array
    {
        return [
            'title' => 'Monitor Down',
            'body' => "Your monitor '{$this->monitor->name}' is not responding.",
            'action_url' => "/monitors/{$this->monitor->id}",
            'monitor_id' => $this->monitor->id,
        ];
    }

    public function databaseType(object $notifiable): string
    {
        return 'monitor_down';
    }
}
```

The client reads `data.title` and `data.body` as required strings and `data.action_url` as optional, so `toArray()` has to carry the first two on every notification. A row without them cannot be decoded, and the fetch that returns it fails.

<a name="api-controllers"></a>
## API Controllers

### NotificationController

```bash
php artisan make:controller Api/V1/NotificationController
```

```php
namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Controller;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

class NotificationController extends Controller
{
    public function index(Request $request): JsonResponse
    {
        // The client sends `page` and `perPage`.
        $notifications = $request->user()
            ->notifications()
            ->paginate($request->integer('perPage', 15));

        return response()->json([
            'data' => $notifications->map(fn ($n) => [
                'id' => $n->id,
                'type' => $n->type,
                'data' => $n->data,
                'read_at' => $n->read_at?->toIso8601String(),
                'created_at' => $n->created_at->toIso8601String(),
            ]),
            'meta' => [
                'current_page' => $notifications->currentPage(),
                'last_page' => $notifications->lastPage(),
                'per_page' => $notifications->perPage(),
                'total' => $notifications->total(),
            ],
        ]);
    }

    public function unreadCount(Request $request): JsonResponse
    {
        // `count` sits at the top level: the client reads it from there.
        return response()->json([
            'count' => $request->user()->unreadNotifications()->count(),
        ]);
    }

    public function markAsRead(Request $request, string $id): JsonResponse
    {
        $request->user()->notifications()->findOrFail($id)->markAsRead();

        return response()->json(['message' => 'Notification marked as read']);
    }

    public function markAllAsRead(Request $request): JsonResponse
    {
        $request->user()->unreadNotifications->markAsRead();

        return response()->json(['message' => 'All notifications marked as read']);
    }

    public function destroy(Request $request, string $id): JsonResponse
    {
        $request->user()->notifications()->findOrFail($id)->delete();

        return response()->json(['message' => 'Notification deleted']);
    }
}
```

### NotificationPreferenceController

The preferences screen reads a type by channel matrix and writes one cell or a batch. The set of types and channels is yours; this sketch keeps it in a config file:

```php
// config/notification-types.php
return [
    'monitor_down' => [
        'label' => 'Monitor down',
        'channels' => [
            'database' => ['locked' => true],
            'push' => ['locked' => false],
        ],
    ],
];
```

```bash
php artisan make:controller Api/V1/NotificationPreferenceController
```

```php
namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Controller;
use App\Models\NotificationSetting;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Validation\ValidationException;

class NotificationPreferenceController extends Controller
{
    public function show(Request $request): JsonResponse
    {
        return $this->matrix($request);
    }

    public function update(Request $request): JsonResponse
    {
        $items = $request->has('preferences')
            ? $request->input('preferences')
            : [$request->only(['type', 'channel', 'is_enabled'])];

        validator(['items' => $items], [
            'items.*.type' => 'required|string',
            'items.*.channel' => 'required|string',
            'items.*.is_enabled' => 'required|boolean',
        ])->validate();

        // One transaction, so a batch cannot half-succeed.
        DB::transaction(function () use ($request, $items) {
            foreach ($items as $item) {
                $channel = config("notification-types.{$item['type']}.channels.{$item['channel']}");

                if ($channel === null || ($channel['locked'] ?? false)) {
                    throw ValidationException::withMessages(['channel' => 'This preference cannot be changed.']);
                }

                NotificationSetting::updateOrCreate(
                    [
                        'user_id' => $request->user()->id,
                        'type' => $item['type'],
                        'channel' => $item['channel'],
                    ],
                    ['is_enabled' => (bool) $item['is_enabled']],
                );
            }
        });

        return $this->matrix($request);
    }

    private function matrix(Request $request): JsonResponse
    {
        $settings = $request->user()->notificationSettings()->get()
            ->keyBy(fn ($setting) => "{$setting->type}.{$setting->channel}");

        $matrix = collect(config('notification-types'))->map(fn (array $type, string $key) => [
            'label' => $type['label'],
            'channels' => collect($type['channels'])->map(fn (array $channel, string $name) => [
                'enabled' => $settings->get("{$key}.{$name}")?->is_enabled ?? true,
                'locked' => $channel['locked'] ?? false,
            ]),
        ]);

        return response()->json([
            'data' => $matrix,
            'meta' => ['push_provisioned' => filled(config('onesignal.app_id'))],
        ]);
    }
}
```

<a name="api-routes"></a>
## API Routes

In `routes/api/v1.php`:

```php
use App\Http\Controllers\Api\V1\NotificationController;
use App\Http\Controllers\Api\V1\NotificationPreferenceController;
use Illuminate\Support\Facades\Route;

Route::middleware('auth:sanctum')->group(function () {
    Route::get('notifications', [NotificationController::class, 'index']);
    Route::get('notifications/unread-count', [NotificationController::class, 'unreadCount']);
    Route::post('notifications/{id}/read', [NotificationController::class, 'markAsRead']);
    Route::post('notifications/read-all', [NotificationController::class, 'markAllAsRead']);
    Route::delete('notifications/{id}', [NotificationController::class, 'destroy']);

    Route::get('notification-preferences', [NotificationPreferenceController::class, 'show']);
    Route::put('notification-preferences', [NotificationPreferenceController::class, 'update']);
});
```

<a name="onesignal-push"></a>
## OneSignal Push Integration

For push through OneSignal, install the Laravel notification channel:

```bash
composer require laravel-notification-channels/onesignal
composer require berkayk/onesignal-laravel
```

```bash
php artisan vendor:publish --provider="Berkayk\OneSignal\OneSignalServiceProvider"
```

Add to `.env`:

```env
ONESIGNAL_APP_ID=your-onesignal-app-id
ONESIGNAL_REST_API_KEY=your-onesignal-rest-api-key
```

> [!NOTE]
> Get the REST API Key from the OneSignal Dashboard, Settings, Keys & IDs. Use the "REST API Key" (it starts with `os_v2_app_...`), not the "User Auth Key".

### Update the Notification Class

Add the OneSignal channel to your notification:

```php
use NotificationChannels\OneSignal\OneSignalChannel;
use NotificationChannels\OneSignal\OneSignalMessage;

public function via(object $notifiable): array
{
    $channels = [];

    if ($notifiable->allows('monitor_down', 'database')) {
        $channels[] = 'database';
    }

    if ($notifiable->allows('monitor_down', 'push')) {
        $channels[] = OneSignalChannel::class;
    }

    return $channels;
}

public function toOneSignal(object $notifiable): OneSignalMessage
{
    return OneSignalMessage::create()
        ->setSubject('Monitor Down')
        ->setBody("Your monitor '{$this->monitor->name}' is not responding.")
        // The destination your app routes from. setData writes
        // additionalData, which is what arrives as `event.data` on a tap,
        // and `url` is the first key magic_deeplink's handler looks for.
        // Without this line a tapped push carries no destination at all.
        ->setData('url', "/monitors/{$this->monitor->id}")
        ->setData('monitor_id', $this->monitor->id)
        // Who the push is for. The client drops a push whose `subject` names
        // another identity than the one the device is subscribed as.
        ->setData('subject', 'user_' . $notifiable->id);
}
```

> [!IMPORTANT]
> **`setUrl` is not the mobile answer, and adding it alongside is not free.** It sets OneSignal's Launch URL, which the SDK acts on when the notification is clicked **on every platform**, not only on the web. Android resolves it (a verified App Link opens the app, anything else opens the browser), and on iOS the SDK calls `openURL`, so Safari opens first and bounces back through the Universal Link handshake. Send both without further action and an iOS user gets that browser flash on top of the route your click listener already performed.
>
> OneSignal's own guidance is the same: *"For mobile push, prefer Additional Data + a click listener. You get full control over navigation, no browser flash on iOS, and you can pass extra fields (like `order_id`) that aren't part of the URL."* ([Deep linking](https://documentation.onesignal.com/docs/en/deep-linking))
>
> So `setData` alone is the shape above. Add `setUrl(...)` when the same notification also serves web push, where the service worker needs a launch url, and then set `OneSignal_suppress_launch_urls` to `YES` in the iOS `Info.plist`: that stops the SDK calling `openURL` and makes your click listener responsible for every deep link, which it already is.
>
> `setData` takes a relative path here because it is routed in-app, and either form works: `OneSignalDeeplinkHandler` parses the value with `Uri.tryParse`, which does not require a scheme, and `RouteDeeplinkHandler` matches on `uri.path` alone, so `/monitors/123` and `https://app.example.com/monitors/123` both reach the same route. A Launch URL, if you send one, does have to be absolute.

### Route User to OneSignal

Add to your `User` model:

```php
/**
 * Route notifications for the OneSignal channel.
 *
 * IMPORTANT: the external id must match what the Flutter app declares when it
 * calls Notify.initializePush('user_${user.id}').
 */
public function routeNotificationForOneSignal(): array
{
    return ['include_external_user_ids' => ['user_' . $this->id]];
}
```

> [!TIP]
> Use a prefix such as `user_` rather than a bare numeric id: OneSignal blocks some external id values. Both sides must agree on the format. When you change the prefix, set `notifications.push_state.external_id_prefix` on the client to match.

### Device Reachability (Optional)

OneSignal accepts a push for a subscription that cannot be woken, so only the device knows whether a page will arrive. `Notify.pushState` reports that to your backend and withdraws it on sign-out. It stays off until the client names both endpoints (there is no default path):

```dart
// In `notificationConfig`, under the `notifications` key.
const Map<String, dynamic> notifications = {
  'push_state': {
    'report_path': '/devices/push-state',
    'release_path': '/devices/push-state/release',
  },
};
```

Both routes sit behind `auth:sanctum`. The user is always the session's; no body field names a person beyond the device's own alias.

**`POST {report_path}`** carries `PushDeliverySnapshot.toMap()` unchanged:

| Key | Rule |
| :--- | :--- |
| `external_id` | Present, nullable string; must equal the caller's own alias (`user_{id}`) when set |
| `subscription_id` | Present, nullable string |
| `reachability` | One of `on`, `off`, `blocked`, `unavailable` (the `PushReachability` names) |
| `captured_at` | ISO-8601 UTC, the device's own clock |

Store it per `(user, subscription_id)` with `updateOrCreate`, stamp your own `reported_at`, and answer `204`. A null key is a fact ("this device holds no subscription id"), so validate with `present`, not `sometimes`.

**`POST {release_path}`** carries `{"subscription_id": "..."}` only. Delete that one row for the session's user and answer `204`. The client calls it before `Auth.logout()` drops the token, and only for the device being signed out of: the person's other devices keep paging them.

The client reports on change (sign-in, permission, subscription swap), never on a timer, and re-posts only after a refusal. A refused release is logged and the sign-out proceeds, so size your freshness horizon for a stale row.

<a name="broadcast"></a>
## Socket Delivery (Broadcast)

The client can take notification state off a socket instead of polling for it (`Notify.startRealtime`, which subscribes through [magic_socket](https://anilcancakir.com/magic_socket/docs/basics/channels)). That needs three things on this side: the `broadcast` channel on the notification, a payload the client's decoder can read, and channel authorisation.

### 1. Add the channel and shape the frame

```php
use Illuminate\Notifications\Messages\BroadcastMessage;

class MonitorDownNotification extends Notification
{
    public function via(object $notifiable): array
    {
        // Alongside `database`, never instead of it: the socket is delivery, the
        // row is the record. A client that was offline reads the row over the API.
        return ['database', 'broadcast'];
    }

    /**
     * The wire event name.
     *
     * Laravel's default is the fully-qualified
     * `Illuminate\Notifications\Events\BroadcastNotificationCreated`. The
     * client matches a listener by EXACT string, so it would have to hardcode a
     * framework internal; this short name is the contract instead.
     */
    public function broadcastAs(): string
    {
        return 'notification.created';
    }

    /**
     * The payload, in the SAME shape `GET /notifications` returns a row.
     *
     * Laravel's default broadcast payload FLATTENS the notification data to the
     * top level and adds `id` and `type`, while `DatabaseNotification.fromMap`
     * on the client reads `data.title`, `data.body` and `data.action_url` from
     * a NESTED `data` key, so the default decodes to nothing useful. Building
     * the frame from `toArray()` keeps one serialiser behind both the API and
     * the socket, so the two cannot drift.
     */
    public function toBroadcast(object $notifiable): BroadcastMessage
    {
        return new BroadcastMessage([
            'id' => $this->id,
            'type' => static::class,
            'data' => $this->toArray($notifiable),
            'created_at' => now()->toIso8601String(),
            'read_at' => null,
        ]);
    }
}
```

### 2. Authorise the channel

The default channel for a `Notifiable` is its class name with dots plus its key, so `App\Models\User` id `42` publishes on `App.Models.User.42`. Authorise it in `routes/channels.php`, scoped to the one user:

```php
use App\Models\User;
use Illuminate\Support\Facades\Broadcast;

Broadcast::channel('App.Models.User.{userId}', function (User $user, string $userId): bool {
    // A notification is personal. Comparing as strings keeps a UUID key working.
    return (string) $user->id === (string) $userId;
}, ['guards' => ['sanctum']]);
```

The `guards` option matters for an API client: the channel-auth request arrives with a bearer token, not a session cookie, so the default `web` guard would deny every subscription.

Override `receivesBroadcastNotificationsOn()` on the notifiable if you want a different name; the client is told the channel by its caller, so any name works as long as both sides agree.

### 3. Point the client at it

```dart
import 'package:magic/magic.dart';
import 'package:magic_notifications/magic_notifications.dart';

Future<void> listenForUser(Model user) async {
  await Notify.startRealtime(channel: 'App.Models.User.${user.id}');
}
```

Nothing else changes. `Notify.startPolling()` stays wired to auth state and becomes a no-op while the socket is live, so a deployment with `BROADCAST_CONNECTION=null` keeps polling and needs no client change at all.

> **The row is still the record.** Keep `database` in `via()`. The socket delivers to whoever is connected; a client that was closed when the notification fired learns about it from the API on its next start, which is the fetch `startRealtime()` does once.

<a name="sending"></a>
## Sending Notifications

### From a Controller

```php
use App\Notifications\MonitorDownNotification;

public function checkMonitor(Monitor $monitor)
{
    if ($monitor->isDown()) {
        $monitor->user->notify(new MonitorDownNotification($monitor));
    }
}
```

### From a Job or Queue

```php
use Illuminate\Support\Facades\Notification;

// Single user
$user->notify(new MonitorDownNotification($monitor));

// Multiple users
Notification::send($users, new MonitorDownNotification($monitor));
```

<a name="api-contract"></a>
## API Contract Reference

The endpoints the Flutter plugin calls on your backend, all relative to the HTTP base URL and authenticated:

| Endpoint | Method | Description |
| :--- | :--- | :--- |
| `/notifications` | `GET` | List notifications, paginated; query `page` and `perPage` |
| `/notifications/unread-count` | `GET` | Unread count |
| `/notifications/{id}/read` | `POST` | Mark one notification as read |
| `/notifications/read-all` | `POST` | Mark all as read |
| `/notifications/{id}` | `DELETE` | Delete a notification |
| `/notification-preferences` | `GET` | The type by channel preference matrix |
| `/notification-preferences` | `PUT` | Change one cell or a batch |
| `/notifications/push-test` | `POST` | Optional: push a test notification to the caller's own devices (used by `PushChannel`) |
| `{push_state.report_path}` | `POST` | Optional: device reachability report |
| `{push_state.release_path}` | `POST` | Optional: release the device's report on sign-out |

### Response Formats

**GET /notifications**:

```json
{
  "data": [
    {
      "id": "550e8400-e29b-41d4-a716-446655440000",
      "type": "monitor_down",
      "data": {
        "title": "Monitor Alert",
        "body": "Your monitor 'API Server' is down",
        "action_url": "/monitors/1"
      },
      "read_at": null,
      "created_at": "2024-01-15T10:30:00Z"
    }
  ],
  "meta": {
    "current_page": 1,
    "last_page": 3,
    "per_page": 15,
    "total": 42
  }
}
```

**GET /notifications/unread-count**:

```json
{
  "count": 5
}
```

**GET /notification-preferences** and **PUT /notification-preferences** are specified under [Preferences](./preferences.md#api): a matrix of types, each with a `label` and per-channel `enabled` and `locked` flags, plus `meta.push_provisioned`.

**POST /notifications/push-test** takes `title` (string), `body` (string) and optional `data` (array), and no recipient: the backend derives the target from the session. Answer `501` while the surface is switched off (the client half is `notifications.push.self_test_enabled`; set both or neither), and `2xx` on success. The client treats any other status as a failure and throws.

<a name="testing"></a>
## Testing

### Test Database Notification

```php
use App\Models\Monitor;
use App\Models\User;
use App\Notifications\MonitorDownNotification;
use Illuminate\Support\Facades\Notification;

test('sends monitor down notification', function () {
    Notification::fake();

    $user = User::factory()->create();
    $monitor = Monitor::factory()->create(['user_id' => $user->id]);

    $user->notify(new MonitorDownNotification($monitor));

    Notification::assertSentTo($user, MonitorDownNotification::class);
});
```

### Test API Endpoints

```php
test('lists user notifications', function () {
    $user = User::factory()->create();
    $monitor = Monitor::factory()->create(['user_id' => $user->id]);
    $user->notify(new MonitorDownNotification($monitor));

    $response = $this->actingAs($user)
        ->getJson('/api/v1/notifications');

    $response->assertOk()
        ->assertJsonStructure([
            'data' => [['id', 'type', 'data', 'read_at', 'created_at']],
            'meta' => ['current_page', 'last_page', 'per_page', 'total'],
        ]);
});
```

<a name="gotchas"></a>
## Gotchas

| Mistake | Fix |
| :--- | :--- |
| Wrapping the unread count as `{"data": {"count": 5}}` | The client reads `count` from the top level and shows `0` otherwise. Return `{"count": 5}`. |
| Reading the page size from `per_page` | The client sends `perPage` (and `page`). Read `perPage`, or the list always uses your default. |
| Answering `GET /notification-preferences` with flat `push_enabled` toggles | The screen expects the type by channel matrix with `enabled` and `locked` per cell. The flat shape belongs to `NotificationPreference`, which the package never fetches. |
| A `toArray()` without `title` or `body` | `DatabaseNotification.fromMap` casts both to `String`, so such a row fails to decode and the fetch that returns it fails. |
| Using Laravel's default broadcast payload | It is flat and carries the event under a long class name. Add `broadcastAs()` and a `toBroadcast()` that nests `data`, as shown. |
| Sending the screen's destination with `setUrl` | That is OneSignal's Launch URL and never reaches `event.data`. Put the route in `setData('url', ...)`. |

<a name="related-documentation"></a>
## Related Documentation

- [Preferences](./preferences.md): the matrix and the models behind it.
- [Shipping push in a release build](./shipping-push.md): what to verify before a release, including `Notify.pushState`.
- [Notification Manager](../architecture/notification-manager.md): how the client uses these endpoints.
- [Installation](../getting-started/installation.md) and [Channels](./channels.md): the Flutter side.
- [Laravel Notifications](https://laravel.com/docs/notifications) and the [OneSignal Laravel channel](https://github.com/laravel-notification-channels/onesignal): the packages this page builds on.
- [magic_socket channels](https://anilcancakir.com/magic_socket/docs/basics/channels): the client-side socket layer.
