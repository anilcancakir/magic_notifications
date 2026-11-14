/// CLI barrel for Magic Notifications.
///
/// Re-exports the dowel infrastructure plus the notifications provider and
/// all seven notifications:* commands. `plugin:install` registers
/// [MagicNotificationsDowelProvider] under `.dowel/plugins.json`;
/// the commands surface automatically through the host [DowelApplication].
library;

// Hide the dowel-builtin DoctorCommand so the notifications-specific
// DoctorCommand (commands/doctor_command.dart) is the only one visible from
// this barrel.
export 'package:dowel/dowel.dart';

export 'commands/channels_command.dart';
export 'commands/configure_command.dart';
export 'commands/doctor_command.dart';
export 'commands/install_command.dart';
export 'commands/publish_command.dart';
export 'commands/test_command.dart';
export 'commands/uninstall_command.dart';
export 'notifications_dowel_provider.dart';
