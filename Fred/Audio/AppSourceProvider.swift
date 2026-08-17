import AppKit
import Foundation

/// App em execução exibido na lista de captura.
struct RunningApp: Equatable, Identifiable {
    let bundleID: String?
    let name: String
    let icon: NSImage?
    let pid: pid_t

    var id: String { bundleID ?? "pid-\(pid)" }
}

protocol RunningAppsProviding {
    func runningApps() -> [RunningApp]
}

/// Implementação real via NSWorkspace.
final class WorkspaceRunningApps: RunningAppsProviding {
    func runningApps() -> [RunningApp] {
        NSWorkspace.shared.runningApplications.compactMap { app in
            guard app.activationPolicy == .regular else { return nil }
            let name = app.localizedName ?? app.bundleIdentifier ?? "App"
            return RunningApp(bundleID: app.bundleIdentifier, name: name, icon: app.icon, pid: app.processIdentifier)
        }
    }
}

/// Filtros puros — testáveis.
enum RunningAppsFilter {
    static func excludingSelf(_ apps: [RunningApp], selfBundleID: String?) -> [RunningApp] {
        apps.filter { $0.bundleID != selfBundleID }
    }

    static func sortedByName(_ apps: [RunningApp]) -> [RunningApp] {
        apps.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}
