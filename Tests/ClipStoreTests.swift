import Foundation
import Testing
import UIKit
import UniformTypeIdentifiers

@testable import Clipity

struct ClipStoreTests {
    private func store() -> (ClipStore, URL) {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".sqlite")
        return (ClipStore(url: url), url)
    }

    @Test func existingSettingsDecodeWithoutLosingPreferences() throws {
        let data = Data(#"{"automaticCapture":false,"aiLabels":true,"historyLimit":100}"#.utf8)
        let settings = try JSONDecoder().decode(ClipSettings.self, from: data)
        #expect(!settings.automaticCapture && settings.aiLabels && settings.historyLimit == 100)
        #expect(!settings.backgroundMonitoring && settings.captureNotifications)
        #expect(ClipSettings().automaticCapture && ClipSettings().historyLimit == 500)
        let library = try JSONDecoder().decode(
            Library.self,
            from: Data(
                #"{"version":1,"clips":[],"folders":[],"settings":{"automaticCapture":true,"aiLabels":false,"historyLimit":50}}"#
                    .utf8))
        #expect(library.captureReceipts == nil)
        #expect(library.clipboardBuffer == nil)
        #expect(library.settings.historyLimit == 50)
    }

    @Test func filesPersistWithoutBloatedSnapshotsAndSurviveOrganization() async throws {
        let (store, url) = store()
        defer { try? FileManager.default.removeItem(at: url) }
        let data = Data("A document with useful notes".utf8)
        let input = Clipping(text: "", fileData: data, filename: "Notes.pdf", fileType: "com.adobe.pdf")
        let file = try await store.addBatch([input])[0]
        let snapshot = try await store.snapshot()
        #expect(snapshot.clips[0].fileData == nil && snapshot.clips[0].hasFile)
        #expect(snapshot.clips[0].kind == "File")
        let folder = try await store.folder(name: "Documents")
        try await store.update(id: file.id, title: "Useful notes", folderID: folder.id, saved: true)
        let reopened = try await ClipStore(url: url).clipping(id: file.id)
        #expect(reopened.fileData == data && reopened.filename == "Notes.pdf")
        #expect(reopened.contentType.identifier == "com.adobe.pdf")
        #expect(reopened.isSaved && reopened.folderID == folder.id)
        try await store.clearHistory()
        #expect(try await store.clipping(id: file.id).payload == data)
        try await store.delete(id: file.id)
        await #expect(throws: ClipError.missingClip) { _ = try await store.hydrated(snapshot.clips[0]) }
    }

    @Test @MainActor func fileProvidersPreserveBytesAndNames() async throws {
        let provider = NSItemProvider()
        let data = Data("%PDF-1.7 fixture".utf8)
        provider.suggestedName = "Reference.pdf"
        provider.registerDataRepresentation(forTypeIdentifier: "com.adobe.pdf", visibility: .all) { completion in
            completion(data, nil)
            return nil
        }
        let clips = try await ContentLoader.load([provider])
        #expect(clips.count == 1)
        #expect(clips[0].filename == "Reference.pdf" && clips[0].fileData == data)
        #expect(clips[0].contentType.identifier == "com.adobe.pdf")
    }

    @Test func filesParticipateInSizeLimitsAndDeduplication() async throws {
        let (store, url) = store()
        defer { try? FileManager.default.removeItem(at: url) }
        let first = Clipping(text: "", fileData: Data([1, 2, 3]), filename: "First.bin", fileType: "public.data")
        let second = Clipping(text: "", fileData: Data([4, 5, 6]), filename: "Second.bin", fileType: "public.data")
        _ = try await store.addBatch([first, second, first])
        #expect(try await store.snapshot().clips.count == 2)
        await #expect(throws: ClipError.tooLarge) {
            _ = try await store.addBatch([Clipping(text: "", fileData: Data(repeating: 0, count: 10_000_001))])
        }
        #expect(try await store.snapshot().clips.count == 2)
    }

    @Test func fiveHundredNewestEntriesPersistAcrossReopen() async throws {
        let (store, url) = store()
        defer { try? FileManager.default.removeItem(at: url) }
        let kept = try await store.add(text: "Keep this outside history", saved: true)
        for batch in 0..<26 {
            _ = try await store.addBatch(
                (0..<20).map { index in
                    let number = batch * 20 + index
                    return Clipping(date: Date(timeIntervalSince1970: Double(number)), text: "History entry \(number)")
                })
        }
        let reopened = ClipStore(url: url)
        let clips = try await reopened.snapshot().clips
        #expect(clips.filter { !$0.isSaved }.count == 500)
        #expect(clips.contains { $0.id == kept.id })
        #expect(!clips.contains { $0.text == "History entry 19" })
        #expect(clips.contains { $0.text == "History entry 20" })
        #expect(clips.contains { $0.text == "History entry 519" })
    }

    @Test func concurrentCaptureReceiptCommitsOnceAndCanPromote() async throws {
        let (first, url) = store()
        defer { try? FileManager.default.removeItem(at: url) }
        let second = ClipStore(url: url)
        let original = Clipping(text: "One copy event")
        async let one = first.captureBatch([original], token: "boot:copy")
        async let two = second.captureBatch([original], token: "boot:copy")
        let results = try await [one, two]
        #expect(results.filter(\.isNew).count == 1)
        #expect(results.filter(\.contentChanged).count == 1)
        #expect(try await first.snapshot().clips.count == 1)
        let folder = try await first.folder(name: "Permanent")
        let promoted = Clipping(text: original.text, title: "Named copy", folderID: folder.id, isSaved: true)
        let result = try await ClipStore(url: url).captureBatch([promoted], token: "boot:copy")
        #expect(!result.isNew && result.clips.first?.id == original.id)
        #expect(result.clips.first?.isSaved == true && result.clips.first?.folderID == folder.id)
        #expect(result.clips.first?.title == "Named copy")
        #expect(try await first.snapshot().clips.count == 1)
    }

    @Test func clipboardBufferSuppressesUnchangedContentAcrossEventsAndRelaunches() async throws {
        let (store, url) = store()
        defer { try? FileManager.default.removeItem(at: url) }
        let original = Clipping(text: "Same clipboard payload")
        let first = try await store.captureBatch([original], token: "boot:1")
        let repeated = try await ClipStore(url: url).captureBatch(
            [Clipping(text: original.text)], token: "boot:2")
        let changed = try await ClipStore(url: url).captureBatch(
            [Clipping(text: "A different clipboard payload")], token: "boot:3")

        #expect(first.contentChanged)
        #expect(!repeated.contentChanged)
        #expect(changed.contentChanged)
        #expect(try await store.snapshot().clipboardBuffer?.token == "boot:3")
    }

    @Test func pendingClipboardSignalsArePersistentlyCoalescedByToken() async throws {
        let (store, url) = store()
        defer { try? FileManager.default.removeItem(at: url) }

        #expect(try await store.markPendingClipboardSignal(token: "boot:10"))
        #expect(!(try await ClipStore(url: url).markPendingClipboardSignal(token: "boot:10")))
        #expect(try await ClipStore(url: url).markPendingClipboardSignal(token: "boot:11"))
    }

    @Test func failedCaptureDoesNotLeaveReceiptAndRetryWorks() async throws {
        let (store, url) = store()
        defer { try? FileManager.default.removeItem(at: url) }
        await #expect(throws: ClipError.missingFolder) {
            _ = try await store.captureBatch([Clipping(text: "A note", folderID: UUID())], token: "retry")
        }
        #expect(try await store.snapshot().captureReceipts == nil)
        let result = try await store.captureBatch([Clipping(text: "A note")], token: "retry")
        #expect(result.isNew)
        try await store.clearHistory()
        let replay = try await store.captureBatch([Clipping(text: "A note")], token: "retry")
        #expect(!replay.isNew && replay.clips.isEmpty)
        #expect(try await store.snapshot().clips.isEmpty)
        let recopy = try await store.captureBatch([Clipping(text: "A note")], token: "new copy")
        #expect(recopy.isNew && recopy.clips.count == 1)
    }

    @Test func pausingDuringProviderLoadPreventsAutomaticCommit() async throws {
        let (store, url) = store()
        defer { try? FileManager.default.removeItem(at: url) }
        try await store.settings(ClipSettings(automaticCapture: false))
        let clip = Clipping(text: "A delayed clipboard provider")
        await #expect(throws: ClipError.capturePaused) {
            _ = try await store.captureBatch([clip], token: "delayed", requireAutomaticCapture: true)
        }
        #expect(try await store.snapshot().clips.isEmpty)
        let manual = try await store.captureBatch([clip], token: "delayed")
        #expect(manual.isNew)
    }

    @Test func retrievalFindsTitlesLabelsFoldersAndImages() async throws {
        let (store, url) = store()
        defer { try? FileManager.default.removeItem(at: url) }
        let folder = try await store.folder(name: "Work")
        let clip = try await store.add(text: "A useful command", title: "Build instructions", folderID: folder.id)
        try await store.label(id: clip.id, labels: ["Developer"], source: "Test")
        let image = try await store.add(text: "", image: Data([1, 2, 3]))
        #expect(try await store.findClips(search: "BUILD").map(\.id) == [clip.id])
        #expect(
            try await store.findClips(search: "developer", savedOnly: true, folderID: folder.id).map(\.id) == [clip.id])
        #expect(try await store.findClips(limit: 1).first?.id == image.id)
        #expect(try await store.clipping(id: image.id).image == Data([1, 2, 3]))
        await #expect(throws: ClipError.missingFolder) { try await store.findClips(folderID: UUID()) }
        try await store.delete(id: clip.id)
        await #expect(throws: ClipError.missingClip) { try await store.clipping(id: clip.id) }
    }

    @Test func permanentClipsSurvivePruningAndClear() async throws {
        let (store, url) = store()
        defer { try? FileManager.default.removeItem(at: url) }
        let folder = try await store.folder(name: "Ideas")
        let kept = try await store.add(text: "Keep this", folderID: folder.id)
        try await store.settings(ClipSettings(historyLimit: 10))
        for index in 0..<15 { try await store.add(text: "Note number \(index)") }
        let library = try await store.snapshot()
        #expect(library.clips.count == 11)
        #expect(library.clips.contains { $0.id == kept.id && $0.isSaved })
        try await store.clearHistory()
        #expect(try await store.snapshot().clips.map(\.id) == [kept.id])
        try await store.deleteFolder(id: folder.id)
        let remaining = try await store.snapshot().clips[0]
        #expect(remaining.isSaved && remaining.folderID == nil && remaining.title == nil)
    }

    @Test func parallelWritersDoNotLoseEntries() async throws {
        let (first, url) = store()
        defer { try? FileManager.default.removeItem(at: url) }
        let second = ClipStore(url: url)
        try await withThrowingTaskGroup(of: Void.self) { group in
            for index in 0..<30 {
                group.addTask {
                    _ = try await (index.isMultiple(of: 2) ? first : second).add(text: "Concurrent note \(index)")
                }
            }
            try await group.waitForAll()
        }
        #expect(try await first.snapshot().clips.count == 30)
    }

    @Test func privacyMarkersAndSecrets() {
        #expect(ClipPrivacy.isPrivate(types: ["public.text", "org.nspasteboard.ConcealedType"]))
        #expect(ClipPrivacy.isPrivate(types: ["org.nspasteboard.TransientType"]))
        #expect(ClipPrivacy.isPrivate(types: ["com.agilebits.onepassword"]))
        #expect(ClipPrivacy.looksSensitive("password=example-secret"))
        #expect(ClipPrivacy.looksSensitive("123456"))
        #expect(ClipPrivacy.looksSensitive("MySecret123!"))
        #expect(!ClipPrivacy.looksSensitive("An ordinary idea to keep."))
        #expect(!ClipPrivacy.looksSensitive("https://example.com/Article123"))
        #expect(ClipPrivacy.looksSensitive("https://example.com/?access_token=private"))
        #expect(ClipPrivacy.looksSensitive("https://user:password@example.com"))
        #expect(ClipPrivacy.looksSensitive("4111 1111 1111 1111"))
    }

    @Test func batchIsAtomicAndRejectsSecrets() async throws {
        let (store, url) = store()
        defer { try? FileManager.default.removeItem(at: url) }
        await #expect(throws: ClipError.sensitive) {
            _ = try await store.addBatch([Clipping(text: "Ordinary note"), Clipping(text: "password=secret")])
        }
        #expect(try await store.snapshot().clips.isEmpty)
    }

    @Test func invalidFolderAndDuplicateNameAreRejected() async throws {
        let (store, url) = store()
        defer { try? FileManager.default.removeItem(at: url) }
        try await store.folder(name: "Travel")
        await #expect(throws: ClipError.invalidFolder) { try await store.folder(name: " travel ") }
        await #expect(throws: ClipError.missingFolder) { try await store.add(text: "Note", folderID: UUID()) }
        #expect(try await store.snapshot().clips.isEmpty)
    }

    @Test func reopeningAndMetadataPreserveContent() async throws {
        let (store, url) = store()
        defer { try? FileManager.default.removeItem(at: url) }
        let clip = try await store.add(text: "Original text")
        let reopened = ClipStore(url: url)
        try await reopened.update(id: clip.id, title: "Optional title", folderID: nil, saved: true)
        try await store.label(id: clip.id, labels: ["Work"], source: "Test")
        let result = try await reopened.snapshot().clips[0]
        #expect(result.text == clip.text && result.title == "Optional title" && result.isSaved)
        #expect(result.labels == ["Work"])
    }

    @Test func corruptLibraryIsNotOverwritten() async throws {
        let (store, url) = store()
        defer { try? FileManager.default.removeItem(at: url) }
        let invalid = Data("not a database".utf8)
        try invalid.write(to: url)
        await #expect(throws: (any Error).self) { try await store.add(text: "New note") }
        #expect(try Data(contentsOf: url) == invalid)
    }

    @Test func imageSnapshotsAreLightweightAndDeletionCleansPayload() async throws {
        let (store, url) = store()
        defer { try? FileManager.default.removeItem(at: url) }
        let image = Data(repeating: 12, count: 100_000)
        let first = try await store.add(text: "", image: image)
        let duplicate = try await store.add(text: "", image: image)
        #expect(first.id == duplicate.id)
        let snapshot = try await store.snapshot()
        #expect(snapshot.clips.count == 1)
        #expect(snapshot.clips[0].hasImage && snapshot.clips[0].image == nil)
        #expect(try await store.hydrated(snapshot.clips[0]).image == image)
        try await store.delete(id: first.id)
        await #expect(throws: ClipError.missingClip) { try await store.hydrated(snapshot.clips[0]) }
    }

    @Test @MainActor func shareProviderLoadsText() async throws {
        let text = try await ContentLoader.load([NSItemProvider(object: "A shared note" as NSString)])
        #expect(text[0].text == "A shared note")
    }

    @Test @MainActor func shareProviderLoadsURL() async throws {
        let link = URL(string: "https://example.com/article")!
        let urls = try await ContentLoader.load([NSItemProvider(object: link as NSURL)])
        #expect(urls[0].text == link.absoluteString)
    }

    @Test @MainActor func shareProviderLoadsImageAndRejectsPrivateMarker() async throws {
        let image = UIGraphicsImageRenderer(size: CGSize(width: 10, height: 10)).image { context in
            UIColor.systemTeal.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 10, height: 10))
        }
        let images = try await ContentLoader.load([NSItemProvider(object: image)])
        #expect(images[0].hasImage)
        #expect(images[0].imageContentType.conforms(to: .image))
        let concealed = NSItemProvider(object: "Private content" as NSString)
        concealed.registerDataRepresentation(forTypeIdentifier: "org.nspasteboard.ConcealedType", visibility: .all) {
            completion in
            completion(Data(), nil)
            return nil
        }
        await #expect(throws: ClipError.sensitive) { try await ContentLoader.load([concealed]) }
    }

}
