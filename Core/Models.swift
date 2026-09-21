import Foundation
import ImageIO
import UniformTypeIdentifiers

struct Clipping: Codable, Identifiable, Sendable, Equatable {
    var id = UUID()
    var date = Date()
    var text: String
    var image: Data?
    var imageID: String?
    var title: String?
    var folderID: UUID?
    var isSaved = false
    var labels: [String] = []
    var labelSource: String?
    var fileData: Data?
    var fileID: String?
    var filename: String?
    var fileType: String?

    var hasImage: Bool { image != nil || imageID != nil }
    var hasFile: Bool { fileData != nil || fileID != nil }
    var contentType: UTType {
        hasImage ? imageContentType : (fileType.flatMap(UTType.init) ?? (hasFile ? .data : .utf8PlainText))
    }
    var payload: Data { image ?? fileData ?? Data(text.utf8) }
    var byteCount: Int { text.utf8.count + (image?.count ?? 0) + (fileData?.count ?? 0) }
    var imageContentType: UTType {
        guard let image, let source = CGImageSourceCreateWithData(image as CFData, nil),
            let type = CGImageSourceGetType(source)
        else { return .image }
        return UTType(type as String) ?? .image
    }
    var displayTitle: String {
        title?.nilIfBlank ?? (hasImage ? "Image" : hasFile ? filename ?? "File" : String(text.prefix(200)))
    }
    var kind: String {
        hasImage
            ? "Image"
            : hasFile
                ? "File"
                : (URL(string: text)?.scheme == "https" || URL(string: text)?.scheme == "http" ? "Link" : "Text")
    }
}

struct ClipFolder: Codable, Identifiable, Sendable, Equatable {
    var id = UUID()
    var name: String
}

struct ClipSettings: Codable, Sendable, Equatable {
    var automaticCapture = true
    var aiLabels = false
    var historyLimit = 500
    var backgroundMonitoring = false
    var captureNotifications = true

    enum CodingKeys: String, CodingKey {
        case automaticCapture, aiLabels, historyLimit, backgroundMonitoring, captureNotifications
    }

    init(
        automaticCapture: Bool = true, aiLabels: Bool = false, historyLimit: Int = 500,
        backgroundMonitoring: Bool = false, captureNotifications: Bool = true
    ) {
        self.automaticCapture = automaticCapture
        self.aiLabels = aiLabels
        self.historyLimit = min(500, max(10, historyLimit))
        self.backgroundMonitoring = backgroundMonitoring
        self.captureNotifications = captureNotifications
    }

    init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            automaticCapture: try values.decodeIfPresent(Bool.self, forKey: .automaticCapture) ?? true,
            aiLabels: try values.decodeIfPresent(Bool.self, forKey: .aiLabels) ?? false,
            historyLimit: try values.decodeIfPresent(Int.self, forKey: .historyLimit) ?? 500,
            backgroundMonitoring: try values.decodeIfPresent(Bool.self, forKey: .backgroundMonitoring) ?? false,
            captureNotifications: try values.decodeIfPresent(Bool.self, forKey: .captureNotifications) ?? true)
    }
}

struct CaptureReceipt: Codable, Sendable {
    var token: String
    var clipIDs: [UUID]
}

struct CaptureResult: Sendable {
    var clips: [Clipping]
    var isNew: Bool
    var contentChanged: Bool
}

struct ClipboardBuffer: Codable, Sendable, Equatable {
    var token: String
    var fingerprint: String?
}

struct Library: Codable, Sendable {
    var version = 1
    var clips: [Clipping] = []
    var folders: [ClipFolder] = []
    var settings = ClipSettings()
    var captureReceipts: [CaptureReceipt]?
    var clipboardBuffer: ClipboardBuffer?
}

extension String {
    var nilIfBlank: String? { trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : self }
}

enum ClipError: LocalizedError, CustomLocalizedStringResourceConvertible {
    case unavailable, storage, empty, sensitive, tooLarge, missingFolder, missingClip, invalidFolder, unsupported,
        clipboardChanged, capturePaused
    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .unavailable: "Shared storage is unavailable. Check the App Group signing configuration."
        case .storage: "Clipity could not read or save its library. Please try again after unlocking your device."
        case .empty: "There is no clipping to save or retrieve."
        case .sensitive: "This looks like private or sensitive content and was not saved."
        case .tooLarge: "This clipping is too large. The limit is 10 MB per clipping."
        case .missingFolder: "That folder no longer exists. Choose another folder."
        case .missingClip: "That clipping no longer exists."
        case .invalidFolder: "Use a unique folder name between 1 and 80 characters."
        case .unsupported: "This item could not be read as text, a web link, an image, or a file."
        case .clipboardChanged: "The clipboard changed before it could be saved. Copy the item again to save it."
        case .capturePaused: "Automatic capture is paused."
        }
    }
    var errorDescription: String? { String(localized: localizedStringResource) }
}
