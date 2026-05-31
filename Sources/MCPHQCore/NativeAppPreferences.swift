import Foundation

public enum NativeAppPreferredExportFormat: String, CaseIterable, Codable, Sendable {
    case text
    case json
}

public enum NativeAppPreferences {
    public enum Key {
        public static let defaultHistoryLimit = "nativeApp.defaultHistoryLimit"
        public static let preferredExportFormat = "nativeApp.preferredExportFormat"
        public static let probeOnRefresh = "nativeApp.probeOnRefresh"
        public static let controlEndpointFilePath = "nativeApp.controlEndpointFilePath"
    }

    public static let dashboardWindowFrameAutosaveName = "nativeApp.dashboardWindowFrame"
    public static let defaultHistoryLimit = 10
    public static let minimumHistoryLimit = 1
    public static let maximumHistoryLimit = 100
    public static let defaultProbeOnRefresh = false
    public static let defaultPreferredExportFormat = NativeAppPreferredExportFormat.text

    public static var defaultControlEndpointFilePath: String {
        defaultControlEndpointFilePath()
    }

    public static func defaultControlEndpointFilePath(
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> String {
        LocalControlEndpointStore.defaultStore(homeDirectory: homeDirectory).fileURL.standardizedFileURL.path
    }

    public static func sanitizedHistoryLimit(_ value: Int) -> Int {
        min(max(value, minimumHistoryLimit), maximumHistoryLimit)
    }

    public static func sanitizedWindowFrameAutosaveName(_ rawName: String?) -> String {
        guard let rawName else { return dashboardWindowFrameAutosaveName }
        let trimmed = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? dashboardWindowFrameAutosaveName : trimmed
    }

    public static func preferredExportFormat(rawValue: String?) -> NativeAppPreferredExportFormat {
        guard let rawValue, let format = NativeAppPreferredExportFormat(rawValue: rawValue) else {
            return defaultPreferredExportFormat
        }
        return format
    }

    public static func sanitizedEndpointFilePath(
        _ rawPath: String,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> String {
        let trimmed = rawPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return defaultControlEndpointFilePath(homeDirectory: homeDirectory)
        }

        let expandedPath: String
        if trimmed == "~" {
            expandedPath = homeDirectory.path
        } else if trimmed.hasPrefix("~/") {
            expandedPath = homeDirectory.appendingPathComponent(String(trimmed.dropFirst(2))).path
        } else {
            expandedPath = trimmed
        }

        return URL(fileURLWithPath: expandedPath).standardizedFileURL.path
    }

    public static func endpointStore(for rawPath: String) -> LocalControlEndpointStore {
        LocalControlEndpointStore(fileURL: URL(fileURLWithPath: sanitizedEndpointFilePath(rawPath)))
    }
}
