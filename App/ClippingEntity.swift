import AppIntents
import SwiftUI
import UniformTypeIdentifiers

struct ClippingEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Clipping"
    static let defaultQuery = ClippingQuery()
    let id: UUID
    @Property(title: "Title") var title: String
    @Property(title: "Text") var text: String
    @Property(title: "Kind") var kind: String
    @Property(title: "Date") var date: Date
    @Property(title: "Kept Permanently") var saved: Bool
    @Property(title: "Labels") var labels: [String]
    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(title)", subtitle: "\(kind)")
    }
    init(_ clip: Clipping) {
        id = clip.id
        title = clip.displayTitle
        text = clip.text
        kind = clip.kind
        date = clip.date
        saved = clip.isSaved
        labels = clip.labels
    }
}

struct ClippingQuery: EntityStringQuery {
    func entities(for identifiers: [UUID]) async throws -> [ClippingEntity] {
        let clips = try await ClipStore.shared.snapshot().clips
        let byID = Dictionary(uniqueKeysWithValues: clips.map { ($0.id, $0) })
        return identifiers.compactMap { byID[$0].map(ClippingEntity.init) }
    }
    func entities(matching string: String) async throws -> [ClippingEntity] {
        try await ClipStore.shared.findClips(search: string).map(ClippingEntity.init)
    }
    func suggestedEntities() async throws -> [ClippingEntity] {
        try await ClipStore.shared.findClips(limit: 25).map(ClippingEntity.init)
    }
}

struct FindClippingsIntent: AppIntent {
    static let title: LocalizedStringResource = "Find Clippings"
    static let description = IntentDescription(
        "Search history and permanent clippings by text, title, or label. Returns clipping entities, including images, for use in other actions."
    )
    static var supportedModes: IntentModes { .background }
    static var authenticationPolicy: IntentAuthenticationPolicy { .requiresAuthentication }
    @Parameter(title: "Search") var search: String?
    @Parameter(title: "Count", default: 25, inclusiveRange: (1, 500)) var count: Int
    @Parameter(title: "Saved Only", default: false) var savedOnly: Bool
    @Parameter(title: "Folder") var folder: ClipFolderEntity?
    static var parameterSummary: some ParameterSummary {
        Summary("Find clippings in Clipity") {
            \.$search
            \.$count
            \.$savedOnly
            \.$folder
        }
    }
    func perform() async throws -> some IntentResult & ReturnsValue<[ClippingEntity]> {
        let clips = try await ClipStore.shared.findClips(
            search: search ?? "", savedOnly: savedOnly, folderID: folder?.id, limit: count)
        return .result(value: clips.map(ClippingEntity.init))
    }
}

struct GetClippingFileIntent: AppIntent {
    static let title: LocalizedStringResource = "Get Clipping File"
    static let description = IntentDescription(
        "Get a chosen clipping as its original image or a UTF-8 text file. Connect this to Share or Save File in Shortcuts."
    )
    static var supportedModes: IntentModes { .background }
    static var authenticationPolicy: IntentAuthenticationPolicy { .requiresAuthentication }
    @Parameter(title: "Clipping") var clipping: ClippingEntity
    static var parameterSummary: some ParameterSummary { Summary("Get the file for \(\.$clipping)") }
    func perform() async throws -> some IntentResult & ReturnsValue<IntentFile> {
        let clip = try await ClipStore.shared.clipping(id: clipping.id)
        let type = clip.contentType
        return .result(
            value: IntentFile(
                data: clip.payload,
                filename: clip.filename ?? "Clipping.\(type.preferredFilenameExtension ?? "txt")", type: type))
    }
}

struct CopyClippingIntent: AppIntent {
    static let title: LocalizedStringResource = "Copy Clipping"
    static var supportedModes: IntentModes { .foreground }
    static var authenticationPolicy: IntentAuthenticationPolicy { .requiresAuthentication }
    @Parameter(title: "Clipping") var clipping: ClippingEntity
    static var parameterSummary: some ParameterSummary { Summary("Copy \(\.$clipping) to the clipboard") }
    func perform() async throws -> some IntentResult {
        let clip = try await ClipStore.shared.clipping(id: clipping.id)
        await ContentLoader.copy(clip)
        return .result()
    }
}

struct KeepClippingIntent: AppIntent {
    static let title: LocalizedStringResource = "Keep Clipping"
    static var supportedModes: IntentModes { .background }
    static var authenticationPolicy: IntentAuthenticationPolicy { .requiresAuthentication }
    @Parameter(title: "Clipping") var clipping: ClippingEntity
    @Parameter(title: "Folder") var folder: ClipFolderEntity?
    static var parameterSummary: some ParameterSummary { Summary("Keep \(\.$clipping) permanently") { \.$folder } }
    func perform() async throws -> some IntentResult & ReturnsValue<ClippingEntity> {
        let clip = try await ClipStore.shared.clipping(id: clipping.id)
        try await ClipStore.shared.update(
            id: clip.id, title: clip.title, folderID: folder?.id ?? clip.folderID, saved: true)
        return .result(value: ClippingEntity(try await ClipStore.shared.clipping(id: clip.id)))
    }
}

@MainActor @Observable
final class ClipNavigation {
    static let shared = ClipNavigation()
    var path: [ClipRoute] = []
    var selection = "history"
    var quickAction: ClipQuickAction?
}

struct OpenClippingIntent: OpenIntent {
    static let title: LocalizedStringResource = "Open Clipping"
    static var supportedModes: IntentModes { .foreground }
    static var authenticationPolicy: IntentAuthenticationPolicy { .requiresAuthentication }
    @Parameter(title: "Clipping") var target: ClippingEntity
    static var parameterSummary: some ParameterSummary { Summary("Open \(\.$target) in Clipity") }
    func perform() async throws -> some IntentResult {
        let clip = try await ClipStore.shared.clipping(id: target.id)
        await MainActor.run { ClipNavigation.shared.path = [.detail(clip.id)] }
        return .result()
    }
}

struct AddClippingFileIntent: AppIntent {
    static let title: LocalizedStringResource = "Add Clipping File"
    static let description = IntentDescription("Save a file supplied by a Shortcut or the Shortcuts share sheet.")
    static var supportedModes: IntentModes { .background }
    static var authenticationPolicy: IntentAuthenticationPolicy { .requiresAuthentication }
    @Parameter(title: "File", supportedContentTypes: [.data]) var file: IntentFile
    @Parameter(title: "Title") var title: String?
    @Parameter(title: "Keep Permanently", default: false) var keep: Bool
    @Parameter(title: "Folder") var folder: ClipFolderEntity?
    static var parameterSummary: some ParameterSummary {
        Summary("Add \(\.$file) to Clipity") {
            \.$title
            \.$keep
            \.$folder
        }
    }
    func perform() async throws -> some IntentResult & ReturnsValue<ClippingEntity> {
        let data = file.data
        guard data.count <= 10_000_000 else { throw ClipError.tooLarge }
        let type = file.type ?? UTType(filenameExtension: (file.filename as NSString).pathExtension) ?? .data
        var input = try await ContentLoader.file(data: data, name: file.filename, type: type)
        input.title = title?.nilIfBlank
        input.folderID = folder?.id
        input.isSaved = keep || folder != nil
        let clip = try await ClipStore.shared.addBatch([input])[0]
        return .result(value: ClippingEntity(clip))
    }
}
