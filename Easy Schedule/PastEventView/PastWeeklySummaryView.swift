//
//  PastWeeklySummaryView.swift
//  Easy Schedule
//
//  Created by Sam Manh Cuong on 23/1/26.
//
import SwiftUI
import Combine

struct PastWeeklySummaryView: View {

    @EnvironmentObject var eventManager: EventManager
    @Environment(\.dismiss) private var dismiss

    let week: (year: Int, week: Int)

    @State private var cachedEventsByWeek: [String: [CalendarEvent]] = [:]
    @State private var cachedStats: WeeklyStats?

    @State private var isLoading = true
    @State private var mode: SummaryMode = .week

    @State private var cachedEvents: [CalendarEvent] = []
   
    @State private var cachedComparison: WeeklyComparison?

    
    private var events: [CalendarEvent] {
        cachedEvents
    }


    private var stats: WeeklyStats {
        cachedStats ?? .empty
    }

//MONTH CACHEEE
    
    private var eventsByMonth: [String: [CalendarEvent]] {
        cachedEventsByMonth
    }

    
    @State private var cachedEventsByMonth: [String: [CalendarEvent]] = [:]

    private var monthTitle: String {
        guard
            let weekStart = Calendar.current.date(
                from: DateComponents(
                    weekOfYear: week.week,
                    yearForWeekOfYear: week.year
                )
            )
        else { return "" }

        let formatter = DateFormatter()
           formatter.locale = .current
           formatter.dateFormat = "LLLL yyyy"
           return formatter.string(from: weekStart)
    }
    private func rebuildStats() {
        cachedStats = WeeklyStatsBuilder.build(events: cachedEvents)
    }

    private func previousWeekSafe() -> (year: Int, week: Int)? {
        let calendar = Calendar.current

        guard let currentWeekDate = calendar.date(
            from: DateComponents(
                weekOfYear: week.week,
                yearForWeekOfYear: week.year
            )
        ) else { return nil }

        guard let previousDate =
            calendar.date(byAdding: .weekOfYear, value: -1, to: currentWeekDate)
        else { return nil }

        return (
            year: calendar.component(.yearForWeekOfYear, from: previousDate),
            week: calendar.component(.weekOfYear, from: previousDate)
        )
    }
    private func rebuildComparison() {
        guard mode == .week else {
            cachedComparison = nil
            return
        }

        guard
            let stats = cachedStats,
            !cachedEvents.isEmpty,
            let prev = previousWeekSafe(),
            let prevEvents = cachedEventsByWeek["\(prev.year)-\(prev.week)"],
            !prevEvents.isEmpty
        else {
            cachedComparison = nil
            return
        }

        let prevStats = WeeklyStatsBuilder.build(events: prevEvents)

        let currentWithOthers =
            (stats.byOrigin[.createdForMe] ?? 0) +
            (stats.byOrigin[.iCreatedForOther] ?? 0)

        let prevWithOthers =
            (prevStats.byOrigin[.createdForMe] ?? 0) +
            (prevStats.byOrigin[.iCreatedForOther] ?? 0)

        cachedComparison = WeeklyComparison(
            deltaTotal: stats.totalEvents - prevStats.totalEvents,
            deltaWithOthers: currentWithOthers - prevWithOthers
        )
    }
    private func rebuildAll() {
        rebuildEvents()
        rebuildStats()
        rebuildComparison()
    }



    var body: some View {
        NavigationStack {
            List {
                if isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, minHeight: 200)
                } else if events.isEmpty {
                    ContentUnavailableView(
                        String(localized: "no_events_this_week"),
                        systemImage: "calendar.badge.clock"
                    )
                } else {
                    summarySection
                    detailSection
                }

            }

            .navigationTitle(
                mode == .week ? weekTitle : monthTitle
            )

            .toolbar {
                // 🔹 LEFT — Week / Month switch
                ToolbarItem(placement: .navigationBarLeading) {
                    Picker("", selection: $mode) {
                        Text(String(localized: "week")).tag(SummaryMode.week)
                        Text(String(localized: "month")).tag(SummaryMode.month)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 160)
                }

                // 🔹 RIGHT — Close
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(String(localized: "close")) {
                        dismiss()
                    }
                }
            }

        }
        .task(id: "\(week.year)-\(week.week)") {
            isLoading = true
            defer { isLoading = false }

            let cal = Calendar.current
            let allEvents = eventManager.pastEvents

            cachedEventsByWeek = Dictionary(grouping: allEvents) {
                "\(cal.component(.yearForWeekOfYear, from: $0.date))-\(cal.component(.weekOfYear, from: $0.date))"
            }

            cachedEventsByMonth = Dictionary(grouping: allEvents) {
                "\(cal.component(.year, from: $0.date))-\(cal.component(.month, from: $0.date))"
            }

            rebuildAll()
        }

        .onChange(of: mode) { _, _ in
            guard !isLoading else { return }
            rebuildAll()
        }


    }
    
    
    
    private static let monthFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = .current
        f.dateFormat = "LLLL yyyy"
        return f
    }()

    
    private var summarySection: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {

                summaryRow(
                    title: String(localized: "total_events"),
                    value: "\(stats.totalEvents)"
                )

                if let mine = stats.byOrigin[.myEvent] {
                    summaryRow(
                        title: String(localized: "created_by_you"),
                        value: "\(mine)"
                    )
                }

                let otherCount =
                    (stats.byOrigin[.createdForMe] ?? 0) +
                    (stats.byOrigin[.iCreatedForOther] ?? 0)

                if otherCount > 0 {
                    summaryRow(
                        title: String(localized: "with_others"),
                        value: "\(otherCount)"
                    )
                }


                if let busiest = stats.busiestWeekday {
                    summaryRow(
                        title: String(localized: "busiest_day"),
                        value: weekdayName(busiest)
                    )
                }

                if let peak = stats.peakHourRange {
                    summaryRow(
                        title: String(localized: "most_active_hours"),
                        value: "\(peak.lowerBound):00 – \(peak.upperBound):00"
                    )
                }
                if mode == .week, let comparison = cachedComparison {

                    Divider()
              
                    HStack {
                        Text(String(localized: "events_vs_last_week"))
                            .foregroundColor(.secondary)

                        Spacer()

                        Text(deltaText(comparison.deltaTotal))
                            .fontWeight(.semibold)
                            .foregroundColor(
                                comparison.deltaTotal > 0 ? .green :
                                comparison.deltaTotal < 0 ? .red :
                                .secondary
                            )
                    }

                }

            }
            .padding(.vertical, 8)
        }
    }

    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    private var eventsByWeek: [String: [CalendarEvent]] {
        cachedEventsByWeek
    }


    private func rebuildEvents() {
        let cal = Calendar.current

        switch mode {

        case .week:
            let key = "\(week.year)-\(week.week)"
            cachedEvents =
                cachedEventsByWeek[key]?
                    .sorted { $0.startTime < $1.startTime } ?? []

        case .month:
            guard
                let weekStart = cal.date(
                    from: DateComponents(
                        weekOfYear: week.week,
                        yearForWeekOfYear: week.year
                    )
                )
            else {
                cachedEvents = []
                return
            }

            let key = monthKey(from: weekStart)
            cachedEvents =
                cachedEventsByMonth[key]?
                    .sorted { $0.startTime < $1.startTime } ?? []
        }
    }

    
    
    private func summaryRow(title: String, value: String) -> some View {
        HStack {
            Text(title)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.semibold)
        }
    }

    private var detailSection: some View {
        Section(header: Text(String(localized: "events"))) {
            ForEach(events) { event in
                VStack(alignment: .leading, spacing: 4) {
                    Text(event.title)
                        .font(.body.weight(.medium))

                    Text(formatted(event.startTime))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 4)
            }
        }
    }

    private var weekTitle: String {
        let calendar = Calendar.current

        guard
            let weekStart = calendar.date(
                from: DateComponents(
                    weekOfYear: week.week,
                    yearForWeekOfYear: week.year
                )
            ),
            let weekEnd = calendar.date(byAdding: .day, value: 6, to: weekStart)
        else {
            return ""
        }

        let start = weekStart.formatted(.dateTime.month().day())
        let end = weekEnd.formatted(.dateTime.month().day())

        return "\(start) – \(end)"
    }


    
    
    private func weekdayName(_ weekday: Int) -> String {
        let symbols = Calendar.current.weekdaySymbols
        return symbols.indices.contains(weekday - 1)
            ? symbols[weekday - 1]
            : ""
    }

    private func formatted(_ date: Date) -> String {
        date.formatted(
            .dateTime
                .hour(.twoDigits(amPM: .abbreviated))
                .minute(.twoDigits)
                .day()
                .month()
                .year()
        )
    }

   

  


  


    private func deltaText(_ value: Int) -> String {
        if value > 0 { return "↑ \(value)" }
        if value < 0 { return "↓ \(abs(value))" }
        return "–"
    }

    //MONTH HELPERRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRR
    
    private func monthKey(from date: Date) -> String {
        let cal = Calendar.current
        let y = cal.component(.year, from: date)
        let m = cal.component(.month, from: date)
        return "\(y)-\(m)"
    }

    
    
    
    
    
    
    
    
}

