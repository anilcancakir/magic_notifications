import 'package:dowel/dowel.dart';

import 'commands/channels_command.dart';
import 'commands/configure_command.dart';
// Aliased: dowel exports its own toolchain `DoctorCommand` from
// its barrel; this is the notification-specific health check.
import 'commands/doctor_command.dart' as notifications_doctor;
import 'commands/install_command.dart';
import 'commands/publish_command.dart';
import 'commands/test_command.dart';
import 'commands/uninstall_command.dart';

/// Version the seven `notifications:*` command banners print.
///
/// Mirrors the `version` field of this package's `pubspec.yaml`, which stays
/// the release's single source of truth. `install_command_test.dart` reads
/// both and fails when they disagree, so the seven banners cannot drift behind
/// a release the way seven hand-written literals did.
const String magicNotificationsVersion = '1.2.1';

/// DowelServiceProvider for Magic Notifications.
///
/// Contributes the seven `notifications:*` commands (install, configure, test,
/// doctor, uninstall, publish, channels) to the host application's
/// [DowelApplication]. `plugin:install` registers it under `.dowel/plugins.json`
/// alongside other plugin providers (e.g. [MagicDowelProvider],
/// [MagicStarterDowelProvider]).
///
/// MCP tools expose ONLY read-only diagnostics: `notifications_doctor` and
/// `notifications_channels`. Mutating commands (install, configure, test,
/// uninstall, publish) are intentionally excluded from the MCP surface.
class MagicNotificationsDowelProvider extends DowelServiceProvider {
  @override
  String get providerName => 'notifications';

  @override
  List<DowelCommand> commands() {
    return [
      InstallCommand(),
      ConfigureCommand(),
      TestCommand(),
      notifications_doctor.DoctorCommand(),
      UninstallCommand(),
      PublishCommand(),
      ChannelsCommand(),
    ];
  }

  @override
  List<McpToolDescriptor> mcpTools() => const <McpToolDescriptor>[
    McpToolDescriptor(
      name: 'notifications_doctor',
      description:
          'Check Magic Notifications installation and configuration health.\n\n'
          'Runs the notifications:doctor command against the project in the current '
          'working directory to diagnose plugin installation, config file presence, OneSignal App ID '
          'format, polling_interval range, and platform-specific setup.\n\n'
          'Usage:\n'
          '- Call with no arguments for a summary report.\n'
          '- Set verbose to true for per-check detail lines including file paths '
          'and required keys.',
      inputSchema: <String, dynamic>{
        'type': 'object',
        'properties': <String, dynamic>{
          'verbose': <String, dynamic>{
            'type': 'boolean',
            'description':
                'Show detailed diagnostic information. Default: false.',
          },
        },
      },
      extensionMethod: 'dowel:notifications:doctor',
    ),
    McpToolDescriptor(
      name: 'notifications_channels',
      description:
          'Show notification channels and their configuration status.\n\n'
          'Reads the project\'s lib/config/notifications.dart and reports the '
          'status of each channel (database, push, mail) including driver, '
          'app_id, polling_interval, and enabled state.\n\n'
          'Usage:\n'
          '- Call with no arguments to display the formatted channel table.',
      inputSchema: <String, dynamic>{
        'type': 'object',
        'properties': <String, dynamic>{},
      },
      extensionMethod: 'dowel:notifications:channels',
    ),
  ];
}
