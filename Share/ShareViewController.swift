import SwiftUI
import UIKit
import WidgetKit

final class ShareViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        let providers = (extensionContext?.inputItems as? [NSExtensionItem] ?? []).flatMap { $0.attachments ?? [] }
        let host = UIHostingController(
            rootView: ShareForm(providers: providers) { [weak self] in
                self?.extensionContext?.completeRequest(returningItems: nil)
            } cancel: { [weak self] in
                self?.extensionContext?.cancelRequest(withError: CocoaError(.userCancelled))
            })
        addChild(host)
        view.addSubview(host.view)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            host.view.topAnchor.constraint(equalTo: view.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        host.didMove(toParent: self)
    }
}

private struct ShareForm: View {
    let providers: [NSItemProvider]
    let complete: () -> Void
    let cancel: () -> Void
    @State private var clips: [Clipping] = []
    @State private var folders: [ClipFolder] = []
    @State private var title = ""
    @State private var saved = false
    @State private var folderID: UUID?
    @State private var newFolder = ""
    @State private var error: String?
    @State private var busy = true

    var body: some View {
        NavigationStack {
            Form {
                if busy { ProgressView("Preparing…") }
                if let error { Text(error).foregroundStyle(.red) }
                Section("Save to Clipity") {
                    ForEach(clips) { clip in Text(clip.displayTitle).lineLimit(4) }
                    TextField("Title (optional)", text: $title)
                    Toggle("Keep permanently", isOn: $saved)
                    if saved {
                        Picker("Folder", selection: $folderID) {
                            Text("Unfiled").tag(nil as UUID?)
                            ForEach(folders) { Text($0.name).tag(Optional($0.id)) }
                        }
                        HStack {
                            TextField("New folder", text: $newFolder)
                            Button("Create") {
                                Task {
                                    do {
                                        folderID = try await ClipStore.shared.folder(name: newFolder).id
                                        folders = try await ClipStore.shared.snapshot().folders
                                        newFolder = ""
                                    } catch { self.error = error.localizedDescription }
                                }
                            }.disabled(newFolder.nilIfBlank == nil)
                        }
                    }
                }
                Text(
                    "Private-copy markers and likely secrets are rejected. If enabled, AI labels are added next time you open Clipity."
                ).font(.caption).foregroundStyle(.secondary)
            }
            .navigationTitle("Clipity")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel", action: cancel) }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task {
                            busy = true
                            defer { busy = false }
                            do {
                                let items = clips.map { original in
                                    var clip = original
                                    clip.title = title.nilIfBlank
                                    clip.isSaved = saved
                                    clip.folderID = saved ? folderID : nil
                                    return clip
                                }
                                _ = try await ClipStore.shared.addBatch(items)
                                WidgetCenter.shared.reloadAllTimelines()
                                complete()
                            } catch { self.error = error.localizedDescription }
                        }
                    }.disabled(busy || clips.isEmpty)
                }
            }
            .task {
                defer { busy = false }
                do {
                    clips = try await ContentLoader.load(providers)
                    folders = try await ClipStore.shared.snapshot().folders
                } catch { self.error = error.localizedDescription }
            }
        }.tint(ClipTheme.foreground)
    }
}
