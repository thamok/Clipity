import SwiftUI

struct ClipEditor: View {
    @Bindable var model: LibraryModel
    var clip: Clipping?
    @State private var title = ""
    @State private var text = ""
    @State private var saved = true
    @State private var folderID: UUID?
    @State private var newFolder = ""
    @State private var generating = false
    @State private var generationTask: Task<Void, Never>?
    @State private var busy = false
    @State private var error: String?
    @Environment(\.dismiss) private var dismiss

    init(model: LibraryModel, clip: Clipping? = nil) {
        self.model = model
        self.clip = clip
        _title = State(initialValue: clip?.title ?? "")
        _folderID = State(initialValue: clip?.folderID)
        _saved = State(initialValue: true)
    }

    var body: some View {
        Form {
            Section("Clipping") {
                HStack {
                    TextField("Title (optional)", text: $title)
                    Button {
                        generateTitle()
                    } label: {
                        if generating { ProgressView() } else { Image(systemName: "sparkles") }
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Generate title")
                    .disabled(generating || (clip == nil && text.nilIfBlank == nil))
                }
                if clip == nil {
                    TextEditor(text: $text).frame(minHeight: 160).accessibilityLabel("Clipping text")
                } else {
                    Text(clip?.displayTitle ?? "").lineLimit(3).foregroundStyle(.secondary)
                }
            }
            Section {
                Toggle("Keep permanently", isOn: $saved)
                if saved {
                    Picker("Folder", selection: $folderID) {
                        Text("Unfiled").tag(nil as UUID?)
                        ForEach(model.library.folders) { Text($0.name).tag(Optional($0.id)) }
                    }
                    .accessibilityIdentifier("folderPicker")
                    HStack {
                        TextField("New folder", text: $newFolder)
                        Button("Create") {
                            Task {
                                do {
                                    folderID = try await ClipStore.shared.folder(name: newFolder).id
                                    newFolder = ""
                                    await model.refresh()
                                } catch { self.error = error.localizedDescription }
                            }
                        }.disabled(newFolder.nilIfBlank == nil)
                    }
                }
            } footer: {
                Text("Permanent clippings are never removed by the history limit. Titles are optional.")
            }
        }
        .navigationTitle(clip == nil ? "New clipping" : "Organize clipping")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { Task { await save() } }.disabled(busy || (clip == nil && text.nilIfBlank == nil))
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear { generationTask?.cancel() }
        .alert("Couldn’t save", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK") { error = nil }
        } message: {
            Text(error ?? "")
        }
        .deferAutomaticCaptureWhileEditing()
    }

    private func generateTitle() {
        let originalTitle = title
        let input = clip ?? Clipping(text: text)
        generating = true
        generationTask = Task {
            defer { generating = false }
            do {
                let hydrated = try await ClipStore.shared.hydrated(input)
                let generated = try await ClipTitleGenerator.title(for: hydrated)
                try Task.checkCancellation()
                if title == originalTitle { title = generated }
            } catch is CancellationError {} catch { self.error = error.localizedDescription }
        }
    }

    private func save() async {
        busy = true
        defer { busy = false }
        do {
            if let clip {
                try await ClipStore.shared.update(id: clip.id, title: title, folderID: folderID, saved: saved)
            } else {
                try await ClipStore.shared.add(text: text, title: title, folderID: saved ? folderID : nil, saved: saved)
            }
            await model.perform {}
            dismiss()
            await model.labelPending()
        } catch { self.error = error.localizedDescription }
    }
}

struct FolderManagerView: View {
    @Bindable var model: LibraryModel
    @State private var name = ""
    @State private var renaming: ClipFolder?
    @State private var rename = ""
    @State private var deleting: ClipFolder?
    @State private var error: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Form {
            Section("Collections") {
                Button("History", systemImage: "clock") { select("history") }
                Button("All saved", systemImage: "bookmark") { select("saved") }
            }
            Section("Create a folder") {
                TextField("Folder name", text: $name)
                Button("Create", systemImage: "folder.badge.plus") {
                    Task {
                        do {
                            try await ClipStore.shared.folder(name: name)
                            name = ""
                            await model.refresh()
                        } catch { self.error = error.localizedDescription }
                    }
                }.disabled(name.nilIfBlank == nil)
            }
            Section {
                ForEach(model.library.folders) { folder in
                    HStack {
                        Button(folder.name, systemImage: "folder") { select(folder.id.uuidString) }
                            .buttonStyle(.borderless)
                        Spacer()
                        Menu {
                            Button("Rename") {
                                rename = folder.name
                                renaming = folder
                            }
                            Button("Delete folder", role: .destructive) { deleting = folder }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }.accessibilityLabel("Manage \(folder.name)")
                    }
                }
            } footer: {
                Text("Deleting a folder keeps its clippings permanently in All saved.")
            }
        }
        .navigationTitle("Folders")
        .toolbar { Button("Done") { dismiss() } }
        .deferAutomaticCaptureWhileEditing()
        .alert("Rename folder", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Name", text: $rename)
            Button("Save") {
                let id = renaming?.id
                Task {
                    do {
                        try await ClipStore.shared.folder(name: rename, id: id)
                        await model.refresh()
                    } catch { self.error = error.localizedDescription }
                }
            }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog(
            "Delete folder? Saved clippings will be kept.",
            isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
            titleVisibility: .visible
        ) {
            if let folder = deleting {
                Button("Delete folder", role: .destructive) {
                    Task { await model.perform { try await ClipStore.shared.deleteFolder(id: folder.id) } }
                }
            }
        }
        .alert("Couldn’t update folder", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK") { error = nil }
        } message: {
            Text(error ?? "")
        }
    }

    private func select(_ selection: String) {
        ClipNavigation.shared.selection = selection
        dismiss()
    }
}
