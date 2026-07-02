import Foundation
import Combine
import MacUpdaterCore

enum DownloadError: LocalizedError, Sendable {
    case elevationRequired
    case invalidVersion(String)

    var errorDescription: String? {
        switch self {
        case .elevationRequired:
            return "This download requires administrator privileges."
        case .invalidVersion(let v):
            return "Invalid version string: \(v)"
        }
    }
}

@MainActor
final class DownloadService: ObservableObject {
    @Published private(set) var tasks: [UUID: DownloadTask] = [:]

    private var activeProcesses: [UUID: Process] = [:]

    private struct ProgressSample {
        let progress: Double
        let timestamp: Date
    }
    private var progressHistory: [UUID: [ProgressSample]] = [:]
    private var taskOutput: [UUID: String] = [:]

    private let versionPattern = /^[0-9]+\.[0-9]+(\.[0-9]+)?$/

    var sortedTasks: [DownloadTask] {
        tasks.values.sorted { a, b in
            let aDate = a.startedAt ?? .distantPast
            let bDate = b.startedAt ?? .distantPast
            return aDate > bDate
        }
    }

    var activeCount: Int {
        tasks.values.filter { $0.state.isActive }.count
    }

    func startDownload(version: String, title: String) -> UUID {
        guard (try? versionPattern.wholeMatch(in: version)) != nil else {
            logError("Invalid version: \(version)", category: "DownloadService")
            return UUID()
        }
        let taskID = UUID()
        let task = DownloadTask(
            id: taskID,
            installerVersion: version,
            installerTitle: title,
            state: .queued,
            startedAt: Date()
        )
        tasks[taskID] = task
        logInfo("Queued download: \(title) \(version)", category: "DownloadService")

        Task {
            await self.executeDownload(id: taskID, version: version, title: title, elevated: false)
        }
        return taskID
    }

    func startElevatedDownload(id: UUID) {
        guard let task = tasks[id], case .failed = task.state else { return }
        updateState(id, .queued)
        let version = task.installerVersion
        let title = task.installerTitle
        logInfo("Retrying elevated: \(title) \(version)", category: "DownloadService")
        Task {
            await self.executeDownload(id: id, version: version, title: title, elevated: true)
        }
    }

    func cancel(id: UUID) {
        guard let process = activeProcesses[id] else {
            if tasks[id]?.state.isActive == true {
                updateState(id, .cancelled)
            }
            return
        }
        process.terminate()
        activeProcesses.removeValue(forKey: id)
        progressHistory.removeValue(forKey: id)
        updateState(id, .cancelled)
        logInfo("Cancelled download \(id)", category: "DownloadService")
    }

    func retry(id: UUID) {
        guard let task = tasks[id] else { return }
        if case .failed = task.state {
            tasks.removeValue(forKey: id)
            _ = startDownload(version: task.installerVersion, title: task.installerTitle)
        }
    }

    func clearCompleted() {
        let completedIDs = tasks.values
            .filter {
                if case .completed = $0.state { return true }
                if case .cancelled = $0.state { return true }
                return false
            }
            .map(\.id)
        completedIDs.forEach { tasks.removeValue(forKey: $0) }
    }

    private func executeDownload(id: UUID, version: String, title: String, elevated: Bool) async {
        updateState(id, .preparing)
        progressHistory[id] = []

        if elevated {
            await executeElevated(id: id, version: version, title: title)
            return
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/softwareupdate")
        process.arguments = ["--fetch-full-installer", "--full-installer-version", version]

        // Merge stdout + stderr into one pipe — softwareupdate writes progress to stderr
        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError  = outputPipe

        activeProcesses[id] = process
        taskOutput[id] = ""

        do {
            try process.run()
        } catch {
            activeProcesses.removeValue(forKey: id)
            taskOutput.removeValue(forKey: id)
            updateState(id, .failed(error: error.localizedDescription))
            logError("Process launch failed: \(error.localizedDescription)", category: "DownloadService")
            return
        }

        logInfo("Download process started (pid \(process.processIdentifier))", category: "DownloadService")

        let outputHandle = outputPipe.fileHandleForReading
        outputHandle.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            let text = String(data: data, encoding: .utf8) ?? ""
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.taskOutput[id] = (self.taskOutput[id] ?? "") + text
                self.processOutputText(id: id, text: text)
            }
        }

        let exitCode = await withCheckedContinuation { (cont: CheckedContinuation<Int32, Never>) in
            process.terminationHandler = { p in
                let code = p.terminationStatus
                Task { @MainActor in
                    cont.resume(returning: code)
                }
            }
        }

        outputHandle.readabilityHandler = nil
        activeProcesses.removeValue(forKey: id)
        progressHistory.removeValue(forKey: id)
        let collectedOutput = taskOutput.removeValue(forKey: id) ?? ""

        if exitCode == 0 {
            updateState(id, .verifying)
            logInfo("Download complete (exit 0), scanning /Applications", category: "DownloadService")
            let found = await InstalledInstallerService().scanForInstaller(version: version)
            let finalState: DownloadState = found ? .completed : .failed(error: "Installer not found in /Applications after download.")
            updateState(id, finalState)
            if case .completed = finalState {
                logInfo("Download verified: \(title) \(version)", category: "DownloadService")
            }
        } else {
            // Use last non-empty line from collected output as the error message
            let errMsg = collectedOutput
                .components(separatedBy: CharacterSet.newlines.union(CharacterSet(charactersIn: "\r")))
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
                .last ?? "Unknown error (exit \(exitCode))"

            logError("Download failed (exit \(exitCode)): \(errMsg)", category: "DownloadService")

            let isPermissionError = collectedOutput.lowercased().contains("requires") ||
                collectedOutput.lowercased().contains("permission") ||
                collectedOutput.lowercased().contains("authorization") ||
                exitCode == 1
            if isPermissionError {
                updateState(id, .failed(error: DownloadError.elevationRequired.localizedDescription ?? errMsg))
            } else {
                updateState(id, .failed(error: errMsg))
            }
        }
    }

    private func executeElevated(id: UUID, version: String, title: String) async {
        logInfo("Running elevated download for \(version)", category: "DownloadService")
        updateState(id, .downloading(progress: 0))

        let script = "do shell script \"/usr/sbin/softwareupdate --fetch-full-installer --full-installer-version \(version)\" with administrator privileges"
        let appleScript = NSAppleScript(source: script)

        let exitCode = await Task.detached {
            var errorDict: NSDictionary?
            appleScript?.executeAndReturnError(&errorDict)
            return errorDict == nil ? 0 : 1
        }.value

        if exitCode == 0 {
            updateState(id, .verifying)
            let found = await InstalledInstallerService().scanForInstaller(version: version)
            updateState(id, found ? .completed : .failed(error: "Installer not found after elevated download."))
        } else {
            updateState(id, .failed(error: "Elevated download failed or was cancelled."))
        }
    }

    private func processOutputText(id: UUID, text: String) {
        // softwareupdate uses both \n and \r (carriage return) for progress lines
        let separators = CharacterSet.newlines.union(CharacterSet(charactersIn: "\r"))
        for line in text.components(separatedBy: separators) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if let progress = parseProgress(from: trimmed) {
                updateProgress(id: id, progress: progress)
            } else if !trimmed.isEmpty {
                logDebug(trimmed, category: "softwareupdate")
            }
        }
    }

    private func parseProgress(from line: String) -> Double? {
        // Matches: "Installing: 12.50% complete" / "Downloading: 5%" / "12.5%"
        let pattern = /([0-9]+\.?[0-9]*)\s*%/
        guard let match = try? pattern.firstMatch(in: line),
              let value = Double(match.1) else { return nil }
        return min(value / 100.0, 1.0)
    }

    private func updateProgress(id: UUID, progress: Double) {
        let sample = ProgressSample(progress: progress, timestamp: Date())
        progressHistory[id, default: []].append(sample)
        if (progressHistory[id]?.count ?? 0) > 5 {
            progressHistory[id]?.removeFirst()
        }

        var speed: Double?
        var eta: Double?
        if let history = progressHistory[id], history.count >= 2,
           let first = history.first, let last = history.last {
            let timeDelta = last.timestamp.timeIntervalSince(first.timestamp)
            let progressDelta = last.progress - first.progress
            if timeDelta > 0, progressDelta > 0 {
                let rate = progressDelta / timeDelta
                let totalSize = 14.0 * 1_000_000_000.0
                speed = rate * totalSize
                eta = (1.0 - last.progress) / rate
            }
        }

        tasks[id]?.state = .downloading(progress: progress)
        tasks[id]?.bytesPerSecond = speed
        tasks[id]?.etaSeconds = eta
    }

    private func updateState(_ id: UUID, _ state: DownloadState) {
        tasks[id]?.state = state
        if case .completed = state { tasks[id]?.completedAt = Date() }
        if case .failed = state { tasks[id]?.completedAt = Date() }
        if case .cancelled = state { tasks[id]?.completedAt = Date() }
    }
}
