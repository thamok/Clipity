import UserNotifications

enum ClipityNotifications {
    static let category = "CLIPITY_CAPTURE_PENDING"
    static let saveAction = "CLIPITY_SAVE_CURRENT"
    static let pendingID = "ClipityClipboardPending"
    static let tokenKey = "captureToken"

    static func register() {
        let save = UNNotificationAction(
            identifier: saveAction, title: "Open & Save", options: [.foreground, .authenticationRequired])
        UNUserNotificationCenter.current().setNotificationCategories([
            UNNotificationCategory(identifier: category, actions: [save], intentIdentifiers: [], options: [])
        ])
    }

    static func requestPermission() async throws -> Bool {
        try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
    }

    static func pending(token: String?) async throws {
        let content = UNMutableNotificationContent()
        content.title = "Clipboard Changed"
        content.body = "Expand to save to Clipity, or tap to open and save."
        content.categoryIdentifier = category
        content.sound = .default
        if let token { content.userInfo[tokenKey] = token }
        try await UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: pendingID, content: content, trigger: nil))
    }

    static func saved(count: Int) async throws {
        guard count > 0 else { return }
        clearPending()
        let content = UNMutableNotificationContent()
        content.title = count == 1 ? "Clipping Saved" : "Clippings Saved"
        content.body = count == 1 ? "Added to your Clipity history." : "Added \(count) items to your Clipity history."
        // No clipping contents in notification previews or system caches.
        try await UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: "ClipityCaptureSaved", content: content, trigger: nil))
    }

    static func clearPending() {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [pendingID])
        center.removeDeliveredNotifications(withIdentifiers: [pendingID])
    }
}
