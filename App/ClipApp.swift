import SwiftUI
import WidgetKit

@main
struct ClipApp: App {
    @UIApplicationDelegateAdaptor(ClipAppDelegate.self) private var appDelegate
    @State private var model = LibraryModel()
    @AppStorage("appearance") private var appearance = "system"
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            LibraryView(model: model)
                .tint(ClipTheme.foreground)
                .preferredColorScheme(appearance == "dark" ? .dark : appearance == "light" ? .light : nil)
                .overlay {
                    if scenePhase != .active {
                        Rectangle().fill(.background).ignoresSafeArea()
                            .overlay { Label("Clipity", systemImage: "clipboard.fill").font(.largeTitle) }
                    }
                }
                .task { await model.start() }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active {
                        Task {
                            await model.refresh()
                            await model.labelPending()
                        }
                    }
                }
                .onOpenURL { url in
                    if url.scheme == "clipity" { Task { await model.refresh() } }
                }
                .onReceive(NotificationCenter.default.publisher(for: .clipLibraryChanged)) { _ in
                    Task {
                        await model.refresh()
                        await model.labelPending()
                    }
                }
        }
    }
}

@MainActor @Observable
final class LibraryModel {
    var library = Library()
    var error: String?
    var notice: String?
    var loading = true
    var labeling = false
    let monitor = PasteboardMonitor.shared
    private var started = false
    private var settingsWrite: Task<Void, Never>?
    private var pendingSettings: ClipSettings?

    func start() async {
        guard !started else { return }
        started = true
        await refresh()
        await monitor.start()
        await labelPending()
    }

    func refresh() async {
        do {
            library = try await ClipStore.shared.snapshot()
            if let pendingSettings { library.settings = pendingSettings }
        } catch { self.error = error.localizedDescription }
        loading = false
    }

    func perform(_ operation: () async throws -> Void) async {
        do {
            try await operation()
            await refresh()
            WidgetCenter.shared.reloadAllTimelines()
        } catch { self.error = error.localizedDescription }
    }

    func copy(_ clip: Clipping) async {
        do {
            ContentLoader.copy(try await ClipStore.shared.hydrated(clip))
            notice = "Copied"
        } catch { self.error = error.localizedDescription }
    }

    func capture() async {
        do {
            let result = try await monitor.capture()
            notice = result.isNew ? "Saved to history" : "Clipboard already in history"
            await refresh()
            await labelPending()
        } catch { self.error = error.localizedDescription }
    }

    func updateSettings(_ settings: ClipSettings) {
        pendingSettings = settings
        library.settings = settings
        let previous = settingsWrite
        settingsWrite = Task {
            await previous?.value
            do {
                try await ClipStore.shared.settings(settings)
                await monitor.reloadSettings()
                if pendingSettings == settings {
                    pendingSettings = nil
                    await refresh()
                }
                // A paste-permission dialog/provider read must not block the next
                // settings write (especially Pause or background authorization).
                if settings.automaticCapture { Task { await monitor.becameActive() } }
            } catch {
                if pendingSettings == settings { pendingSettings = nil }
                self.error = error.localizedDescription
                await refresh()
            }
        }
    }

    func labelPending() async {
        guard library.settings.aiLabels, !labeling else { return }
        labeling = true
        defer { labeling = false }
        for clip in library.clips where clip.labels.isEmpty {
            guard !Task.isCancelled, UIApplication.shared.applicationState == .active else { break }
            do {
                let labels = try await ClipLabeler.labels(for: ClipStore.shared.hydrated(clip))
                try await ClipStore.shared.label(id: clip.id, labels: labels, source: "Apple Intelligence")
            } catch {
                notice = "AI labels unavailable: \(error.localizedDescription)"
                break
            }
        }
        await refresh()
    }
}
