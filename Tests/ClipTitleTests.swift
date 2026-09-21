import FoundationModels
import Testing
import UIKit

@testable import Clipity

// Vision requires an Espresso compute context unavailable in this simulator runtime.
// Run these real-model acceptance tests on a physical Apple Intelligence device.
#if !targetEnvironment(simulator)
    struct ClipTitleTests {
        @Test(.enabled(if: SystemLanguageModel.default.isAvailable))
        @MainActor func generatesTitleForAnImageWithoutTextAndFileMetadata() async throws {
            let image = UIGraphicsImageRenderer(size: CGSize(width: 600, height: 400)).pngData { context in
                UIColor.systemBlue.setFill()
                context.fill(CGRect(x: 0, y: 0, width: 600, height: 400))
                UIColor.systemGreen.setFill()
                context.cgContext.fillEllipse(in: CGRect(x: -100, y: 200, width: 500, height: 400))
                context.cgContext.fillEllipse(in: CGRect(x: 200, y: 220, width: 500, height: 400))
                UIColor.systemYellow.setFill()
                context.cgContext.fillEllipse(in: CGRect(x: 420, y: 40, width: 80, height: 80))
            }
            let title = try await ClipTitleGenerator.title(for: Clipping(text: "", image: image))
            #expect(!title.isEmpty && title.count <= 120)
            let fileTitle = try await ClipTitleGenerator.title(
                for: Clipping(
                    text: "", fileData: Data([0xff, 0x00, 0xfe]), filename: "Landscape illustration.design",
                    fileType: "public.data"))
            #expect(!fileTitle.isEmpty && fileTitle.count <= 120)
        }

        @Test(.enabled(if: SystemLanguageModel.default.isAvailable))
        @MainActor func generatesTitlesForImagesAndPDFDocuments() async throws {
            let text = "Mountain walk\nPack walking shoes, a rain jacket, and water."
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 26), .foregroundColor: UIColor.black,
            ]
            let rect = CGRect(x: 20, y: 20, width: 560, height: 350)
            let image = UIGraphicsImageRenderer(size: CGSize(width: 600, height: 400)).pngData { context in
                UIColor.white.setFill()
                context.fill(CGRect(x: 0, y: 0, width: 600, height: 400))
                (text as NSString).draw(in: rect, withAttributes: attributes)
            }
            let imageTitle = try await ClipTitleGenerator.title(for: Clipping(text: "", image: image))
            #expect(!imageTitle.isEmpty && imageTitle.count <= 120)

            let pdf = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 600, height: 400)).pdfData { context in
                context.beginPage()
                (text as NSString).draw(in: rect, withAttributes: attributes)
            }
            let pdfTitle = try await ClipTitleGenerator.title(
                for: Clipping(text: "", fileData: pdf, filename: "Packing.pdf", fileType: "com.adobe.pdf"))
            #expect(!pdfTitle.isEmpty && pdfTitle.count <= 120)
        }
    }

#endif
