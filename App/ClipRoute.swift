import Foundation

enum ClipRoute: Hashable {
    case detail(UUID)
    case organize(UUID)
    case compose, folders
    case settings(SettingsSection?)
}

enum SettingsSection: String, CaseIterable, Identifiable {
    case appearance = "Appearance"
    case clipboard = "Clipboard"
    case background = "Background monitoring"
    case notifications = "Notifications"
    case intelligence = "Apple Intelligence"
    case history = "History"
    case privacy = "Privacy"
    var id: String { rawValue }
}
