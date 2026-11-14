import 'package:flutter/widgets.dart' hide Notification;
import 'package:magic/magic.dart';
import 'package:magic_notifications/magic_notifications.dart';

const Color _ink = Color(0xFF111827);
const Color _accent = Color(0xFF4F46E5);
const TextStyle _text = TextStyle(color: _ink, fontSize: 16);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Magic.init(
    configs: [
      {
        'app': {
          'providers': [(app) => NotificationServiceProvider(app)],
        },
        'notifications': {
          'push': {
            // No `app_id`, so the driver is resolved but never initialised.
            // Push needs a OneSignal account and a device, see the README.
            'driver': 'onesignal',
          },
          'database': {'enabled': true, 'polling_interval': 30},
        },
      },
    ],
  );

  // A channel of the app's own, registered once boot has finished. It records
  // what it is handed, so a send has something visible to dispatch to.
  Notify.manager.registerChannel(ConsoleChannel());

  runApp(const ExampleApp());
}

/// A channel of this app's own: it keeps the titles it was handed.
class ConsoleChannel extends NotificationChannel {
  /// The titles delivered so far, newest last.
  static final List<String> delivered = <String>[];

  @override
  String get name => 'console';

  @override
  bool get isAvailable => true;

  @override
  Future<void> send(Notifiable notifiable, Notification notification) async {
    delivered.add('${notification.type} for ${notifiable.notifiableId}');
  }
}

/// Who the example sends to.
class ExampleUser with Notifiable {
  @override
  String get notifiableId => '1';
}

/// Names three channels: one this app registered, and two the package does.
class WelcomeNotification extends Notification {
  @override
  List<String> via(Notifiable notifiable) => ['console', 'database', 'push'];

  @override
  Map<String, dynamic>? toDatabase(Notifiable notifiable) => {
    'title': 'Welcome',
    'body': 'This row would be created by your backend.',
  };
}

/// Channel state on boot, plus one send and one realtime attempt.
class ExampleApp extends StatelessWidget {
  const ExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return WidgetsApp(
      title: 'magic_notifications example',
      color: _accent,
      textStyle: _text,
      pageRouteBuilder: <T>(RouteSettings settings, WidgetBuilder builder) {
        return PageRouteBuilder<T>(
          settings: settings,
          pageBuilder: (context, _, _) => builder(context),
        );
      },
      home: const StatusPage(),
    );
  }
}

class StatusPage extends StatefulWidget {
  const StatusPage({super.key});

  @override
  State<StatusPage> createState() => _StatusPageState();
}

class _StatusPageState extends State<StatusPage> {
  String _reachability = 'reading...';
  String _realtime = 'not tried';

  @override
  void initState() {
    super.initState();
    _readReachability();
  }

  Future<void> _readReachability() async {
    final PushDriver? driver = Notify.manager.pushDriverOrNull;
    final String answer = driver == null
        ? 'no push driver'
        : (await driver.reachability()).name;

    if (!mounted) return;
    setState(() => _reachability = answer);
  }

  Future<void> _send() async {
    // `push` is skipped silently: it is switched off until
    // `notifications.push.self_test_enabled` is true.
    await Notify.send(ExampleUser(), WelcomeNotification());

    if (!mounted) return;
    setState(() {});
  }

  Future<void> _tryRealtime() async {
    // False here: the app configures no broadcast driver.
    final bool live = await Notify.startRealtime(channel: 'App.Models.User.1');

    if (!mounted) return;
    setState(() => _realtime = live ? 'live' : 'refused, keep polling');
  }

  @override
  Widget build(BuildContext context) {
    final NotificationManager manager = Notify.manager;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('database channel: ${manager.hasChannel('database')}'),
            Text('push channel: ${manager.hasChannel('push')}'),
            Text('push reachability: $_reachability'),
            Text('realtime: $_realtime'),
            const SizedBox(height: 16),
            Row(
              children: [
                _Button(label: 'Send', onTap: _send),
                const SizedBox(width: 8),
                _Button(label: 'Try realtime', onTap: _tryRealtime),
              ],
            ),
            const SizedBox(height: 16),
            Text('console channel got: ${ConsoleChannel.delivered.length}'),
            for (final String line in ConsoleChannel.delivered) Text(line),
          ],
        ),
      ),
    );
  }
}

class _Button extends StatelessWidget {
  const _Button({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        color: _accent,
        child: Text(label, style: const TextStyle(color: Color(0xFFFFFFFF))),
      ),
    );
  }
}
