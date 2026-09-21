import UIKit
import UniformTypeIdentifiers

@MainActor
enum ContentLoader {
    static func load(_ providers: [NSItemProvider]) async throws -> [Clipping] {
        guard !providers.isEmpty else { throw ClipError.empty }
        guard providers.count <= 20 else { throw ClipError.tooLarge }
        var clips: [Clipping] = []
        for provider in providers {
            guard !ClipPrivacy.isPrivate(types: provider.registeredTypeIdentifiers) else { throw ClipError.sensitive }
            if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
                let data = try await data(provider, type: UTType.image.identifier)
                guard data.count <= 10_000_000 else { throw ClipError.tooLarge }
                guard UIImage(data: data) != nil else { throw ClipError.unsupported }
                clips.append(Clipping(text: "", image: data))
            } else if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                let url: URL = try await withCheckedThrowingContinuation { continuation in
                    provider.loadObject(ofClass: NSURL.self) { object, error in
                        if let url = object as? URL {
                            continuation.resume(returning: url)
                        } else {
                            continuation.resume(throwing: error ?? ClipError.unsupported)
                        }
                    }
                }
                let access = url.startAccessingSecurityScopedResource()
                defer { if access { url.stopAccessingSecurityScopedResource() } }
                let size = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
                guard size.isRegularFile == true else { throw ClipError.unsupported }
                guard (size.fileSize ?? Int.max) <= 10_000_000 else { throw ClipError.tooLarge }
                clips.append(
                    try file(
                        data: Data(contentsOf: url), name: url.lastPathComponent,
                        type: UTType(filenameExtension: url.pathExtension) ?? .data))
            } else if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
                // NSURL providers may serialize URL data as an archive, not UTF-8 bytes.
                // Ask NSItemProvider to decode its registered URL representation.
                let url: URL = try await withCheckedThrowingContinuation { continuation in
                    provider.loadObject(ofClass: NSURL.self) { object, error in
                        if let url = object as? URL {
                            continuation.resume(returning: url)
                        } else {
                            continuation.resume(throwing: error ?? ClipError.unsupported)
                        }
                    }
                }
                guard ["https", "http"].contains(url.scheme?.lowercased() ?? "") else { throw ClipError.unsupported }
                clips.append(Clipping(text: url.absoluteString))
            } else if provider.hasItemConformingToTypeIdentifier(UTType.text.identifier) {
                let identifier =
                    [UTType.utf8PlainText, .plainText, .text].first {
                        provider.hasItemConformingToTypeIdentifier($0.identifier)
                    }?.identifier ?? UTType.text.identifier
                let data = try await data(provider, type: identifier)
                guard let text = String(data: data, encoding: .utf8) else { throw ClipError.unsupported }
                clips.append(Clipping(text: text))
            } else if let identifier = provider.registeredTypeIdentifiers.first(where: {
                UTType($0)?.conforms(to: .data) == true
            }) {
                clips.append(
                    try file(
                        data: await data(provider, type: identifier), name: provider.suggestedName,
                        type: UTType(identifier) ?? .data))
            } else {
                throw ClipError.unsupported
            }
        }
        guard clips.reduce(0, { $0 + $1.byteCount }) <= 20_000_000 else { throw ClipError.tooLarge }
        return clips
    }

    static func file(data: Data, name: String?, type: UTType) throws -> Clipping {
        guard data.count <= 10_000_000 else { throw ClipError.tooLarge }
        guard !data.isEmpty else { throw ClipError.empty }
        if type.conforms(to: .image) {
            guard UIImage(data: data) != nil else { throw ClipError.unsupported }
            return Clipping(text: "", image: data)
        }
        let filename =
            name?.nilIfBlank.map { ($0 as NSString).lastPathComponent }
            ?? "Clipping.\(type.preferredFilenameExtension ?? "data")"
        let text = type.conforms(to: .plainText) ? String(data: data, encoding: .utf8) ?? "" : ""
        return Clipping(text: text, fileData: data, filename: filename, fileType: type.identifier)
    }

    private static func data(_ provider: NSItemProvider, type: String) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            provider.loadDataRepresentation(forTypeIdentifier: type) { data, error in
                if let data {
                    continuation.resume(returning: data)
                } else {
                    continuation.resume(throwing: error ?? ClipError.unsupported)
                }
            }
        }
    }

    static func copy(_ clip: Clipping) {
        var values: [String: Any] = ["de.thamo.clipity.clipping": Data()]
        if let image = clip.image {
            values[clip.imageContentType.identifier] = image
        } else if let file = clip.fileData {
            values[clip.contentType.identifier] = file
        } else {
            values[UTType.utf8PlainText.identifier] = clip.text
        }
        UIPasteboard.general.setItems([values], options: [.localOnly: true])
    }
}
