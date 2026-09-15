import SwiftUI

extension View {
    /// Surfaces an `InstallerAlert`, with a "Show in Finder" button when the problem is
    /// about a specific bundle the user may want to look at.
    func installerAlert(_ alert: Binding<InstallerAlert?>) -> some View {
        modifier(InstallerAlertModifier(alert: alert))
    }
}

private struct InstallerAlertModifier: ViewModifier {
    @Binding var alert: InstallerAlert?

    func body(content: Content) -> some View {
        content.alert(
            alert?.title ?? "",
            isPresented: Binding(
                get: { alert != nil },
                set: { if !$0 { alert = nil } }
            ),
            presenting: alert
        ) { current in
            if let url = current.revealURL {
                Button("Show in Finder") { InstallerLauncher.reveal(url) }
            }
            Button("OK", role: .cancel) {}
        } message: { current in
            Text(current.message)
        }
    }
}
