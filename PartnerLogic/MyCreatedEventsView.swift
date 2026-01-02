//
//  MyCreatedEventsView.swift
//  Easy Schedule
//
//  Created by Sam Manh Cuong on 2/1/26.
//

import SwiftUI
import FirebaseAuth
import FirebaseFirestore

struct MyCreatedEventsView: View {

    @EnvironmentObject var eventManager: EventManager

    @State private var createdUpcoming: [CalendarEvent] = []
    @State private var createdPast: [CalendarEvent] = []

    @State private var loading = true
    @State private var showPast = false
    @State private var selectedDate: Date? = nil
    @State private var searchText: String = ""

    var body: some View {
        NavigationStack {
            VStack {

                Picker("", selection: $showPast) {
                    Text(String(localized: "upcoming")).tag(false)
                    Text(String(localized: "past")).tag(true)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)

                if showPast {
                    searchBar
                }

                if loading {
                    ProgressView(String(localized: "loading"))
                        .padding()
                } else {
                    if showPast { pastList }
                    else { upcomingList }
                }
            }
            .navigationTitle(String(localized: "my_created_events"))
            .onAppear { loadEvents() }
            .sheet(isPresented: Binding(
                get: { selectedDate != nil },
                set: { if !$0 { selectedDate = nil } }
            )) {
                if let date = selectedDate {
                    CreatedEventsByDateView(date: date, events: createdPast)
                }
            }
        }
    }

    // MARK: Search bar
    private var searchBar: some View {
        HStack {
            Image(systemName: "magnifyingglass")
            TextField(String(localized: "search_placeholder"), text: $searchText)
        }
        .padding(10)
        .background(Color(.systemGray6))
        .cornerRadius(10)
        .padding(.horizontal)
    }

    // MARK: Upcoming list
    private var upcomingList: some View {
        let grouped = groupedByMonth(events: createdUpcoming)
        let sortedMonths = grouped.keys.sorted()

        return List {
            if createdUpcoming.isEmpty {
                Text(String(localized: "no_upcoming_events"))
                    .foregroundColor(.secondary)
            } else {
                ForEach(sortedMonths, id: \.self) { monthDate in
                    let monthEvents = grouped[monthDate] ?? []
                    Section(header: headerMonth(monthDate, count: monthEvents.count)) {

                        let weeks = groupedByWeek(events: monthEvents)
                        let sortedWeeks = weeks.keys.sorted()

                        ForEach(sortedWeeks, id: \.self) { week in
                            let weekEvents = weeks[week] ?? []

                            let weekPrefix = String(localized: "week_prefix")

                            Section(header:
                                Text("\(weekPrefix) \(week)")
                            )
 {

                                let days = groupedByDay(events: weekEvents)
                                let sortedDays = days.keys.sorted()

                                ForEach(sortedDays, id: \.self) { day in
                                    Section(header: Text(formatDate(day)).fontWeight(.bold)) {

                                        ForEach(days[day]!.sorted { $0.startTime < $1.startTime }) { ev in
                                            createdEventRow(ev)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    // MARK: Past list
    private var pastList: some View {
        let filtered = createdPast.filter { ev in
            searchText.isEmpty ||
            ev.title.localizedCaseInsensitiveContains(searchText) ||
            ev.owner.localizedCaseInsensitiveContains(searchText)
        }

        let grouped = groupedByMonth(events: filtered)
        let sortedMonths = grouped.keys.sorted(by: >)

        return List {
            if filtered.isEmpty {
                Text(
                    searchText.isEmpty
                    ? String(localized: "no_past_events")
                    : String(localized: "no_results")
                )
                    .foregroundColor(.secondary)
            } else {
                ForEach(sortedMonths, id: \.self) { monthDate in
                    let monthEvents = grouped[monthDate] ?? []

                    Section(header: headerMonth(monthDate, count: monthEvents.count)) {

                        let weeks = groupedByWeek(events: monthEvents)
                        let sortedWeeks = weeks.keys.sorted()

                        ForEach(sortedWeeks, id: \.self) { week in
                            let weekEvents = weeks[week] ?? []

                            Button {
                                selectedDate = weekEvents.first?.date
                            } label: {
                                HStack {
                                    let weekPrefix = String(localized: "week_prefix")
                                    Text("\(weekPrefix) \(week)")
                                    Spacer()
                                    let template = String(localized: "events_count")
                                    Text(template.replacingOccurrences(of: "{count}", with: "\(weekEvents.count)"))
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    // MARK: Row
    private func createdEventRow(_ ev: CalendarEvent) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(ev.title).font(.headline)

            HStack {
                Image(systemName: "person.fill")
                let ownerPrefix = String(localized: "owner_prefix")
                Text("\(ownerPrefix) \(ev.owner)")
            }
            .font(.caption)
            .foregroundColor(.secondary)

            Text("\(formatTime(ev.startTime)) → \(formatTime(ev.endTime))")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
    }

    // MARK: Load data
    private func loadEvents() {
        loading = true
        let now = Date()

        // Lấy toàn bộ events trong máy
        let allEvents = eventManager.events
        let pastEvents = eventManager.pastEvents

        // Chỉ lấy lịch tôi tạo cho đối tác
        let createdForOtherUpcoming = allEvents.filter {
            $0.origin == .iCreatedForOther && $0.endTime >= now
        }

        let createdForOtherPast = pastEvents.filter {
            $0.origin == .iCreatedForOther && $0.endTime < now
        }

        self.createdUpcoming = createdForOtherUpcoming
        self.createdPast = createdForOtherPast

        loading = false
    }
    private func formattedFullDate(_ date: Date) -> String {
        date.formatted(.dateTime.weekday(.wide).day().month(.wide))
    }



    // MARK: Group helpers
    private func groupedByMonth(events: [CalendarEvent]) -> [Date: [CalendarEvent]] {
        Dictionary(grouping: events) {
            Calendar.current.date(from:
                Calendar.current.dateComponents([.year, .month], from: $0.date)
            )!
        }
    }

    private func groupedByWeek(events: [CalendarEvent]) -> [Int: [CalendarEvent]] {
        Dictionary(grouping: events) {
            Calendar.current.component(.weekOfMonth, from: $0.date)
        }
    }

    private func groupedByDay(events: [CalendarEvent]) -> [Date: [CalendarEvent]] {
        Dictionary(grouping: events) {
            Calendar.current.startOfDay(for: $0.date)
        }
    }

    // MARK: Date formatting helpers
    private func headerMonth(_ date: Date, count: Int) -> some View {
        HStack {
            Text(formatMonth(date)).font(.headline)
            Spacer()
            let template = String(localized: "events_count")
            Text(template.replacingOccurrences(of: "{count}", with: "\(count)"))
.foregroundColor(.secondary)
        }
    }

    private func formatMonth(_ date: Date) -> String {
        date.formatted(.dateTime.month(.wide).year())
    }


    private func formatDate(_ date: Date) -> String {
        date.formatted(.dateTime.weekday(.wide).day().month(.wide))
    }



    private func formatTime(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }

}

