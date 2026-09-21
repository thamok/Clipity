import SwiftUI

private struct EditorCaptureScope: ViewModifier {
    @State private var registered = false
    func body(content: Content) -> some View {
        content
            .onAppear {
                guard !registered else { return }
                registered = true
                PasteboardMonitor.shared.beginEditing()
            }
            .onDisappear {
                guard registered else { return }
                registered = false
                PasteboardMonitor.shared.endEditing()
            }
    }
}

extension View {
    func deferAutomaticCaptureWhileEditing() -> some View { modifier(EditorCaptureScope()) }
}
