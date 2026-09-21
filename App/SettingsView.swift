import FoundationModels
import SwiftUI

struct SettingsView: View {
    @Bindable var model: LibraryModel
    var initialSection: SettingsSection? = nil
    @AppStorage("appearance") private var appearance = "system"
    @State private var clear = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Form {
            if initialSection == nil || initialSection == .appearance {
                Section("Appearance") {
                    Picker("Theme", selection: $appearance) {
                        Text("System").tag("system")
                        Text("Light").tag("light")
                        Text("Dark").tag("dark")
                    }
                }
            }
            if initialSection == nil || initialSection == .clipboard {
                Section {
                    Toggle("Automatic clipboard history", isOn: setting(\.automaticCapture))
                        .accessibilityIdentifier("automaticCapture")
                    Text(model.monitor.status).font(.caption).foregroundStyle(.secondary)
                } header: {
                    Text("Clipboard")
                } footer: {
                    Text(
                        "Save text, links, and images automatically while Clipity can access the clipboard, including when you return to the app. Allow Paste from Other Apps in iOS Settings if prompted. Existing capture preferences are preserved on upgrade."
                    )
                }
            }
            if initialSection == nil || initialSection == .background {
                Section {
                    Toggle("Background monitoring", isOn: setting(\.backgroundMonitoring))
                        .disabled(!model.library.settings.automaticCapture)
                        .accessibilityIdentifier("backgroundMonitoring")
                    Text(model.monitor.backgroundStatus).font(.caption).foregroundStyle(.secondary)
                    Button("Open iOS Settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                    }
                } header: {
                    Text("Personal-use background mode")
                } footer: {
                    Text(
                        "Uses location activity to keep the listener running; no coordinates are saved. This uses battery and shows the system location indicator. iOS can still suspend or terminate Clipity. When background clipboard reading is blocked, expand the notification to save the current clipboard before copying something else. Reopen Clipity after force-quitting or restarting your device."
                    )
                }
            }
            if initialSection == nil || initialSection == .notifications {
                Section {
                    Toggle("Clipboard notifications", isOn: setting(\.captureNotifications))
                    Text(model.monitor.notificationStatus).font(.caption).foregroundStyle(.secondary)
                    Button("Enable Notifications") { Task { await model.monitor.requestNotifications() } }
                    if let error = model.monitor.lastError { Text(error).font(.caption).foregroundStyle(.red) }
                } header: {
                    Text("Notifications")
                } footer: {
                    Text(
                        "Successful captures show a saved confirmation. A background change that cannot be read shows an expand-to-save prompt. Notification previews never include clipboard contents."
                    )
                }
            }
            if initialSection == nil || initialSection == .intelligence {
                Section {
                    Toggle("On-device AI labels", isOn: setting(\.aiLabels))
                    Label(
                        SystemLanguageModel.default.isAvailable
                            ? "Apple Intelligence is ready" : "Apple Intelligence is unavailable",
                        systemImage: "sparkles"
                    )
                    .foregroundStyle(.secondary)
                    if model.labeling { ProgressView("Labeling clippings…") }
                    Button("Label unlabeled clippings") { Task { await model.labelPending() } }
                        .disabled(!model.library.settings.aiLabels || model.labeling)
                } header: {
                    Text("Labels")
                } footer: {
                    Text(
                        "Labels are generated locally while Clipity is open. Images use on-device text recognition. Requires a supported device with Apple Intelligence enabled and its model downloaded. There is no cloud fallback. Labels may be inaccurate."
                    )
                }
            }
            if initialSection == nil || initialSection == .history {
                Section("History") {
                    Picker("History limit", selection: setting(\.historyLimit)) {
                        ForEach([25, 50, 100, 250, 500], id: \.self) { Text("\($0) clippings").tag($0) }
                    }
                    Button("Clear unsaved history", role: .destructive) { clear = true }
                }
            }
            if initialSection == nil || initialSection == .privacy {
                Section("Privacy") {
                    Label("Stored on this device", systemImage: "lock.shield")
                    Text(
                        "Clipity skips recognized private-copy markers and likely passwords, tokens, and verification codes. iOS does not identify the source app, and unmarked sensitive copies cannot always be detected. Keep automatic capture off when copying sensitive information."
                    )
                    Text(
                        "Widgets never display clipping text or titles. Shortcuts require authentication. The app hides its content when inactive, and the library uses complete file protection."
                    )
                    Text(
                        "The optional Clipity keyboard reads saved clippings only with Full Access. Clipity makes no network requests."
                    )
                }.font(.subheadline)
            }
        }
        .navigationTitle(initialSection?.rawValue ?? "Settings")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { Button("Done") { dismiss() } }
        .confirmationDialog("Clear all unsaved history?", isPresented: $clear, titleVisibility: .visible) {
            Button("Clear history", role: .destructive) {
                Task { await model.perform { try await ClipStore.shared.clearHistory() } }
            }
        } message: {
            Text("Permanent clippings and folders will be kept.")
        }
    }

    private func setting<Value>(_ keyPath: WritableKeyPath<ClipSettings, Value>) -> Binding<Value> {
        Binding(
            get: { model.library.settings[keyPath: keyPath] },
            set: { value in
                var settings = model.library.settings
                settings[keyPath: keyPath] = value
                model.updateSettings(settings)
            })
    }
}
