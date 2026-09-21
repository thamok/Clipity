import SwiftUI
import WidgetKit

struct ClipEntry: TimelineEntry {
    let date: Date
}

struct ClipProvider: TimelineProvider {
    func placeholder(in context: Context) -> ClipEntry { ClipEntry(date: .now) }
    func getSnapshot(in context: Context, completion: @escaping (ClipEntry) -> Void) {
        completion(ClipEntry(date: .now))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<ClipEntry>) -> Void) {
        // Deliberately do not read the library: no private content enters WidgetKit's snapshot cache.
        completion(Timeline(entries: [ClipEntry(date: .now)], policy: .never))
    }
}

struct ClipWidgetView: View {
    @Environment(\.widgetFamily) private var family
    var body: some View {
        Group {
            switch family {
            case .accessoryCircular:
                Image(systemName: "clipboard.fill").font(.title2).accessibilityLabel("Open Clipity")
            case .accessoryInline:
                Label("Open Clipity", systemImage: "clipboard")
            case .accessoryRectangular:
                VStack(alignment: .leading) {
                    Label("Clipity", systemImage: "clipboard.fill").font(.headline)
                    Text("Your ideas, kept close").font(.caption)
                }
            default:
                VStack(alignment: .leading, spacing: 12) {
                    Image(systemName: "clipboard.fill").font(.largeTitle).foregroundStyle(ClipTheme.foreground)
                    Spacer(minLength: 0)
                    Text("Clipity").font(.title2.bold())
                    Text("Open your clippings").font(.subheadline).foregroundStyle(.secondary)
                    Label("Content stays private", systemImage: "lock.fill").font(.caption2).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .containerBackground(.background, for: .widget)
        .widgetURL(URL(string: "clipity://library"))
    }
}

@main
struct ClipWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "ClipityLibrary", provider: ClipProvider()) { _ in ClipWidgetView() }
            .configurationDisplayName("Clipity")
            .description("Open your library without exposing clipboard content.")
            .supportedFamilies([
                .systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular, .accessoryInline,
            ])
    }
}
