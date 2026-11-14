---
paths:
  - "lib/src/cli/**/*.dart"
---

# CLI Domain

Commands are built on `dowel` and surface via the host app's unified `dowel` binary (`dart run magic:dowel`).

## Command shape

- Commands extend `DowelCommand` — implement `signature` (DSL: `'name {arg} {--flag}'`), `description`, `boot` (return `CommandBoot.none`), `Future<int> handle(DowelContext ctx)`
- `signature` defines arguments and options; `ctx.argument('name')` and `ctx.option('flag')` retrieve values
- `handle()` returns exit code: `0` for success, `1` for error; use `ctx.output.error(msg)` for diagnostic messaging
- Install extends `DowelInstallCommand` — drives manifest-based install via `install.yaml` + transactional `PluginInstaller`; fluent override adds dynamic logic (UUID validation, conditional prompts, arbitrary file writes)

## Install infrastructure

- Manifest: `install.yaml` at package root (schema: `plugin_name`, `magic.provider`, `publish{stub:target}`, `native.*`, `post_install`)
- Transactional ops: `installer.writeFile(path, content)` (atomic, rolled back on error), then helper-backed mutations (`ConfigEditor`, `HtmlEditor`, `XmlEditor`, `MainDartEditor`) (synchronous, no rollback)
- Stub loading: `StubLoader.load('name', searchPaths)` — searches `assets/stubs/` directory; returns string content
- Code injection: `ConfigEditor.addImportToFile(path, import)`, `ConfigEditor.injectProvider(path, provider)` — idempotent (checks existing pattern before inserting)
- Idempotent re-install: guard helper ops with `HtmlEditor.hasContent(path, marker)` to avoid double-injection
- Testability: override `getProjectRoot()` and `getStubSearchPaths()` in test subclasses to use temp dirs

## MCP tools

`MagicNotificationsDowelProvider.mcpTools()` exposes two read-only diagnostic tools:
- `notifications_doctor` — health check (config presence, OneSignal App ID format, polling interval, platform setup)
- `notifications_channels` — list channel status and configuration

Mutating commands (install, configure, test, uninstall, publish) are excluded from the MCP surface.
