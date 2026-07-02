import Foundation

/// Tags installers as downgrades relative to `currentVersion` and reports which non-downgrade
/// versions aren't in `knownVersions` yet. Shared by the main app's UI refresh and the
/// background helper's check loop so the two never drift out of sync.
public func diffNewUpgrades(
    installers: [MacOSInstaller],
    currentVersion: VersionNumber,
    knownVersions: Set<String>
) -> (tagged: [MacOSInstaller], newlyAvailable: [MacOSInstaller]) {
    let tagged = installers.map { installer -> MacOSInstaller in
        var i = installer
        i.isDowngrade = i.versionNumber <= currentVersion
        return i
    }
    let upgrades = tagged.filter { !$0.isDowngrade }
    let newVersions = Set(upgrades.map(\.version)).subtracting(knownVersions)
    let newlyAvailable = upgrades.filter { newVersions.contains($0.version) }
    return (tagged, newlyAvailable)
}
