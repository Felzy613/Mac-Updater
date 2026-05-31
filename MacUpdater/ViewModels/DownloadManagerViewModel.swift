import Foundation
import Combine

@MainActor
final class DownloadManagerViewModel: ObservableObject {
    @Published private(set) var tasks: [DownloadTask] = []
    @Published var pendingElevationTaskID: UUID?

    private let downloadService: DownloadService
    private let notificationService: NotificationService
    private var cancellables = Set<AnyCancellable>()

    init(downloadService: DownloadService, notificationService: NotificationService) {
        self.downloadService = downloadService
        self.notificationService = notificationService

        downloadService.$tasks
            .map { dict in dict.values.sorted { ($0.startedAt ?? .distantPast) > ($1.startedAt ?? .distantPast) } }
            .assign(to: &$tasks)

        downloadService.$tasks
            .sink { [weak self] dict in
                guard let self else { return }
                for task in dict.values {
                    self.handleStateChange(task: task)
                }
            }
            .store(in: &cancellables)
    }

    var activeCount: Int { downloadService.activeCount }

    func startDownload(installer: MacOSInstaller) {
        let id = downloadService.startDownload(version: installer.version, title: installer.title)
        notificationService.sendDownloadStarted(title: installer.title, version: installer.version)
        logInfo("Initiated download: \(installer.displayName)", category: "DownloadManager")
        _ = id
    }

    func cancel(taskID: UUID) {
        downloadService.cancel(id: taskID)
    }

    func retry(taskID: UUID) {
        downloadService.retry(id: taskID)
    }

    func confirmElevation(taskID: UUID) {
        pendingElevationTaskID = nil
        downloadService.startElevatedDownload(id: taskID)
    }

    func dismissElevation() {
        pendingElevationTaskID = nil
    }

    func clearCompleted() {
        downloadService.clearCompleted()
    }

    private var notifiedCompleted: Set<UUID> = []
    private var notifiedFailed: Set<UUID> = []

    private func handleStateChange(task: DownloadTask) {
        if case .completed = task.state, !notifiedCompleted.contains(task.id) {
            notifiedCompleted.insert(task.id)
            notificationService.sendDownloadCompleted(title: task.installerTitle, version: task.installerVersion)
        }
        if case .failed(let err) = task.state, !notifiedFailed.contains(task.id) {
            notifiedFailed.insert(task.id)
            if err == DownloadError.elevationRequired.localizedDescription {
                pendingElevationTaskID = task.id
            } else {
                notificationService.sendDownloadFailed(
                    title: task.installerTitle,
                    version: task.installerVersion,
                    error: err
                )
            }
        }
    }
}
