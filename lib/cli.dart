/// CLI barrel for Magic Notifications.
///
/// Exposes ONLY the dowel-CLI surface ([MagicNotificationsDowelProvider]).
/// Does NOT export the Magic Notifications runtime (no Flutter, dart:ui, or
/// package:magic runtime imports), so this barrel is safe for consumption from
/// pure-Dart dowel dispatchers.
///
/// `plugin:install` registers the provider in the consumer's
/// `bin/dispatcher.dart`; wiring it by hand looks like:
///
/// ```dart
/// import 'package:dowel/dowel.dart';
/// import 'package:magic_notifications/cli.dart' show MagicNotificationsDowelProvider;
///
/// Future<void> main(List<String> args) async {
///   final registry = DowelRegistry()
///     ..registerProvider(MagicNotificationsDowelProvider());
///   exit(await DowelApplication(registry: registry).dispatch(args));
/// }
/// ```
///
/// Runtime consumers (lib/main.dart of a Magic-based app) continue to
/// import `package:magic_notifications/magic_notifications.dart` for facades
/// and the full notification surface.
library;

export 'src/cli/notifications_dowel_provider.dart';
