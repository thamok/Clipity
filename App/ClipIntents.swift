import AppIntents
import UIKit
import UniformTypeIdentifiers
import WidgetKit

struct SaveClipboardIntent: AppIntent {
    static let title: LocalizedStringResource = "Save Clipboard to Clipity"
    static let description = IntentDescription(
        "Open Clipity and save the current text, web link, or image. Checks private-copy markers before loading content. iOS paste permission may be required."
    )
    static var supportedModes: IntentModes { .foreground }
    static var authenticationPolicy: IntentAuthenticationPolicy { .requiresAuthentication }
    @Parameter(title: "Keep Permanently", default: false) var keep: Bool
    @Parameter(title: "Title") var title: String?
    @Parameter(title: "Folder") var folder: ClipFolderEntity?
    static var parameterSummary: some ParameterSummary {
        Summary("Save the clipboard to Clipity") {
            \.$keep
            \.$title
            \.$folder
        }
    }
    func perform() async throws -> some IntentResult {
        _ = try await PasteboardMonitor.shared.capture(title: title, folderID: folder?.id, keep: keep)
        return .result()
    }
}

struct GetLatestClippingFileIntent: AppIntent {
    static let title: LocalizedStringResource = "Get Latest Clipping File"
    static let description = IntentDescription(
        "Return the latest clipping as its original file or image, or as UTF-8 text.")
    static var supportedModes: IntentModes { .background }
    static var authenticationPolicy: IntentAuthenticationPolicy { .requiresAuthentication }
    func perform() async throws -> some IntentResult & ReturnsValue<IntentFile> {
        guard let clip = try await ClipStore.shared.snapshot().clips.max(by: { $0.date < $1.date }) else {
            throw ClipError.empty
        }
        let loaded = try await ClipStore.shared.hydrated(clip)
        let type = loaded.contentType
        return .result(
            value: IntentFile(
                data: loaded.payload,
                filename: loaded.filename ?? "Clipping.\(type.preferredFilenameExtension ?? "txt")", type: type))
    }
}

struct AddClippingIntent: AppIntent {
    static let title: LocalizedStringResource = "Add Clipping"
    static let description = IntentDescription(
        "Save text or a web link to Clipity. Pass the output of Get Clipboard to capture clipboard text. Private-looking content is rejected."
    )
    static var supportedModes: IntentModes { .background }
    static var authenticationPolicy: IntentAuthenticationPolicy { .requiresAuthentication }

    @Parameter(title: "Text") var text: String
    @Parameter(title: "Title") var title: String?
    @Parameter(title: "Keep Permanently", default: false) var keep: Bool
    @Parameter(title: "Folder") var folder: ClipFolderEntity?

    static var parameterSummary: some ParameterSummary {
        Summary("Add \(\.$text) to Clipity") {
            \.$title
            \.$keep
            \.$folder
        }
    }

    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let clip = try await ClipStore.shared.add(
            text: text, title: title, folderID: folder?.id, saved: keep || folder != nil)
        WidgetCenter.shared.reloadAllTimelines()
        return .result(value: clip.text)
    }
}

struct GetLatestClippingsIntent: AppIntent {
    static let title: LocalizedStringResource = "Get Latest Clippings"
    static let description = IntentDescription(
        "Return the newest text and link clippings, optionally from a folder. Image-only clippings are excluded from this text action."
    )
    static var supportedModes: IntentModes { .background }
    static var authenticationPolicy: IntentAuthenticationPolicy { .requiresAuthentication }
    @Parameter(title: "Count", default: 1, inclusiveRange: (1, 500)) var count: Int
    @Parameter(title: "Saved Only", default: false) var savedOnly: Bool
    @Parameter(title: "Folder") var folder: ClipFolderEntity?

    static var parameterSummary: some ParameterSummary {
        Summary("Get the latest \(\.$count) clippings") {
            \.$savedOnly
            \.$folder
        }
    }

    func perform() async throws -> some IntentResult & ReturnsValue<[String]> {
        let library = try await ClipStore.shared.snapshot()
        if let folder, !library.folders.contains(where: { $0.id == folder.id }) { throw ClipError.missingFolder }
        let clips = library.clips.sorted { $0.date > $1.date }.filter {
            !$0.text.isEmpty && (!savedOnly || $0.isSaved) && (folder == nil || $0.folderID == folder?.id)
        }
        return .result(value: Array(clips.prefix(max(1, min(500, count)))).map(\.text))
    }
}

struct ClipFolderEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Folder"
    static let defaultQuery = ClipFolderQuery()
    let id: UUID
    @Property(title: "Name") var name: String
    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(name)") }
    init(_ folder: ClipFolder) {
        id = folder.id
        name = folder.name
    }
}

struct ClipFolderQuery: EntityStringQuery {
    func entities(for identifiers: [UUID]) async throws -> [ClipFolderEntity] {
        let folders = try await ClipStore.shared.snapshot().folders
        return identifiers.compactMap { id in folders.first { $0.id == id }.map(ClipFolderEntity.init) }
    }
    func entities(matching string: String) async throws -> [ClipFolderEntity] {
        try await ClipStore.shared.snapshot().folders.filter { $0.name.localizedCaseInsensitiveContains(string) }.map(
            ClipFolderEntity.init)
    }
    func suggestedEntities() async throws -> [ClipFolderEntity] {
        try await ClipStore.shared.snapshot().folders.map(ClipFolderEntity.init)
    }
}

struct ClipShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: SaveClipboardIntent(), phrases: ["Save my clipboard to \(.applicationName)"],
            shortTitle: "Save Clipboard", systemImageName: "clipboard.fill")
        AppShortcut(
            intent: AddClippingIntent(), phrases: ["Add a clipping to \(.applicationName)"], shortTitle: "Add Clipping",
            systemImageName: "plus.square.on.square")
        AppShortcut(
            intent: GetLatestClippingsIntent(), phrases: ["Get my latest clippings from \(.applicationName)"],
            shortTitle: "Latest Clippings", systemImageName: "clipboard")
        AppShortcut(
            intent: GetLatestClippingFileIntent(), phrases: ["Get my latest clipping file from \(.applicationName)"],
            shortTitle: "Latest Clipping File", systemImageName: "doc")
        AppShortcut(
            intent: FindClippingsIntent(), phrases: ["Find clippings in \(.applicationName)"],
            shortTitle: "Find Clippings", systemImageName: "magnifyingglass")
    }
}

extension Notification.Name {
    static let clipLibraryChanged = Notification.Name("ClipityLibraryChanged")
}
