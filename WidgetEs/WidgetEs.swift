//
//  WidgetEs.swift
//  WidgetEs (widget target)
//
//  Widget màn hình chính + màn khoá: hiện "việc đang/sắp diễn ra".
//  Đọc snapshot do app ghi vào App Group; timeline tự refresh ở mỗi mốc event.
//
import WidgetKit
import SwiftUI

// MARK: - Entry
struct NextEventEntry: TimelineEntry {
    let date: Date
    let current: ScheduleSnapshotItem?
    let next: ScheduleSnapshotItem?
    let upcoming: [ScheduleSnapshotItem]

    /// Việc cần làm nổi bật: đang diễn ra > sắp tới.
    var focus: ScheduleSnapshotItem? { current ?? next }
    var focusIsNow: Bool { current != nil }
}

// MARK: - Provider
struct NextEventProvider: TimelineProvider {
    func placeholder(in context: Context) -> NextEventEntry {
        NextEventEntry(date: Date(), current: nil, next: .sample, upcoming: [.sample])
    }

    func getSnapshot(in context: Context, completion: @escaping (NextEventEntry) -> Void) {
        completion(entry(from: SharedStore.readSnapshot(), at: Date()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<NextEventEntry>) -> Void) {
        let now = Date()
        let snap = SharedStore.readSnapshot()

        var dates: [Date] = [now]
        dates.append(contentsOf: snap.refreshDates(after: now))
        dates.append(now.addingTimeInterval(30 * 60))          // sàn refresh 30'
        let points = Array(Set(dates)).sorted().prefix(12)

        let entries = points.map { entry(from: snap, at: $0) }
        let reload = points.last ?? now.addingTimeInterval(3600)
        completion(Timeline(entries: entries, policy: .after(reload)))
    }

    private func entry(from snap: ScheduleSnapshot, at date: Date) -> NextEventEntry {
        NextEventEntry(date: date,
                       current: snap.current(at: date),
                       next: snap.next(at: date),
                       upcoming: snap.upcoming(at: date, limit: 3))
    }
}

extension ScheduleSnapshotItem {
    static var sample: ScheduleSnapshotItem {
        let now = Date()
        return ScheduleSnapshotItem(id: "sample", title: "Team Standup",
                                    start: now.addingTimeInterval(15 * 60),
                                    end: now.addingTimeInterval(45 * 60),
                                    colorHex: "#007AFF")
    }
}

// MARK: - Widget
struct NextEventWidget: Widget {
    let kind = "NextEventWidget"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: NextEventProvider()) { entry in
            NextEventWidgetView(entry: entry)
        }
        .configurationDisplayName(WidgetStrings.widgetName)
        .description(WidgetStrings.widgetDesc)
        .supportedFamilies([.systemSmall, .systemMedium,
                            .accessoryRectangular, .accessoryInline])
    }
}

// MARK: - Root view
struct NextEventWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: NextEventEntry

    var body: some View {
        switch family {
        case .systemMedium:         MediumWidgetView(entry: entry)
        case .accessoryRectangular: RectAccessoryView(entry: entry)
        case .accessoryInline:      InlineAccessoryView(entry: entry)
        default:                    SmallWidgetView(entry: entry)
        }
    }
}

// MARK: - Small
struct SmallWidgetView: View {
    let entry: NextEventEntry
    var body: some View {
        Group {
            if let item = entry.focus {
                VStack(alignment: .leading, spacing: 4) {
                    LabelRow(item: item, isNow: entry.focusIsNow)
                    Text(item.title).font(.headline).lineLimit(2).minimumScaleFactor(0.8)
                    Spacer(minLength: 0)
                    if entry.focusIsNow {
                        countdown(to: item.end, prefix: WidgetStrings.endsIn)
                    } else {
                        Text(item.start, style: .time).font(.subheadline.weight(.semibold))
                        Text(item.start, style: .relative).font(.caption2).foregroundStyle(.secondary)
                    }
                }
            } else {
                EmptyScheduleView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .padding(14)
        .containerBackground(for: .widget) { Color(uiColor: .systemBackground) }
    }
}

// MARK: - Medium
struct MediumWidgetView: View {
    let entry: NextEventEntry
    var body: some View {
        Group {
            if let item = entry.focus {
                HStack(alignment: .top, spacing: 14) {
                    focusColumn(item)
                    if !laterItems.isEmpty {
                        Divider()
                        upcomingColumn
                    }
                }
            } else {
                EmptyScheduleView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .padding(14)
        .containerBackground(for: .widget) { Color(uiColor: .systemBackground) }
    }

    private var laterItems: [ScheduleSnapshotItem] {
        let focusID = entry.focus?.id
        return entry.upcoming.filter { $0.id != focusID }
    }

    private func focusColumn(_ item: ScheduleSnapshotItem) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            LabelRow(item: item, isNow: entry.focusIsNow)
            Text(item.title).font(.headline).lineLimit(2)
            if entry.focusIsNow {
                countdown(to: item.end, prefix: WidgetStrings.endsIn)
            } else {
                Text(item.start, style: .time).font(.subheadline.weight(.semibold))
                Text(item.start, style: .relative).font(.caption2).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var upcomingColumn: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(WidgetStrings.today.uppercased())
                .font(.caption2.weight(.bold)).foregroundStyle(.secondary)
            ForEach(Array(laterItems.prefix(3))) { item in
                HStack(spacing: 6) {
                    RoundedRectangle(cornerRadius: 2).fill(item.color).frame(width: 3, height: 22)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(item.title).font(.caption.weight(.medium)).lineLimit(1)
                        Text(item.start, style: .time).font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Lock screen accessories
struct RectAccessoryView: View {
    let entry: NextEventEntry
    var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .containerBackground(for: .widget) { Color.clear }
    }
    @ViewBuilder private var content: some View {
        if let item = entry.focus {
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.focusIsNow ? WidgetStrings.now : WidgetStrings.next)
                    .font(.caption2.weight(.bold))
                Text(item.title).font(.headline).lineLimit(1)
                if entry.focusIsNow {
                    Text(timerInterval: timerRange(to: item.end), countsDown: true).font(.caption2)
                } else {
                    Text(item.start, style: .time).font(.caption2)
                }
            }
        } else {
            Label(WidgetStrings.noEvents, systemImage: "checkmark.circle")
        }
    }
}

struct InlineAccessoryView: View {
    let entry: NextEventEntry
    var body: some View {
        if let item = entry.focus {
            Label {
                Text(item.title)
            } icon: {
                Image(systemName: entry.focusIsNow ? "circle.fill" : "calendar")
            }
        } else {
            Label(WidgetStrings.noEvents, systemImage: "checkmark.circle")
        }
    }
}

// MARK: - Shared pieces
struct LabelRow: View {
    let item: ScheduleSnapshotItem
    let isNow: Bool
    var body: some View {
        HStack(spacing: 5) {
            Circle().fill(item.color).frame(width: 8, height: 8)
            Text(isNow ? WidgetStrings.now : WidgetStrings.next)
                .font(.caption2.weight(.bold))
                .foregroundStyle(item.color)
        }
    }
}

struct EmptyScheduleView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Image(systemName: "checkmark.circle.fill").font(.title3).foregroundStyle(.green)
            Text(WidgetStrings.free).font(.headline)
            Text(WidgetStrings.noEvents).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

/// Khoảng thời gian hợp lệ cho `Text(timerInterval:)` (lowerBound ≤ upperBound).
func timerRange(to date: Date) -> ClosedRange<Date> {
    let now = Date()
    return now...max(date, now.addingTimeInterval(1))
}

@ViewBuilder
func countdown(to date: Date, prefix: String) -> some View {
    HStack(spacing: 4) {
        Text(prefix).font(.caption2).foregroundStyle(.secondary)
        Text(timerInterval: timerRange(to: date), countsDown: true)
            .font(.subheadline.weight(.semibold).monospacedDigit())
    }
}
