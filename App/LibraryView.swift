import SwiftUI

struct LibraryView: View {
    @Bindable var model: LibraryModel
    @State private var search = ""
    @State private var searching = false
    @State private var barCollapsed = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var sharing: Clipping?
    @Bindable private var navigation = ClipNavigation.shared

    private var clips: [Clipping] {
        let selected = model.library.clips.filter { clip in
            let included =
                navigation.selection == "recent"
                || (navigation.selection == "history"
                    ? !clip.isSaved
                    : navigation.selection == "saved"
                        ? clip.isSaved : clip.folderID?.uuidString == navigation.selection)
            return included
                && (search.isEmpty
                    || [clip.text, clip.title ?? "", clip.filename ?? "", clip.labels.joined(separator: " ")].contains {
                        $0.localizedCaseInsensitiveContains(search)
                    })
        }
        return navigation.selection == "recent" ? Array(selected.prefix(3)) : selected
    }
    private var title: String {
        switch navigation.selection {
        case "history": "History"
        case "saved": "Saved"
        case "recent": "Last 3 clips"
        default: model.library.folders.first { $0.id.uuidString == navigation.selection }?.name ?? "History"
        }
    }

    var body: some View {
        NavigationStack(path: $navigation.path) {
            List {
                Section {
                    if model.loading {
                        ProgressView("Opening library…")
                    } else if clips.isEmpty {
                        ContentUnavailableView(
                            search.isEmpty ? "Room for your next idea" : "No matching clippings", systemImage: "tray",
                            description: Text(
                                search.isEmpty
                                    ? "Save your clipboard, write a note, or choose Clipity in another app’s share sheet."
                                    : "Try another word or collection."))
                    }
                    ForEach(clips) { clip in
                        Button {
                            navigation.path.append(.detail(clip.id))
                        } label: {
                            ClipRow(clip: clip)
                        }
                        .buttonStyle(.plain)
                        .highPriorityGesture(LongPressGesture(minimumDuration: 0.4).onEnded { _ in share(clip) })
                        .swipeActions(edge: .leading, allowsFullSwipe: true) {
                            Button("Copy", systemImage: "doc.on.doc") { Task { await model.copy(clip) } }.tint(
                                ClipTheme.accent)
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button("Delete", systemImage: "trash", role: .destructive) {
                                Task { await model.perform { try await ClipStore.shared.delete(id: clip.id) } }
                            }
                            Button("Organize", systemImage: "folder") { navigation.path.append(.organize(clip.id)) }
                                .tint(ClipTheme.accent)
                        }
                        .accessibilityAction(named: "Share") { share(clip) }
                        .accessibilityAction(named: "Copy") { Task { await model.copy(clip) } }
                        .accessibilityAction(named: "Organize") { navigation.path.append(.organize(clip.id)) }
                    }
                } header: {
                    HStack {
                        Text("\(clips.count) clippings")
                        Spacer()
                        Image(systemName: model.library.settings.automaticCapture ? "waveform" : "pause.circle")
                            .accessibilityLabel(model.monitor.status)
                    }
                }
            }
            .navigationTitle(title)
            .navigationDestination(for: ClipRoute.self) { route in
                switch route {
                case .detail(let id): ClipDetailView(clipID: id, model: model)
                case .organize(let id):
                    if let clip = model.library.clips.first(where: { $0.id == id }) {
                        ClipEditor(model: model, clip: clip)
                    } else {
                        ContentUnavailableView("Clipping removed", systemImage: "tray")
                    }
                case .compose: ClipEditor(model: model)
                case .folders: FolderManagerView(model: model)
                case .settings(let section): SettingsView(model: model, initialSection: section)
                }
            }
            .onScrollGeometryChange(for: Int.self) { geometry in
                Int(max(0, geometry.contentOffset.y + geometry.contentInsets.top) / 80)
            } action: { old, new in
                guard !searching else { return }
                withAnimation(reduceMotion ? nil : .snappy(duration: 0.2)) { barCollapsed = new > old && new > 1 }
            }
            .refreshable { await model.refresh() }
            .overlay(alignment: .top) {
                if let notice = model.notice {
                    Text(notice).font(.callout).padding(.horizontal, 16).padding(.vertical, 10)
                        .glassEffect(in: .capsule).padding(.top, 8)
                        .accessibilityIdentifier("captureStatus").allowsHitTesting(false)
                }
            }
            .task(id: model.notice) {
                guard model.notice != nil else { return }
                do {
                    try await Task.sleep(for: .seconds(3))
                    model.notice = nil
                } catch {}
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                LibraryNavigationBar(model: model, search: $search, searching: $searching, collapsed: $barCollapsed)
            }
            .sheet(item: $sharing) { ShareActivity(clip: $0) }
            .alert(
                "Couldn’t complete that",
                isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })
            ) {
                Button("OK") { model.error = nil }
            } message: {
                Text(model.error ?? "")
            }
        }
        .onChange(of: navigation.quickAction, initial: true) { _, _ in processQuickAction() }
        .onChange(of: scenePhase) { _, phase in if phase == .active { processQuickAction() } }
    }

    private func processQuickAction() {
        guard scenePhase == .active, let action = navigation.quickAction else { return }
        navigation.quickAction = nil
        search = ""
        searching = false
        barCollapsed = false
        Task { await model.handle(action) }
    }

    private func share(_ clip: Clipping) {
        Task {
            do { sharing = try await ClipStore.shared.hydrated(clip) } catch {
                model.error = error.localizedDescription
            }
        }
    }
}

private struct ClipRow: View {
    let clip: Clipping
    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            if clip.hasImage {
                ClipThumbnail(clip: clip)
            } else {
                Image(systemName: clip.hasFile ? "doc" : clip.kind == "Link" ? "link" : "text.alignleft")
                    .font(.title3).foregroundStyle(ClipTheme.foreground).frame(width: 36, height: 40)
                    .background(ClipTheme.accent.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
            }
            VStack(alignment: .leading, spacing: 6) {
                Text(clip.displayTitle).font(clip.title?.nilIfBlank == nil ? .body : .headline).foregroundStyle(
                    .primary
                ).lineLimit(4)
                if clip.title != nil && !clip.text.isEmpty {
                    Text(clip.text).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
                }
                HStack {
                    Text(clip.kind)
                    Text(clip.date, style: .relative)
                    if clip.isSaved { Image(systemName: "bookmark.fill").accessibilityLabel("Saved permanently") }
                }.font(.caption).foregroundStyle(.secondary)
                if !clip.labels.isEmpty {
                    Text(clip.labels.joined(separator: " · ")).font(.caption).foregroundStyle(ClipTheme.foreground)
                }
            }
        }.padding(.vertical, 6)
    }
}

private struct ClipDetailView: View {
    let clipID: UUID
    @Bindable var model: LibraryModel
    @State private var share = false
    @State private var confirmDelete = false
    @State private var hydrated: Clipping?
    @Environment(\.dismiss) private var dismiss
    private var clip: Clipping? { model.library.clips.first { $0.id == clipID } }

    var body: some View {
        Group {
            if let clip {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        if let title = clip.title { Text(title).font(.largeTitle.bold()) }
                        if clip.hasFile {
                            Label(clip.filename ?? "File", systemImage: "doc")
                                .font(.headline)
                            Text(clip.contentType.localizedDescription ?? "File").foregroundStyle(.secondary)
                        }
                        if let data = hydrated?.image, let image = UIImage(data: data) {
                            Image(uiImage: image).resizable().scaledToFit().clipShape(
                                RoundedRectangle(cornerRadius: 16))
                        }
                        if !clip.text.isEmpty {
                            Text(clip.text).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                        }
                        if !clip.labels.isEmpty {
                            Label(clip.labels.joined(separator: " · "), systemImage: "sparkles").foregroundStyle(
                                ClipTheme.foreground)
                        }
                        Text(clip.date.formatted()).font(.caption).foregroundStyle(.secondary)
                        if clip.isSaved { Label("Kept permanently", systemImage: "bookmark.fill").font(.caption) }
                    }.padding()
                }
                .toolbar {
                    ToolbarItemGroup(placement: .bottomBar) {
                        Button("Copy", systemImage: "doc.on.doc") { Task { await model.copy(clip) } }
                        Spacer()
                        Button("Share", systemImage: "square.and.arrow.up") { share = true }.disabled(
                            (clip.hasImage || clip.hasFile) && hydrated == nil)
                        Spacer()
                        Button("Organize", systemImage: "folder") {
                            ClipNavigation.shared.path.append(.organize(clip.id))
                        }
                        Spacer()
                        Button("Delete", systemImage: "trash", role: .destructive) { confirmDelete = true }
                    }
                }
                .sheet(isPresented: $share) { ShareActivity(clip: hydrated ?? clip) }
                .task(id: clip.id) {
                    do { hydrated = try await ClipStore.shared.hydrated(clip) } catch {
                        model.error = error.localizedDescription
                    }
                }
            } else {
                ContentUnavailableView("Clipping removed", systemImage: "tray")
            }
        }
        .navigationTitle("Clipping").navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Delete this clipping permanently?", isPresented: $confirmDelete, titleVisibility: .visible)
        {
            Button("Delete", role: .destructive) {
                Task {
                    await model.perform { try await ClipStore.shared.delete(id: clipID) }
                    if model.error == nil { dismiss() }
                }
            }
        }
    }
}

struct ShareActivity: UIViewControllerRepresentable {
    let clip: Clipping
    func makeUIViewController(context: Context) -> UIActivityViewController {
        if let file = clip.fileData {
            let provider = NSItemProvider()
            provider.suggestedName = clip.filename
            provider.registerDataRepresentation(forTypeIdentifier: clip.contentType.identifier, visibility: .all) {
                completion in
                completion(file, nil)
                return nil
            }
            let controller = UIActivityViewController(activityItems: [], applicationActivities: nil)
            controller.activityItemsConfiguration = UIActivityItemsConfiguration(itemProviders: [provider])
            return controller
        }
        let item: Any = clip.image.flatMap(UIImage.init(data:)) ?? (clip.text as Any)
        return UIActivityViewController(activityItems: [item], applicationActivities: nil)
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
