import SwiftUI
import UIKit

final class KeyboardViewController: UIInputViewController {
    private var host: UIHostingController<KeyboardContent>?

    override func viewDidLoad() {
        super.viewDidLoad()
        let host = UIHostingController(rootView: content([]))
        self.host = host
        addChild(host)
        view.addSubview(host.view)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            host.view.topAnchor.constraint(equalTo: view.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            view.heightAnchor.constraint(greaterThanOrEqualToConstant: 240),
        ])
        host.didMove(toParent: self)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        Task {
            do {
                let clips = hasFullAccess ? try await ClipStore.shared.snapshot().clips.filter { !$0.text.isEmpty } : []
                host?.rootView = content(Array(clips.prefix(20)))
            } catch { host?.rootView = content([], error: error.localizedDescription) }
        }
    }

    private func content(_ clips: [Clipping], error: String? = nil) -> KeyboardContent {
        KeyboardContent(
            clips: clips, fullAccess: hasFullAccess, error: error,
            insert: { [weak self] text in
                self?.textDocumentProxy.insertText(text)
            }, next: { [weak self] in self?.advanceToNextInputMode() })
    }
}

private struct KeyboardContent: View {
    let clips: [Clipping]
    let fullAccess: Bool
    let error: String?
    let insert: (String) -> Void
    let next: () -> Void
    var body: some View {
        VStack {
            HStack {
                Label("Clipity", systemImage: "clipboard").font(.headline)
                Spacer()
                Button("Next keyboard", systemImage: "globe", action: next)
            }.padding(.horizontal)
            if !fullAccess {
                Text(
                    "Enable Full Access in Keyboard Settings to read your shared Clipity library. Clipity does not use the network."
                ).font(.caption).padding()
            } else if let error {
                Text(error).font(.caption).padding()
            } else if clips.isEmpty {
                Text("Save a text clipping in Clipity to use it here.").foregroundStyle(.secondary).padding()
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading) {
                        ForEach(clips) { clip in
                            Button {
                                insert(clip.text)
                            } label: {
                                Text(clip.displayTitle).lineLimit(2).frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(10)
                            }.buttonStyle(.bordered)
                        }
                    }.padding(.horizontal)
                }
            }
        }.padding(.vertical, 8).tint(ClipTheme.foreground)
    }
}
