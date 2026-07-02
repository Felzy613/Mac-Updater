# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build commands

```bash
# Open in Xcode (then ⌘R to run)
xed .

# Command-line debug build
xcodebuild -scheme MacUpdater -configuration Debug build

# Command-line release archive (used by CI)
xcodebuild archive \
  -project MacUpdater.xcodeproj \
  -scheme MacUpdater \
  -configuration Release \
  -destination "generic/platform=macOS" \
  -archivePath /tmp/app.xcarchive
```

There are no automated tests — correctness is verified manually by running the app.

## Architecture

Mac Updater is a native macOS SwiftUI app (macOS 13+, Swift 6) that wraps Apple's `softwareupdate` CLI. It follows **MVVM with a service layer**:

```
MacUpdaterApp      — app entry point; constructs all services and injects VMs via @EnvironmentObject
Models/            — plain value types: SystemInfo, MacOSInstaller, DownloadTask, AppLog, VersionNumber
Services/          — Swift 6 actors; one responsibility each (see below)
ViewModels/        — @MainActor ObservableObject classes; one per view section
Views/             — SwiftUI views organised by feature (Dashboard, Installers, Downloads, Installed, Logs, Settings, MenuBar)
```

### Service layer

All services are Swift 6 `actor` types except `DownloadService`, which is `@MainActor` so it can own `Process` instances and update `@Published` state directly during streaming output.

| Service | Responsibility |
|---|---|
| `ShellService` | Runs whitelisted shell commands via `Process`; the `AllowedCommand` enum enforces the command allowlist and validates version strings with a regex before spawning |
| `InstallerDiscoveryService` | Calls `ShellService` with `.listFullInstallers` and parses `softwareupdate` line output into `[MacOSInstaller]` |
| `DownloadService` | Manages `Process` instances for `softwareupdate --fetch-full-installer`; merges stdout+stderr into one pipe (progress is written to stderr); parses `%` progress lines; falls back to `NSAppleScript` for elevated privilege downloads |
| `InstalledInstallerService` | Scans `/Applications` for `Install macOS *.app` bundles and reads their `Info.plist` |
| `SystemInfoService` | Calls `sw_vers` and `uname` to populate `SystemInfo` |
| `NotificationService` | Wraps `UNUserNotificationCenter` |
| `LoggingService` | Singleton actor; persists entries as JSONL to `~/Library/Application Support/MacUpdater/logs/app.json`; capped at 2000 entries |

### Logging

All code uses four global free functions rather than direct `LoggingService` calls:

```swift
logDebug("message", category: "MyCategory")
logInfo("message",  category: "MyCategory")
logWarning("message", category: "MyCategory")
logError("message", category: "MyCategory")
```

### Version comparison

`VersionNumber` (in `Models/SystemInfo.swift`) implements `Comparable`. Installers are flagged `isDowngrade = true` when their `versionNumber <= currentVersion`, and `InstallerListViewModel` filters them out unless `showDowngrades` is enabled.

### Concurrency notes

- Services are `actor` types — call them with `await` from async contexts.
- `DownloadService` is `@MainActor` — its `@Published` properties update the UI directly; no explicit `DispatchQueue.main` switches needed.
- The `readabilityHandler` on `Pipe` fires on a background thread; all state mutations are dispatched back via `Task { @MainActor in ... }`.

## CI / CD

Every push to `main` triggers `.github/workflows/release.yml`:

1. `bump_version.py` reads the commit message and bumps `MARKETING_VERSION` in `project.pbxproj` using conventional commit rules (`feat:` → minor, anything else → patch, `BREAKING CHANGE`/`!` → major).
2. Xcode archives and exports the app.
3. `pkgbuild` creates a `.pkg` installer.
4. A version-bump commit tagged `vX.Y.Z` is pushed with `[skip ci]` to prevent re-triggering.
5. A GitHub Release is created with the `.pkg` attached.

Signing requires `MACOS_CERTIFICATE` (base64 `.p12`) and `MACOS_CERTIFICATE_PWD` secrets; without them the build succeeds but is ad-hoc signed.

## Key constraints

- **Unsandboxed** — the app has no App Sandbox entitlement so it can launch `/usr/sbin/softwareupdate` via `Process`. Keep it that way; sandboxing would break all shell execution.
- **No URLSession / network code** — all network activity goes through `softwareupdate`; the app never makes its own HTTP requests.
- **`AllowedCommand` is the security boundary** — all new shell operations must be added as named cases there, with version-string validation if a user-supplied version is passed to the command line.
