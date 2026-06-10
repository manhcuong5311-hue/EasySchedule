//
//  WeekGlanceView.swift
//  Easy Schedule
//
//  A week-at-a-glance strip that lives *behind* the day card and is revealed by
//  dragging the card down (mirrors Structify's WeekTimelineView). Events for the
//  7 days of the selected week are grouped into Morning / Noon / Night periods;
//  each period shows a row of coloured badges per day column.
//

import SwiftUI

// MARK: - Period buckets

private enum WeekGlancePeriod: Int, CaseIterable {
    case morning    // < 12:00
    case afternoon  // 12:00 – 18:00
    case night      // ≥ 18:00

    var icon: String {
        switch self {
        case .morning:   return "sunrise.fill"
        case .afternoon: return "sun.max.fill"
        case .night:     return "moon.fill"
        }
    }

    var label: String {
        switch self {
        case .morning:   return String(localized: "glance_morning")
        case .afternoon: return String(localized: "glance_noon")
        case .night:     return String(localized: "glance_night")
        }
    }

    var color: Color {
        switch self {
        case .morning:   return .orange
        case .afternoon: return .yellow
        case .night:     return .indigo
        }
    }

    func contains(minutes: Int) -> Bool {
        switch self {
        case .morning:   return minutes < 720
        case .afternoon: return minutes >= 720 && minutes < 1080
        case .night:     return minutes >= 1080
        }
    }
}

// MARK: - WeekGlanceView

struct WeekGlanceView: View {

    @Binding var selectedDate: Date
    /// Tapping a day column selects that date (and lets the parent collapse the card).
    var onSelectDate: (Date) -> Void

    @EnvironmentObject var eventManager: EventManager
    @Environment(\.colorScheme) private var scheme

    private let badgeSize: CGFloat = 26
    private let badgeGap: CGFloat = 3
    private let periodHeaderHeight: CGFloat = 26

    // MARK: - Week dates (week containing the selected date)

    private var weekDates: [Date] {
        var cal = Calendar.current
        cal.firstWeekday = 2   // Monday first, aligned with the day picker above
        let start = cal.dateInterval(of: .weekOfYear, for: selectedDate)?.start
            ?? selectedDate
        return (0..<7).compactMap { cal.date(byAdding: .day, value: $0, to: start) }
    }

    // MARK: - Data

    // Planning strip: only today and later show badges. Past days pull from the
    // local archive (including events since deleted elsewhere), which resurfaces
    // as unrecognizable grey dots — so past columns stay empty instead.
    private func events(for date: Date) -> [CalendarEvent] {
        let cal = Calendar.current
        guard cal.startOfDay(for: date) >= cal.startOfDay(for: Date()) else { return [] }
        return eventManager.events(for: date)
            .filter { $0.origin != .busySlot }
            .sorted { $0.startMinutes < $1.startMinutes }
    }

    private func events(for date: Date, period: WeekGlancePeriod) -> [CalendarEvent] {
        events(for: date).filter { period.contains(minutes: $0.startMinutes) }
    }

    private func maxBadgeCount(for period: WeekGlancePeriod) -> Int {
        weekDates.reduce(0) { max($0, events(for: $1, period: period).count) }
    }

    // MARK: - Body

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(WeekGlancePeriod.allCases, id: \.rawValue) { period in
                    periodSection(period: period)
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .padding(.horizontal, 8)        // align columns with the day picker above
        .padding(.top, 6)
        .padding(.bottom, 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    // MARK: - Period section

    @ViewBuilder
    private func periodSection(period: WeekGlancePeriod) -> some View {
        let rowCount = maxBadgeCount(for: period)

        VStack(alignment: .leading, spacing: 2) {
            // Period header: icon + label
            HStack(spacing: 6) {
                Image(systemName: period.icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(period.color)

                Text(period.label)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(period.color)
            }
            .padding(.leading, 2)
            .padding(.vertical, 3)
            .frame(height: periodHeaderHeight)

            if rowCount > 0 {
                ForEach(0..<rowCount, id: \.self) { rowIndex in
                    HStack(spacing: 0) {
                        ForEach(weekDates, id: \.self) { date in
                            let dayEvents = events(for: date, period: period)

                            ZStack {
                                if rowIndex < dayEvents.count {
                                    badgeView(event: dayEvents[rowIndex])
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: badgeSize)
                            .contentShape(Rectangle())
                            .onTapGesture { onSelectDate(date) }
                        }
                    }
                }
            } else {
                // Keep the period readable even with no events.
                Text(String(localized: "glance_no_events"))
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .padding(.leading, 4)
                    .frame(height: badgeSize * 0.7)
            }
        }
    }

    // MARK: - Badge

    // Custom icon first (same resolution as the day picker), falling back to
    // the origin glyph.
    private func badgeIcon(for event: CalendarEvent) -> String {
        EventIconStore.shared.icon(for: event.id) ?? event.originIcon
    }

    @ViewBuilder
    private func badgeView(event: CalendarEvent) -> some View {
        let color = event.eventColor

        ZStack {
            Circle()
                .fill(color.opacity(scheme == .dark ? 0.25 : 0.15))
                .overlay(Circle().stroke(color.opacity(0.4), lineWidth: 1.2))

            Image(systemName: badgeIcon(for: event))
                .font(.system(size: badgeSize * 0.4, weight: .semibold))
                .foregroundStyle(color)
        }
        .frame(width: badgeSize, height: badgeSize)
        .shadow(color: color.opacity(0.18), radius: 2, y: 1)
    }
}
