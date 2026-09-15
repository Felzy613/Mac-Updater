import Foundation
import Combine
import MacUpdaterCore

@MainActor
final class DownloadService: ObservableObject {
    @Published private(set) var tasks: [UUID: DownloadTask] = [:]

    private var activeProcesses: [UUID: Process] = [:]
    private var terminals: [UUID: PseudoTerminal] = [:]
    private var pipeHandles: [UUID: FileHandle] = [:]
    private var readSources: [UUID: DispatchSourceRead] = [:]
    private var monitors: [UUID: DownloadProgressMonitor] = [:]
    private var collectedOutput: [UUID: String] = [:]
    /// Tasks where `softwareupdate` itself reported a percentage, so the disk-watching
    /// fallback should keep quiet.
    private var reportedOwnProgress: Set<UUID> = []
    private var cancelledIDs: Set<UUID> = []

    /// Only one installer downloads at a time — two `softwareupdate` processes writing
    /// into /Applications trip over each other, and each one needs tens of gigabytes.
    private var pendingIDs: [UUID] = []
    private var runningID: UUID?

    private static let readerQueue = DispatchQueue(label: "FelzyTech.MacUpdater.softwareupdate-output")

    var sortedTasks: [DownloadTask] {
        tasks.values.sorted { ($0.startedAt ?? .distantPast) > ($1.startedAt ?? .distantPast) }
    }

    var activeCount: Int {
        tasks.values.filter { $0.state.isActive }.count
    }

    var hasFinishedTasks: Bool {
        tasks.values.contains { $0.state.isFinished }
    }

    // MARK: - Starting downloads

    @discardableResult
    func startDownload(installer: MacOSInstaller) -> UUID {
        startDownload(
            version: installer.version,
            title: installer.title,
            expectedBytes: installer.sizeKiB * 1024
        )
    }

    @discardableResult
    func startDownload(version: String, title: String, expectedBytes: Int64) -> UUID {
        let taskID = UUID()
        var task = DownloadTask(
            id: taskID,
            installerVersion: version,
            installerTitle: title,
            expectedBytes: expectedBytes,
            state: .queued,
            startedAt: Date()
        )

        // Validate before anything else: a bad version must surface as a visible failed
        // task, not a silently discarded UUID.
        guard (try? AllowedCommand.makeFetchFullInstaller(version: version)) != nil else {
            task.state = .failed(DownloadFailure(
                reason: .launchFailed,
                summary: "“\(version)” isn't a macOS version number.",
                recovery: "Refresh the installer list and start the download from there."
            ))
            task.completedAt = Date()
            tasks[taskID] = task
            logError("Rejected invalid version: \(version)", category: "DownloadService")
            return taskID
        }

        tasks[taskID] = task
        logInfo("Queued download: \(title) \(version)", category: "DownloadService")
        enqueue(taskID)
        return taskID
    }

    /// Re-runs a failed download from scratch, keeping its place in the list.
    func retry(id: UUID) {
        guard let task = tasks[id], task.state.isFinished else { return }
        resetForRetry(id: id, elevated: false, overrideSpaceCheck: task.spaceCheckOverridden)
    }

    /// Runs the download through `osascript` so macOS prompts for an admin password.
    func retryElevated(id: UUID) {
        guard let task = tasks[id], task.state.isFinished else { return }
        logInfo("Retrying with elevation: \(task.displayName)", category: "DownloadService")
        resetForRetry(id: id, elevated: true, overrideSpaceCheck: task.spaceCheckOverridden)
    }

    /// Starts the download even though the pre-flight says the disk is too small —
    /// our estimate is a rule of thumb, and the user may know better.
    func retryIgnoringSpaceCheck(id: UUID) {
        guard tasks[id]?.state.isFinished == true else { return }
        logInfo("Retrying with space check overridden", category: "DownloadService")
        resetForRetry(id: id, elevated: false, overrideSpaceCheck: true)
    }

    func cancel(id: UUID) {
        guard tasks[id]?.state.isActive == true else { return }
        cancelledIDs.insert(id)
        pendingIDs.removeAll { $0 == id }

        if let process = activeProcesses[id], process.isRunning {
            process.terminate()
            tasks[id]?.state = .cancelled
        } else {
            // Queued but never started, so nothing will fire a completion for it.
            finish(id: id, state: .cancelled)
        }
        logInfo("Cancelled download \(tasks[id]?.displayName ?? id.uuidString)", category: "DownloadService")
    }

    func clearFinished() {
        let finished = tasks.values.filter { $0.state.isFinished }.map(\.id)
        finished.forEach { tasks.removeValue(forKey: $0) }
    }

    // MARK: - Queue

    private func resetForRetry(id: UUID, elevated: Bool, overrideSpaceCheck: Bool) {
        guard var task = tasks[id] else { return }
        task.state = .queued
        task.startedAt = Date()
        task.completedAt = nil
        task.bytesPerSecond = nil
        task.etaSeconds = nil
        task.installerURL = nil
        task.isStalled = false
        task.usedElevation = elevated
        task.spaceCheckOverridden = overrideSpaceCheck
        tasks[id] = task
        cancelledIDs.remove(id)
        reportedOwnProgress.remove(id)
        enqueue(id)
    }

    private func enqueue(_ id: UUID) {
        guard !pendingIDs.contains(id), runningID != id else { return }
        pendingIDs.append(id)
        pumpQueue()
    }

    private func pumpQueue() {
        guard runningID == nil else { return }
        while let next = pendingIDs.first {
            pendingIDs.removeFirst()
            guard let task = tasks[next], !cancelledIDs.contains(next) else { continue }
            runningID = next
            Task { await self.execute(id: next, elevated: task.usedElevation) }
            return
        }
    }

    // MARK: - Execution

    private func execute(id: UUID, elevated: Bool) async {
        guard let task = tasks[id] else {
            runningID = nil
            pumpQueue()
            return
        }

        updateState(id, .preparing)
        collectedOutput[id] = ""

        if !task.spaceCheckOverridden, let failure = preflightSpace(for: task) {
            logError("Pre-flight: \(failure.summary)", category: "DownloadService")
            finish(id: id, state: .failed(failure))
            return
        }

        if elevated {
            await runElevated(task: task)
        } else {
            await runDirect(task: task)
        }
    }

    /// Catches the common, entirely predictable failure before spending 20 minutes on it.
    private func preflightSpace(for task: DownloadTask) -> DownloadFailure? {
        guard task.expectedBytes > 0, let space = DiskSpace.current() else { return nil }
        let required = DiskSpace.requiredBytes(forInstallerSize: task.expectedBytes)
        guard space.availableCapacity < required else { return nil }

        let context = DownloadFailure.Context(
            version: task.installerVersion,
            expectedBytes: task.expectedBytes,
            space: space
        )
        return DownloadFailure(
            reason: .insufficientSpace,
            summary: "Not enough free disk space for macOS \(task.installerVersion).",
            recovery: DownloadFailure.spaceRecovery(context: context),
            rawOutput: "Checked before starting: \(DiskSpace.formatted(space.availableCapacity)) available, "
                + "about \(DiskSpace.formatted(required)) needed."
        )
    }

    private func runDirect(task: DownloadTask) async {
        let id = task.id
        guard let command = try? AllowedCommand.makeFetchFullInstaller(version: task.installerVersion) else {
            finish(id: id, state: .failed(DownloadFailure(
                reason: .launchFailed,
                summary: "“\(task.installerVersion)” isn't a macOS version number."
            )))
            return
        }

        let process = Process()
        process.executableURL = command.executableURL
        process.arguments = command.arguments
        process.standardInput = FileHandle.nullDevice

        // A pty, so softwareupdate believes it is in Terminal and prints progress;
        // a plain pipe gets us the text but no percentages.
        let terminal = PseudoTerminal()
        let fallbackPipe: Pipe? = terminal == nil ? Pipe() : nil
        if let terminal {
            process.standardOutput = terminal.replicaHandle
            process.standardError = terminal.replicaHandle
            terminals[id] = terminal
        } else if let fallbackPipe {
            process.standardOutput = fallbackPipe
            process.standardError = fallbackPipe
            logWarning("No pty available; progress reporting will be limited", category: "DownloadService")
        }

        activeProcesses[id] = process

        do {
            try process.run()
        } catch {
            cleanUpProcessResources(id: id)
            finish(id: id, state: .failed(DownloadFailure(
                reason: .launchFailed,
                summary: "Couldn't start softwareupdate.",
                recovery: error.localizedDescription
            )))
            logError("Process launch failed: \(error.localizedDescription)", category: "DownloadService")
            return
        }

        logInfo("softwareupdate started (pid \(process.processIdentifier)) for \(task.displayName)",
                category: "DownloadService")

        if let terminal {
            terminal.closeReplica()
            attachTerminalReader(id: id, fd: terminal.primaryFD)
        } else if let fallbackPipe {
            attachPipeReader(id: id, handle: fallbackPipe.fileHandleForReading)
        }

        startMonitor(for: task)

        let exitCode = await withCheckedContinuation { (continuation: CheckedContinuation<Int32, Never>) in
            let onExit: @Sendable (Process) -> Void = { finished in
                continuation.resume(returning: finished.terminationStatus)
            }
            process.terminationHandler = onExit
        }

        // Let the reader pick up anything written just before exit.
        try? await Task.sleep(for: .milliseconds(250))
        drainRemaining(id: id)
        cleanUpProcessResources(id: id)

        await completeRun(id: id, exitCode: exitCode)
    }

    private func runElevated(task: DownloadTask) async {
        let id = task.id
        guard let command = try? AllowedCommand.makeElevatedFetchFullInstaller(version: task.installerVersion) else {
            finish(id: id, state: .failed(DownloadFailure(
                reason: .launchFailed,
                summary: "“\(task.installerVersion)” isn't a macOS version number."
            )))
            return
        }

        let process = Process()
        process.executableURL = command.executableURL
        process.arguments = command.arguments
        process.standardInput = FileHandle.nullDevice

        // `do shell script` holds all output until the command finishes, so there is
        // nothing to stream — the disk monitor supplies progress instead.
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        activeProcesses[id] = process

        do {
            try process.run()
        } catch {
            cleanUpProcessResources(id: id)
            finish(id: id, state: .failed(DownloadFailure(
                reason: .launchFailed,
                summary: "Couldn't start the authorization prompt.",
                recovery: error.localizedDescription
            )))
            return
        }

        logInfo("Elevated softwareupdate started (pid \(process.processIdentifier))", category: "DownloadService")
        attachPipeReader(id: id, handle: pipe.fileHandleForReading)
        startMonitor(for: task)
        updateState(id, .downloading(progress: 0))

        let exitCode = await withCheckedContinuation { (continuation: CheckedContinuation<Int32, Never>) in
            let onExit: @Sendable (Process) -> Void = { finished in
                continuation.resume(returning: finished.terminationStatus)
            }
            process.terminationHandler = onExit
        }

        try? await Task.sleep(for: .milliseconds(250))
        drainRemaining(id: id)
        cleanUpProcessResources(id: id)

        let output = collectedOutput[id] ?? ""
        if exitCode != 0, output.lowercased().contains("user canceled") || output.contains("-128") {
            logInfo("Authorization cancelled by user", category: "DownloadService")
            finish(id: id, state: .failed(DownloadFailure(
                reason: .userCancelled,
                summary: "You cancelled the administrator prompt.",
                recovery: "Retry and enter your password to continue.",
                rawOutput: output
            )))
            return
        }

        await completeRun(id: id, exitCode: exitCode)
    }

    /// Shared tail of both paths: verify on success, explain on failure.
    private func completeRun(id: UUID, exitCode: Int32) async {
        guard let task = tasks[id] else {
            runningID = nil
            pumpQueue()
            return
        }
        guard !cancelledIDs.contains(id) else {
            finish(id: id, state: .cancelled)
            return
        }

        let output = collectedOutput[id] ?? ""

        guard exitCode == 0 else {
            let failure = DownloadFailure.classify(
                output: output,
                exitCode: exitCode,
                context: DownloadFailure.Context(
                    version: task.installerVersion,
                    expectedBytes: task.expectedBytes
                )
            )
            logError("Download failed (exit \(exitCode)): \(failure.summary)", category: "DownloadService")
            finish(id: id, state: .failed(failure))
            return
        }

        updateState(id, .verifying)
        logInfo("softwareupdate finished; locating the installer in /Applications", category: "DownloadService")

        let version = task.installerVersion
        let since = task.startedAt ?? Date()
        let found = await Task.detached(priority: .userInitiated) {
            InstallerBundleInspector.find(version: version, modifiedAfter: since)
        }.value

        guard let found else {
            finish(id: id, state: .failed(DownloadFailure(
                reason: .installerMissing,
                summary: "softwareupdate reported success, but no installer is in /Applications.",
                recovery: "Check /Applications for an “Install macOS” app. If one is there but incomplete, "
                    + "delete it and download again.",
                rawOutput: output
            )))
            logError("Verification failed: no installer found for \(version)", category: "DownloadService")
            return
        }

        guard found.isComplete else {
            finish(id: id, state: .failed(DownloadFailure(
                reason: .incompleteInstaller,
                summary: "The downloaded installer is incomplete.",
                recovery: found.issueDescription,
                rawOutput: output
            )))
            logError("Verification failed: \(found.displayName) is incomplete", category: "DownloadService")
            return
        }

        tasks[id]?.installerURL = found.bundleURL
        logInfo("Download verified: \(found.displayName) (macOS \(found.macOSVersion)) at \(found.bundleURL.path)",
                category: "DownloadService")
        finish(id: id, state: .completed)
    }

    // MARK: - Output handling

    /// Dispatch and Foundation call these handlers on background threads, so they are
    /// typed `@Sendable` to keep them out of the main actor and hop back explicitly.
    private func attachTerminalReader(id: UUID, fd: Int32) {
        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: Self.readerQueue)
        let handler: @Sendable () -> Void = { [weak self] in
            guard let data = PseudoTerminal.drain(fd: fd) else {
                // nil means EOF: on a pty that arrives as EIO once the child is gone.
                source.cancel()
                return
            }
            guard !data.isEmpty else { return }
            let text = String(decoding: data, as: UTF8.self)
            Task { @MainActor in
                self?.appendOutput(id: id, text: text)
            }
        }
        source.setEventHandler(handler: handler)
        source.resume()
        readSources[id] = source
    }

    private func attachPipeReader(id: UUID, handle: FileHandle) {
        let handler: @Sendable (FileHandle) -> Void = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            let text = String(decoding: data, as: UTF8.self)
            Task { @MainActor in
                self?.appendOutput(id: id, text: text)
            }
        }
        handle.readabilityHandler = handler
        pipeHandles[id] = handle
    }

    /// The classification of an elevated failure lives in the last few lines osascript
    /// writes as it exits, so read to the end rather than trusting the last callback.
    private func drainRemaining(id: UUID) {
        if let terminal = terminals[id], let data = PseudoTerminal.drain(fd: terminal.primaryFD), !data.isEmpty {
            appendOutput(id: id, text: String(decoding: data, as: UTF8.self))
        }
        if let handle = pipeHandles[id] {
            handle.readabilityHandler = nil
            let rest = handle.availableData
            if !rest.isEmpty {
                appendOutput(id: id, text: String(decoding: rest, as: UTF8.self))
            }
        }
    }

    private func appendOutput(id: UUID, text: String) {
        // Only while a run is in flight — a late callback must not resurrect the buffer
        // for a task that has already finished.
        guard let existing = collectedOutput[id] else { return }
        collectedOutput[id] = existing + text

        for line in Self.splitLines(text) {
            if let reading = Self.parseProgress(from: line) {
                reportedOwnProgress.insert(id)
                tasks[id]?.isStalled = false
                applyReportedProgress(id: id, reading: reading)
            } else if !line.isEmpty {
                logDebug(line, category: "softwareupdate")
                if line.lowercased().contains("downloading"), tasks[id]?.state.progress == nil {
                    updateState(id, .downloading(progress: 0))
                }
            }
        }
    }

    /// softwareupdate animates its progress line with carriage returns, backspaces and
    /// (now that it thinks it is in a terminal) ANSI escapes. Strip the animation and
    /// keep the text.
    static func splitLines(_ text: String) -> [String] {
        let escapes = /\u{1B}\[[0-9;?]*[ -\/]*[@-~]/
        let separators = CharacterSet.newlines.union(CharacterSet(charactersIn: "\r"))
        return text
            .replacing(escapes, with: "")
            .components(separatedBy: separators)
            .map { line in
                String(line.unicodeScalars.filter { $0 == "\t" || $0.value >= 32 })
                    .trimmingCharacters(in: .whitespaces)
            }
            .filter { !$0.isEmpty }
    }

    struct ProgressReading {
        let fraction: Double
        let isInstallPhase: Bool
    }

    /// Matches "Downloading: 12.5%", "Installing: 40%", or a bare "12.5%".
    static func parseProgress(from line: String) -> ProgressReading? {
        let pattern = /([0-9]+\.?[0-9]*)\s*%/
        guard let match = try? pattern.firstMatch(in: line), let value = Double(match.1) else { return nil }
        let lowered = line.lowercased()
        return ProgressReading(
            fraction: min(max(value / 100.0, 0), 1),
            isInstallPhase: lowered.contains("install") && !lowered.contains("installer:")
        )
    }

    private func applyReportedProgress(id: UUID, reading: ProgressReading) {
        guard var task = tasks[id] else { return }

        if reading.isInstallPhase {
            task.state = .installing(progress: reading.fraction)
            task.bytesPerSecond = nil
            task.etaSeconds = nil
        } else {
            task.state = .downloading(progress: reading.fraction)
            if task.expectedBytes > 0, let started = task.startedAt {
                let elapsed = Date().timeIntervalSince(started)
                let done = Double(task.expectedBytes) * reading.fraction
                if elapsed > 5, done > 0 {
                    let speed = done / elapsed
                    task.bytesPerSecond = speed
                    task.etaSeconds = (Double(task.expectedBytes) - done) / speed
                }
            }
        }
        tasks[id] = task
    }

    // MARK: - Disk-watching fallback

    private func startMonitor(for task: DownloadTask) {
        let id = task.id
        let monitor = DownloadProgressMonitor(expectedBytes: task.expectedBytes)
        monitors[id] = monitor
        monitor.start { [weak self] reading in
            self?.applyMonitorReading(id: id, reading: reading)
        }
    }

    private func applyMonitorReading(id: UUID, reading: DownloadProgressMonitor.Reading) {
        guard var task = tasks[id], task.state.isActive else { return }
        task.isStalled = reading.isStalled

        // softwareupdate's own numbers win whenever it is producing them.
        guard !reportedOwnProgress.contains(id) else {
            tasks[id] = task
            return
        }

        if let progress = reading.progress, progress > 0 {
            task.state = .downloading(progress: progress)
            task.bytesPerSecond = reading.bytesPerSecond
            if let speed = reading.bytesPerSecond, speed > 0, task.expectedBytes > 0 {
                task.etaSeconds = Double(task.expectedBytes - reading.bytesObserved) / speed
            }
        }
        tasks[id] = task
    }

    // MARK: - Bookkeeping

    private func cleanUpProcessResources(id: UUID) {
        if let source = readSources.removeValue(forKey: id) {
            source.cancel()
        }
        activeProcesses.removeValue(forKey: id)
        pipeHandles.removeValue(forKey: id)?.readabilityHandler = nil
        terminals.removeValue(forKey: id)
        monitors.removeValue(forKey: id)?.stop()
    }

    private func finish(id: UUID, state: DownloadState) {
        cleanUpProcessResources(id: id)
        collectedOutput.removeValue(forKey: id)
        reportedOwnProgress.remove(id)
        cancelledIDs.remove(id)
        updateState(id, state)

        tasks[id]?.bytesPerSecond = nil
        tasks[id]?.etaSeconds = nil
        tasks[id]?.isStalled = false

        if runningID == id { runningID = nil }
        pumpQueue()
    }

    private func updateState(_ id: UUID, _ state: DownloadState) {
        tasks[id]?.state = state
        if state.isFinished { tasks[id]?.completedAt = Date() }
    }
}
