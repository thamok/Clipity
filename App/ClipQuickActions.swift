import UIKit

enum ClipQuickAction: String, CaseIterable {
    case addAI = "de.thamo.clipity.add-ai"
    case add = "de.thamo.clipity.add"
    case latest = "de.thamo.clipity.latest"
    case recent = "de.thamo.clipity.recent"

    @MainActor static func register() {
        // Four entries fit the Home Screen quick-action menu. Recent content is
        // shown only after opening Clipity, rather than exposing it on SpringBoard.
        UIApplication.shared.shortcutItems = [
            UIApplicationShortcutItem(
                type: addAI.rawValue, localizedTitle: "Add Clip with AI",
                localizedSubtitle: "Save clipboard and generate a title", icon: .init(systemImageName: "sparkles")),
            UIApplicationShortcutItem(
                type: add.rawValue, localizedTitle: "Add Clip", localizedSubtitle: "Save the current clipboard",
                icon: .init(systemImageName: "plus.square.on.square")),
            UIApplicationShortcutItem(
                type: latest.rawValue, localizedTitle: "Get Last Clip", localizedSubtitle: "Copy the newest clipping",
                icon: .init(systemImageName: "doc.on.doc")),
            UIApplicationShortcutItem(
                type: recent.rawValue, localizedTitle: "Show Last 3 Clips", localizedSubtitle: nil,
                icon: .init(systemImageName: "clock")),
        ]
    }

    @MainActor static func receive(_ shortcut: UIApplicationShortcutItem) -> Bool {
        guard let action = Self(rawValue: shortcut.type) else { return false }
        ClipNavigation.shared.quickAction = action
        return true
    }
}

final class ClipSceneDelegate: NSObject, UIWindowSceneDelegate {
    func scene(
        _ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions
    ) {
        if let shortcut = connectionOptions.shortcutItem { _ = ClipQuickAction.receive(shortcut) }
    }

    func windowScene(
        _ windowScene: UIWindowScene, performActionFor shortcutItem: UIApplicationShortcutItem,
        completionHandler: @escaping (Bool) -> Void
    ) {
        completionHandler(ClipQuickAction.receive(shortcutItem))
    }
}

extension LibraryModel {
    func handle(_ action: ClipQuickAction) async {
        let navigation = ClipNavigation.shared
        navigation.path = []
        var captured = false
        do {
            switch action {
            case .add, .addAI:
                let result = try await monitor.capture()
                guard let clip = result.clips.first else { throw ClipError.empty }
                captured = true
                navigation.selection = clip.isSaved ? "saved" : "history"
                await refresh()
                if action == .addAI {
                    notice = "Generating title…"
                    let title = try await ClipTitleGenerator.title(for: ClipStore.shared.hydrated(clip))
                    // Read current organization after generation, preserving edits
                    // another process may have committed while the model ran.
                    let current = try await ClipStore.shared.clipping(id: clip.id)
                    try await ClipStore.shared.update(
                        id: current.id, title: title, folderID: current.folderID, saved: current.isSaved)
                    await refresh()
                    notice = "Clipping saved with a title"
                } else {
                    notice = "Saved to history"
                }
            case .latest:
                guard let clip = try await ClipStore.shared.findClips(limit: 1).first else { throw ClipError.empty }
                ContentLoader.copy(try await ClipStore.shared.hydrated(clip))
                await refresh()
                navigation.path = [.detail(clip.id)]
                notice = "Copied"
            case .recent:
                await refresh()
                navigation.selection = "recent"
            }
        } catch {
            self.error =
                action == .addAI && captured
                ? "The clipping was saved, but its AI title could not be generated. \(error.localizedDescription)"
                : error.localizedDescription
        }
    }
}
