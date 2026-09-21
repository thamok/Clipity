import ImageIO
import SwiftUI

actor ClipThumbnailCache {
    static let shared = ClipThumbnailCache()
    private let cache = NSCache<NSString, CGImage>()
    init() { cache.totalCostLimit = 12_000_000 }

    func image(for clip: Clipping) async throws -> CGImage? {
        let key = (clip.imageID ?? clip.id.uuidString) as NSString
        if let image = cache.object(forKey: key) { return image }
        guard let data = try await ClipStore.shared.hydrated(clip).image,
            let source = CGImageSourceCreateWithData(data as CFData, nil),
            let image = CGImageSourceCreateThumbnailAtIndex(
                source, 0,
                [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceThumbnailMaxPixelSize: 240,
                ] as CFDictionary)
        else { return nil }
        cache.setObject(image, forKey: key, cost: image.bytesPerRow * image.height)
        return image
    }
}

struct ClipThumbnail: View {
    let clip: Clipping
    @State private var image: CGImage?
    var body: some View {
        Group {
            if let image {
                Image(decorative: image, scale: 1).resizable().scaledToFill()
            } else {
                Image(systemName: "photo").foregroundStyle(.secondary)
            }
        }
        .frame(width: 76, height: 76)
        .background(.quaternary, in: .rect(cornerRadius: 10))
        .clipShape(.rect(cornerRadius: 10))
        .accessibilityLabel("Image preview")
        .task(id: clip.imageID ?? clip.id.uuidString) {
            image = try? await ClipThumbnailCache.shared.image(for: clip)
        }
    }
}
