import Foundation
import MacUpdaterCore

/// Watches how many bytes have actually landed on disk while `softwareupdate` runs.
///
/// Used as a fallback for the elevated path (where the download is wrapped in
/// `do shell script`, which buffers all output until it finishes) and any time
/// `softwareupdate` stops printing percentages. It also drives stall detection, so a
/// download that quietly wedges says so instead of showing a frozen progress bar.
@MainActor
final class DownloadProgressMonitor {
    struct Reading: Sendable {
        let bytesObserved: Int64
        let progress: Double?
        let bytesPerSecond: Double?
        let isStalled: Bool
    }

    private static let interval: TimeInterval = 3
    private static let stallThreshold: TimeInterval = 300

    private let expectedBytes: Int64
    private var baseline: Baseline?
    private var timer: Timer?
    private var samples: [(bytes: Int64, at: Date)] = []
    private var lastGrowth = Date()

    private struct Baseline: Sendable {
        let freeCapacity: Int64
        let stagingSize: Int64
    }

    init(expectedBytes: Int64) {
        self.expectedBytes = expectedBytes
    }

    func start(onReading: @escaping @MainActor @Sendable (Reading) -> Void) {
        stop()
        lastGrowth = Date()
        Task { [weak self] in
            let snapshot = await Self.snapshot()
            self?.beginSampling(
                baseline: Baseline(freeCapacity: snapshot.free, stagingSize: snapshot.staging),
                onReading: onReading
            )
        }
    }

    private func beginSampling(
        baseline: Baseline,
        onReading: @escaping @MainActor @Sendable (Reading) -> Void
    ) {
        self.baseline = baseline
        timer = Timer.scheduledTimer(withTimeInterval: Self.interval, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                await self.tick(onReading: onReading)
            }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        samples.removeAll()
        baseline = nil
    }

    // MARK: - Private

    private func tick(onReading: @MainActor @Sendable (Reading) -> Void) async {
        guard let baseline else { return }
        let snapshot = await Self.snapshot()

        // Prefer the staging directory: it measures this download directly. Free space is
        // noisier (anything else on the Mac can move it) but always available.
        let staged = max(0, snapshot.staging - baseline.stagingSize)
        let consumed = max(0, baseline.freeCapacity - snapshot.free)
        let bytes = max(staged, consumed)

        let now = Date()
        if let previous = samples.last?.bytes, bytes > previous {
            lastGrowth = now
        } else if samples.isEmpty {
            lastGrowth = now
        }
        samples.append((bytes, now))
        if samples.count > 10 { samples.removeFirst() }

        var speed: Double?
        if let first = samples.first, let last = samples.last {
            let seconds = last.at.timeIntervalSince(first.at)
            let delta = Double(last.bytes - first.bytes)
            if seconds > 0, delta > 0 { speed = delta / seconds }
        }

        let progress = expectedBytes > 0 ? min(Double(bytes) / Double(expectedBytes), 0.99) : nil
        let stalled = bytes > 0 && now.timeIntervalSince(lastGrowth) > Self.stallThreshold

        onReading(Reading(bytesObserved: bytes, progress: progress, bytesPerSecond: speed, isStalled: stalled))
    }

    private static func snapshot() async -> (free: Int64, staging: Int64) {
        await Task.detached(priority: .utility) {
            (DiskSpace.current()?.freeCapacity ?? 0, StagingProbe.size())
        }.value
    }
}

/// `softwareupdate` stages the installer package here before expanding it into
/// /Applications, so the directory's size tracks the download in flight.
private enum StagingProbe {
    static let url = URL(fileURLWithPath: "/Library/Updates")

    static func size() -> Int64 {
        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: [.fileAllocatedSizeKey, .isRegularFileKey],
            options: []
        ) else { return 0 }

        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            guard let values = try? fileURL.resourceValues(forKeys: [.fileAllocatedSizeKey, .isRegularFileKey]),
                  values.isRegularFile == true,
                  let size = values.fileAllocatedSize else { continue }
            total += Int64(size)
        }
        return total
    }
}
