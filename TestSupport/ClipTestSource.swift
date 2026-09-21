import SwiftUI

/// A separate foreground source app for physical-device clipboard acceptance.
/// XCTest's background runner cannot write the device pasteboard itself.
@main
struct ClipityTestSource: App {
    private var text: String {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "--clip-proof"), arguments.indices.contains(index + 1) else {
            return "Clipboard source test"
        }
        return arguments[index + 1]
    }
    var body: some Scene {
        WindowGroup {
            VStack(spacing: 24) {
                Text("Clipboard Test Source").font(.title)
                Text(text).textSelection(.enabled)
                Button("Copy Test Clipping") { UIPasteboard.general.string = text }
                    .buttonStyle(.borderedProminent)
            }.padding()
        }
    }
}
