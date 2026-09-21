import Darwin
import UIKit
import WidgetKit

/// Shared by the app, foreground Shortcut, and expanded notification.
@MainActor
enum ClipboardCapture {
    // The pasteboard's change counter resets on reboot. Scope receipts to this boot,
    // not to a process, so two extensions and the app agree on the same copy event.
    private static let bootID: String = {
        var boot = timeval()
        var size = MemoryLayout<timeval>.size
        guard sysctlbyname("kern.boottime", &boot, &size, nil, 0) == 0 else { return UUID().uuidString }
        return "\(boot.tv_sec).\(boot.tv_usec)"
    }()

    static var currentToken: String { "\(bootID):\(UIPasteboard.general.changeCount)" }

    static func save(
        expectedToken: String? = nil, title: String? = nil,
        folderID: UUID? = nil, keep: Bool = false, automatic: Bool = false
    ) async throws -> CaptureResult {
        let pasteboard = UIPasteboard.general
        let token = currentToken
        guard expectedToken == nil || expectedToken == token else { throw ClipError.clipboardChanged }
        guard !ClipPrivacy.isPrivate(types: pasteboard.types) else { throw ClipError.sensitive }
        var clips = try await ContentLoader.load(pasteboard.itemProviders)
        // Loading a remote provider can take time. Never associate newer contents
        // with an earlier event or silently save the wrong copy from an old alert.
        guard currentToken == token else { throw ClipError.clipboardChanged }
        for index in clips.indices {
            clips[index].title = title?.nilIfBlank
            clips[index].folderID = folderID
            clips[index].isSaved = keep || folderID != nil
        }
        let result = try await ClipStore.shared.captureBatch(clips, token: token, requireAutomaticCapture: automatic)
        LibraryEvents.post()
        WidgetCenter.shared.reloadAllTimelines()
        return result
    }
}

enum LibraryEvents {
    static let darwinName = "de.thamo.clipity.library.changed"
    static func post() {
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            CFNotificationName(darwinName as CFString), nil, nil, true)
    }
}
