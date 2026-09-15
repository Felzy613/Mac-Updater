import Foundation
import Combine
import MacUpdaterCore

@MainActor
final class DownloadManagerViewModel: ObservableObject {
    @Published private(set) var tasks: [DownloadTask] = []
    /// Set only when a failure was genuinely about privileges, so the password sheet
    /// stops appearing for unrelated problems like a full disk.
    @Published var pendingElevationTaskID: UUID?
    @Published var alert: InstallerAlert?

    private let downloadService: DownloadService
    private let notificationService: NotificationService
    private var cancellables = Set<AnyCancellable>()
    private var notifiedCompleted: Set<UUID> = []
    private var notifiedFailed: Set<UUID> = []

    init(downloadService: DownloadService, notificationService: NotificationService) {
        self.downloadService = downloadService
        self.notificationService = notificationService

        downloadService.$tasks
            .map { $0.values.sorted { ($0.startedAt ?? .distantPast) > ($1.startedAt ?? .distantPast) } }
            .assign(to: &$tasks)

        downloadService.$tasks
            .sink { [weak self] dict in
                guard let self else { return }
                dict.values.forEach { self.handleStateChange(task: $0) }
            }
            .store(in: &cancellables)
    }

    var activeCount: Int { downloadService.activeCount }
    var hasFinishedTasks: Bool { downloadService.hasFinishedTasks }

    func startDownload(installer: MacOSInstaller) {
        downloadService.startDownload(installer: installer)
        notificationService.sendDownloadStarted(title: installer.title, version: installer.version)
        logInfo("Initiated download: \(installer.displayName)", category: "DownloadManager")
    }

    func cancel(taskID: UUID) { downloadService.cancel(id: taskID) }

    func retry(taskID: UUID) {
        notifiedFailed.remove(taskID)
        downloadService.retry(id: taskID)
    }

    func retryIgnoringSpaceCheck(taskID: UUID) {
        notifiedFailed.remove(taskID)
        downloadService.retryIgnoringSpaceCheck(id: taskID)
    }

    func confirmElevation(taskID: UUID) {
        pendingElevationTaskID = nil
        notifiedFailed.remove(taskID)
        downloadService.retryElevated(id: taskID)
    }

    func dismissElevation() { pendingElevationTaskID = nil }

    func clearFinished() { downloadService.clearFinished() }

    func openInstaller(taskID: UUID) {
        guard let url = tasks.first(where: { $0.id == taskID })?.installerURL else { return }
        Task {
            if let alert = await InstallerLauncher.launch(bundleURL: url) {
                self.alert = alert
            }
        }
    }

    func revealInstaller(taskID: UUID) {
        guard let url = tasks.first(where: { $0.id == taskID })?.installerURL else { return }
        InstallerLauncher.reveal(url)
    }

    private func handleStateChange(task: DownloadTask) {
        if case .completed = task.state, !notifiedCompleted.contains(task.id) {
            notifiedCompleted.insert(task.id)
            notificationService.sendDownloadCompleted(title: task.installerTitle, version: task.installerVersion)
        }

        guard case .failed(let failure) = task.state, !notifiedFailed.contains(task.id) else { return }
        notifiedFailed.insert(task.id)

        if failure.suggestsElevation {
            pendingElevationTaskID = task.id
            return
        }
        // The user already dismissed their own cancellation; don't notify about it.
        guard failure.reason != .userCancelled else { return }
        notificationService.sendDownloadFailed(
            title: task.installerTitle,
            version: task.installerVersion,
            error: failure.summary
        )
    }
}
