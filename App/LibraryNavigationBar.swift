import SwiftUI

struct LibraryNavigationBar: View {
    @Bindable var model: LibraryModel
    @Bindable private var navigation = ClipNavigation.shared
    @Binding var search: String
    @Binding var searching: Bool
    @Binding var collapsed: Bool
    @FocusState private var searchFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var glass

    var body: some View {
        GlassEffectContainer(spacing: 12) {
            VStack(spacing: 10) {
                if searching {
                    HStack(spacing: 10) {
                        Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                        TextField("Search clippings", text: $search)
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                            .submitLabel(.search).focused($searchFocused)
                            .accessibilityIdentifier("clippingSearch")
                        Button("Close search", systemImage: "xmark.circle.fill") {
                            search = ""
                            searching = false
                        }.foregroundStyle(.secondary)
                    }
                    .padding(14)
                    .glassEffect(in: .capsule)
                }
                HStack {
                    if collapsed && !searching {
                        Button {
                            withAnimation(reduceMotion ? nil : .snappy(duration: 0.2)) { collapsed = false }
                        } label: {
                            Image(systemName: navigation.selection == "history" ? "house" : "folder")
                                .font(.title3).frame(width: 54, height: 54)
                        }
                        .accessibilityLabel("Show navigation")
                        .glassEffect(.regular.interactive(), in: .circle)
                        .glassEffectID("navigation", in: glass)
                        Spacer()
                    } else {
                        HStack(spacing: 2) {
                            Menu {
                                Button("History", systemImage: "clock") { selectHistory() }
                                Button("All saved", systemImage: "bookmark") {
                                    navigation.selection = "saved"
                                    searching = false
                                    search = ""
                                }
                                ForEach(model.library.folders) { folder in
                                    Button(folder.name, systemImage: "folder") {
                                        navigation.selection = folder.id.uuidString
                                        searching = false
                                        search = ""
                                    }
                                }
                            } label: {
                                item(
                                    "Folders", icon: "folder", selected: !searching && navigation.selection != "history"
                                )
                            } primaryAction: {
                                navigation.path.append(.folders)
                            }
                            .accessibilityIdentifier("collectionPicker")

                            Menu {
                                Button("Save Clipboard", systemImage: "plus.square.on.square") {
                                    Task { await model.capture() }
                                }
                                Button("Add Clip with AI", systemImage: "sparkles") {
                                    Task { await model.handle(.addAI) }
                                }
                                Button("Write a clipping", systemImage: "square.and.pencil") {
                                    navigation.path.append(.compose)
                                }
                            } label: {
                                item(
                                    "History", icon: "house", selected: !searching && navigation.selection == "history")
                            } primaryAction: {
                                selectHistory()
                            }

                            Button {
                                searching = true
                                collapsed = false
                                searchFocused = true
                            } label: {
                                item("Search", icon: "magnifyingglass", selected: searching)
                            }

                            Menu {
                                ForEach(SettingsSection.allCases) { section in
                                    Button(section.rawValue) { navigation.path.append(.settings(section)) }
                                }
                            } label: {
                                item("Settings", icon: "gearshape", selected: false)
                            } primaryAction: {
                                navigation.path.append(.settings(nil))
                            }
                        }
                        .buttonStyle(.plain)
                        .padding(6)
                        .glassEffect(.regular.interactive(), in: .capsule)
                        .glassEffectID("navigation", in: glass)
                    }
                }
            }
        }
        .padding(.horizontal, 16).padding(.bottom, 8).padding(.top, 4)
        .onChange(of: searching) { _, value in searchFocused = value }
    }

    private func item(_ title: String, icon: String, selected: Bool) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon).font(.system(size: 22, weight: .medium))
            Text(title).font(.caption2.weight(selected ? .semibold : .medium)).lineLimit(1)
        }
        .foregroundStyle(.primary)
        .frame(maxWidth: .infinity).frame(minHeight: 52)
        .padding(.horizontal, 4)
        .background(selected ? Color.primary.opacity(0.1) : .clear, in: .capsule)
        .contentShape(.capsule)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func selectHistory() {
        navigation.selection = "history"
        search = ""
        searching = false
    }
}
