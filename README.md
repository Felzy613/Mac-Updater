# Mac Updater

A native macOS application for discovering, downloading, and managing full macOS installers — without ever touching Terminal.

Mac Updater is a production-quality SwiftUI front-end for Apple's `softwareupdate --fetch-full-installer` mechanism. It filters available installers to show only upgrades newer than your current macOS version, tracks download progress in real time, and sends native notifications when downloads complete.

---

## Features

- **System detection** — displays your current macOS version, build number, and chip architecture
- **Installer discovery** — fetches the full list of available macOS installers from Apple
- **Upgrade filtering** — only shows installers newer than your current OS by default
- **Download management** — start, cancel, retry, and monitor download progress with speed and ETA
- **Privilege escalation** — prompts for your administrator password via a native GUI sheet when required
- **Installed installer browser** — scans `/Applications` and lists any macOS installer apps with version details and a one-click launch button
- **Log viewer** — structured log with levels, search, category filter, and plain-text export
- **Native notifications** — notifies you when downloads start, complete, or fail
- **Menu bar extra** — quick-access popover showing active download progress
- **Settings** — control auto-refresh, notification preferences, log retention, and advanced display options

---

## Requirements

| Requirement | Version |
|---|---|
| macOS | 13.0 Ventura or later |
| Architecture | Apple Silicon or Intel |
| Account | Administrator account (required for downloading installers) |

---

## Building

### Open in Xcode

```bash
git clone https://github.com/your-username/Mac-Updater.git
cd Mac-Updater
xed .
```

Xcode 15 or later will open the project automatically. Select the **MacUpdater** scheme and press **⌘R** to build and run.

> **Note:** The app runs unsandboxed so it can launch `/usr/sbin/softwareupdate` via `Process`. You do not need to change any signing settings for local development — Xcode will sign with your personal team automatically.

### Command line

```bash
xcodebuild -scheme MacUpdater -configuration Debug build
```

---

## CI / CD

Every push to `main` triggers the [Build and Release](.github/workflows/release.yml) workflow:

1. Version is bumped automatically using [Conventional Commits](https://www.conventionalcommits.org/)
2. App is archived and exported with Xcode
3. A `.pkg` installer is built and attached to a GitHub Release

### Conventional commit types

| Commit prefix | Version bump |
|---|---|
| `feat:` / `feature:` | minor |
| `fix:` / `chore:` / etc. | patch |
| `BREAKING CHANGE` or `type!:` | major |

### Required secrets

| Secret | Description |
|---|---|
| `MACOS_CERTIFICATE` | Base64-encoded Developer ID Application `.p12` certificate |
| `MACOS_CERTIFICATE_PWD` | Password for the `.p12` certificate |

Without these secrets the workflow still builds, but the resulting `.pkg` will be ad-hoc signed (not distributable outside your own machine).

---

## Architecture

Mac Updater follows MVVM with a clean service layer:

```
MacUpdater/
├── Models/          SystemInfo, MacOSInstaller, DownloadTask, AppLog
├── Services/        ShellService, SystemInfoService, InstallerDiscoveryService,
│                    DownloadService, InstalledInstallerService,
│                    NotificationService, LoggingService
├── ViewModels/      One per view, all @MainActor ObservableObject
└── Views/           SwiftUI views organised by feature
```

All services are Swift 6 `actor` types. `DownloadService` is a `@MainActor` class that owns `Process` instances directly, enabling safe cancellation and real-time progress binding.

---

## License

[MIT](LICENSE)
