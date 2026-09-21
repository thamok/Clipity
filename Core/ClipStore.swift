import CryptoKit
import Foundation
import SQLite3

/// SQLite serializes read-modify-write transactions across the app and all extension processes.
/// No cached snapshot is ever written back over another process's edits.
actor ClipStore {
    static let shared = ClipStore()
    static let groupID =
        Bundle.main.object(forInfoDictionaryKey: "ClipityAppGroup") as? String ?? "group.de.thamo.clipity"
    private let explicitURL: URL?

    init(url: URL? = nil) { explicitURL = url }

    static func storageRoot(
        groupContainer: (String) -> URL? = {
            FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: $0)
        },
        applicationSupport: () -> URL? = {
            FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).last
        }
    ) throws -> URL {
        if let shared = groupContainer(groupID) { return shared }
        guard let local = applicationSupport() else { throw ClipError.unavailable }
        return local.appendingPathComponent("AppGroup", isDirectory: true)
    }

    private func databaseURL() throws -> URL {
        if let explicitURL { return explicitURL }
        let fileManager = FileManager.default
        let root = try Self.storageRoot()
        let directory = root.appendingPathComponent("Library", isDirectory: true)
        try fileManager.createDirectory(
            at: directory, withIntermediateDirectories: true,
            attributes: [.protectionKey: FileProtectionType.complete])
        return directory.appendingPathComponent("Clipity.sqlite")
    }

    private func transaction<T>(_ body: (inout Library) throws -> T, writing: Bool = true) throws -> T {
        var db: OpaquePointer?
        let url = try databaseURL()
        guard
            sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX, nil)
                == SQLITE_OK, let db
        else {
            if let db { sqlite3_close(db) }
            throw ClipError.storage
        }
        defer { sqlite3_close(db) }
        sqlite3_busy_timeout(db, 5_000)
        func execute(_ sql: String) throws {
            guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else { throw ClipError.storage }
        }
        try execute("PRAGMA secure_delete=ON")
        try execute("CREATE TABLE IF NOT EXISTS library (id INTEGER PRIMARY KEY CHECK(id=1), data BLOB NOT NULL)")
        try execute("CREATE TABLE IF NOT EXISTS images (id TEXT PRIMARY KEY, data BLOB NOT NULL)")
        try execute(writing ? "BEGIN IMMEDIATE" : "BEGIN")
        do {
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(db, "SELECT data FROM library WHERE id=1", -1, &statement, nil) == SQLITE_OK else {
                throw ClipError.storage
            }
            var library = Library()
            let step = sqlite3_step(statement)
            if step == SQLITE_ROW, let bytes = sqlite3_column_blob(statement, 0) {
                let data = Data(bytes: bytes, count: Int(sqlite3_column_bytes(statement, 0)))
                sqlite3_finalize(statement)
                library = try JSONDecoder().decode(Library.self, from: data)
                guard library.version == 1 else { throw ClipError.storage }
            } else {
                sqlite3_finalize(statement)
                guard step == SQLITE_DONE else { throw ClipError.storage }
            }
            let result = try body(&library)
            if writing {
                // Keep image bytes out of library snapshots and metadata rewrites. Keyboard,
                // search, and Shortcuts never need to load every image into their process.
                for index in library.clips.indices {
                    for (isFile, image) in [(false, library.clips[index].image), (true, library.clips[index].fileData)]
                    {
                        guard let image else { continue }
                        let id = Self.imageID(image)
                        var insert: OpaquePointer?
                        guard
                            sqlite3_prepare_v2(
                                db, "INSERT OR IGNORE INTO images(id,data) VALUES(?,?)", -1, &insert, nil) == SQLITE_OK
                        else { throw ClipError.storage }
                        defer { sqlite3_finalize(insert) }
                        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
                        sqlite3_bind_text(insert, 1, id, -1, transient)
                        let bound = image.withUnsafeBytes {
                            sqlite3_bind_blob(insert, 2, $0.baseAddress, Int32($0.count), transient)
                        }
                        guard bound == SQLITE_OK, sqlite3_step(insert) == SQLITE_DONE else { throw ClipError.storage }
                        if isFile {
                            library.clips[index].fileID = id
                            library.clips[index].fileData = nil
                        } else {
                            library.clips[index].imageID = id
                            library.clips[index].image = nil
                        }
                    }
                }
                // IDs are SHA-256 hex strings, generated locally, never interpolated user input.
                let retained = Set(library.clips.flatMap { [$0.imageID, $0.fileID].compactMap { $0 } })
                guard retained.allSatisfy({ $0.count == 64 && $0.allSatisfy(\.isHexDigit) }) else {
                    throw ClipError.storage
                }
                let list = retained.map { "'\($0)'" }.joined(separator: ",")
                try execute(list.isEmpty ? "DELETE FROM images" : "DELETE FROM images WHERE id NOT IN (\(list))")
                let data = try JSONEncoder().encode(library)
                guard
                    sqlite3_prepare_v2(db, "INSERT OR REPLACE INTO library(id,data) VALUES(1,?)", -1, &statement, nil)
                        == SQLITE_OK
                else { throw ClipError.storage }
                defer { sqlite3_finalize(statement) }
                let status = data.withUnsafeBytes { bytes in
                    sqlite3_bind_blob(
                        statement, 1, bytes.baseAddress, Int32(bytes.count),
                        unsafeBitCast(-1, to: sqlite3_destructor_type.self))
                }
                guard status == SQLITE_OK, sqlite3_step(statement) == SQLITE_DONE else { throw ClipError.storage }
            }
            try execute("COMMIT")
            if writing { LibraryEvents.post() }
            return result
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
    }

    func snapshot() throws -> Library { try transaction({ $0 }, writing: false) }

    func hydrated(_ clip: Clipping) throws -> Clipping {
        guard let id = clip.imageID ?? clip.fileID, clip.image == nil && clip.fileData == nil else { return clip }
        var db: OpaquePointer?
        guard sqlite3_open_v2(try databaseURL().path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK, let db else {
            if let db { sqlite3_close(db) }
            throw ClipError.storage
        }
        defer { sqlite3_close(db) }
        sqlite3_busy_timeout(db, 5_000)
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT data FROM images WHERE id=?", -1, &statement, nil) == SQLITE_OK else {
            throw ClipError.storage
        }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_text(statement, 1, id, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        guard sqlite3_step(statement) == SQLITE_ROW, let bytes = sqlite3_column_blob(statement, 0) else {
            throw ClipError.missingClip
        }
        var result = clip
        let data = Data(bytes: bytes, count: Int(sqlite3_column_bytes(statement, 0)))
        if clip.hasFile { result.fileData = data } else { result.image = data }
        return result
    }

    private static func imageID(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    @discardableResult
    func add(text: String, image: Data? = nil, title: String? = nil, folderID: UUID? = nil, saved: Bool = false) throws
        -> Clipping
    {
        try addBatch([
            Clipping(
                text: text, image: image, title: title?.nilIfBlank, folderID: folderID,
                isSaved: saved || folderID != nil)
        ])[0]
    }

    func addBatch(_ clips: [Clipping]) throws -> [Clipping] {
        try ingest(clips, captureToken: nil).clips
    }

    /// A receipt and its entries commit together, including across app/extension processes.
    func captureBatch(_ clips: [Clipping], token: String, requireAutomaticCapture: Bool = false) throws -> CaptureResult
    {
        try ingest(
            clips, captureToken: token, clipboardFingerprint: Self.clipboardFingerprint(clips),
            requireAutomaticCapture: requireAutomaticCapture)
    }

    /// Records a signal whose contents iOS would not expose. This keeps repeated
    /// lifecycle notifications for one pasteboard event from repeatedly alerting.
    func markPendingClipboardSignal(token: String) throws -> Bool {
        try transaction { library in
            guard library.clipboardBuffer?.token != token else { return false }
            library.clipboardBuffer = ClipboardBuffer(
                token: token, fingerprint: library.clipboardBuffer?.fingerprint)
            return true
        }
    }

    private func ingest(
        _ clips: [Clipping], captureToken: String?, clipboardFingerprint: String? = nil,
        requireAutomaticCapture: Bool = false
    ) throws -> CaptureResult
    {
        guard !clips.isEmpty else { throw ClipError.empty }
        guard clips.count <= 20,
            clips.reduce(0, { $0 + $1.byteCount }) <= 20_000_000
        else { throw ClipError.tooLarge }
        return try transaction { library in
            if requireAutomaticCapture && !library.settings.automaticCapture { throw ClipError.capturePaused }
            for clip in clips {
                guard clip.image != nil || clip.fileData != nil || clip.text.nilIfBlank != nil else {
                    throw ClipError.empty
                }
                guard clip.byteCount <= 10_000_000 else { throw ClipError.tooLarge }
                guard !ClipPrivacy.looksSensitive(clip.text), !ClipPrivacy.looksSensitive(clip.title ?? "") else {
                    throw ClipError.sensitive
                }
                if let folder = clip.folderID, !library.folders.contains(where: { $0.id == folder }) {
                    throw ClipError.missingFolder
                }
            }
            if let captureToken, let receipt = library.captureReceipts?.first(where: { $0.token == captureToken }) {
                // Existing receipts predate the persistent clipboard buffer on
                // upgraded installs. Seed it quietly instead of announcing an
                // already handled copy event.
                if library.clipboardBuffer == nil {
                    library.clipboardBuffer = ClipboardBuffer(
                        token: captureToken, fingerprint: clipboardFingerprint)
                }
                // A Shortcut can promote an automatically captured clipping without duplicating it.
                for (offset, id) in receipt.clipIDs.enumerated() {
                    guard clips.indices.contains(offset), let index = library.clips.firstIndex(where: { $0.id == id })
                    else { continue }
                    if clips[offset].isSaved { library.clips[index].isSaved = true }
                    if let title = clips[offset].title { library.clips[index].title = title }
                    if let folder = clips[offset].folderID {
                        library.clips[index].folderID = folder
                        library.clips[index].isSaved = true
                    }
                }
                return CaptureResult(
                    clips: receipt.clipIDs.compactMap { id in library.clips.first { $0.id == id } }, isNew: false,
                    contentChanged: false)
            }
            let contentChanged =
                clipboardFingerprint.map { $0 != library.clipboardBuffer?.fingerprint } ?? true
            var results: [Clipping] = []
            for var clip in clips {
                if let image = clip.image { clip.imageID = Self.imageID(image) }
                if let file = clip.fileData { clip.fileID = Self.imageID(file) }
                if let index = library.clips.firstIndex(where: {
                    $0.text == clip.text && $0.imageID == clip.imageID && $0.fileID == clip.fileID && !$0.isSaved
                        && !clip.isSaved
                }) {
                    library.clips[index].date = clip.date
                    if let title = clip.title?.nilIfBlank { library.clips[index].title = title }
                    results.append(library.clips[index])
                } else {
                    library.clips.append(clip)
                    results.append(clip)
                }
            }
            Self.prune(&library)
            if let captureToken {
                var receipts = library.captureReceipts ?? []
                receipts.append(CaptureReceipt(token: captureToken, clipIDs: results.map(\.id)))
                library.captureReceipts = Array(receipts.suffix(32))
                library.clipboardBuffer = ClipboardBuffer(
                    token: captureToken, fingerprint: clipboardFingerprint)
            }
            return CaptureResult(clips: results, isNew: true, contentChanged: contentChanged)
        }
    }

    /// Hash only the ordered clipboard payload, excluding dates, generated IDs,
    /// titles, folders, and labels. Persisting a digest avoids retaining a second
    /// copy of potentially private clipboard contents solely for comparison.
    private static func clipboardFingerprint(_ clips: [Clipping]) throws -> String {
        struct Payload: Encodable {
            var text: String
            var image: String?
            var file: String?
            var filename: String?
            var fileType: String?
        }
        let payloads = clips.map {
            Payload(
                text: $0.text,
                image: $0.imageID ?? $0.image.map(imageID),
                file: $0.fileID ?? $0.fileData.map(imageID),
                filename: $0.filename,
                fileType: $0.fileType)
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return imageID(try encoder.encode(payloads))
    }

    func clipping(id: UUID) throws -> Clipping {
        guard let clip = try snapshot().clips.first(where: { $0.id == id }) else { throw ClipError.missingClip }
        return try hydrated(clip)
    }

    func findClips(search: String = "", savedOnly: Bool = false, folderID: UUID? = nil, limit: Int = 500) throws
        -> [Clipping]
    {
        let library = try snapshot()
        if let folderID, !library.folders.contains(where: { $0.id == folderID }) { throw ClipError.missingFolder }
        return Array(
            library.clips.sorted { $0.date > $1.date }.lazy.filter { clip in
                (!savedOnly || clip.isSaved) && (folderID == nil || clip.folderID == folderID)
                    && (search.isEmpty
                        || [clip.text, clip.title ?? "", clip.filename ?? "", clip.labels.joined(separator: " ")]
                            .contains { $0.localizedCaseInsensitiveContains(search) })
            }.prefix(min(500, max(1, limit))))
    }

    func update(id: UUID, title: String?, folderID: UUID?, saved: Bool) throws {
        try transaction { library in
            guard let index = library.clips.firstIndex(where: { $0.id == id }) else { throw ClipError.missingClip }
            if let folderID, !library.folders.contains(where: { $0.id == folderID }) { throw ClipError.missingFolder }
            guard !ClipPrivacy.looksSensitive(title ?? "") else { throw ClipError.sensitive }
            library.clips[index].title = title?.nilIfBlank
            library.clips[index].folderID = saved ? folderID : nil
            library.clips[index].isSaved = saved
            Self.prune(&library)
        }
    }

    func label(id: UUID, labels: [String], source: String) throws {
        try transaction { library in
            guard let index = library.clips.firstIndex(where: { $0.id == id }) else { return }
            library.clips[index].labels = Array(labels.prefix(3)).map { String($0.prefix(32)) }
            library.clips[index].labelSource = source
        }
    }

    func delete(id: UUID) throws { try transaction { $0.clips.removeAll { $0.id == id } } }
    func clearHistory() throws { try transaction { $0.clips.removeAll { !$0.isSaved } } }
    func settings(_ settings: ClipSettings) throws {
        try transaction {
            $0.settings = settings
            $0.settings.historyLimit = min(500, max(10, settings.historyLimit))
            Self.prune(&$0)
        }
    }

    @discardableResult
    func folder(name: String, id: UUID? = nil) throws -> ClipFolder {
        try transaction { library in
            let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty, name.count <= 80,
                !library.folders.contains(where: {
                    $0.id != id && $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame
                })
            else { throw ClipError.invalidFolder }
            if let id {
                guard let index = library.folders.firstIndex(where: { $0.id == id }) else {
                    throw ClipError.missingFolder
                }
                library.folders[index].name = name
                return library.folders[index]
            }
            let folder = ClipFolder(name: name)
            library.folders.append(folder)
            return folder
        }
    }

    func deleteFolder(id: UUID) throws {
        try transaction { library in
            library.folders.removeAll { $0.id == id }
            for index in library.clips.indices where library.clips[index].folderID == id {
                library.clips[index].folderID = nil
            }
        }
    }

    private static func prune(_ library: inout Library) {
        library.clips.sort { $0.date > $1.date }
        var count = 0
        library.clips.removeAll { clip in
            guard !clip.isSaved else { return false }
            count += 1
            return count > library.settings.historyLimit
        }
    }
}
