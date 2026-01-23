//
//  PastEventsByWeekView.swift
//  Easy Schedule
//
//  Created by Sam Manh Cuong on 2/1/26.
//
import SwiftUI

struct PastEventsByWeekView: View {
    @EnvironmentObject var eventManager: EventManager
    let week: (year: Int, week: Int)
    @Environment(\.dismiss) private var dismiss

    @State private var showConfirmClear = false   // 🔥 popup Clear All

    var body: some View {
        NavigationStack {
            List {
                ForEach(eventsThisWeek) { event in
                    VStack(alignment: .leading, spacing: 4) {

                        // ⭐ Tiêu đề sự kiện
                        Text(event.title)
                            .font(.headline)

                        // ⭐ Hiển thị tên người dùng
                        if event.origin == .iCreatedForOther {
                            HStack(spacing: 4) {
                                Text(displayName(for: event, uid: event.createdBy, eventManager: eventManager))
                                Text("→")
                                Text(displayName(for: event, uid: event.owner, eventManager: eventManager))
                            }
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        } else {
                            Text(displayName(for: event, uid: event.createdBy, eventManager: eventManager))
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }

                        // ⭐ Thời gian
                        Text(formatted(event.startTime))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 4)
                }
                .onDelete(perform: deleteAt)     // 🔥 Swipe xoá từng item
            }
            .navigationTitle(weekOfMonthTitle)
            .toolbar {

                // 🔥 Nút Clear All (nổi bật)
                ToolbarItem(placement: .navigationBarLeading) {
                    if !eventsThisWeek.isEmpty {
                        Button(role: .destructive) {
                            showConfirmClear = true
                        } label: {
                            Text(String(localized: "clear_all"))
                        }
                    }
                }

                // 🔥 Close
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(String(localized: "close")) { dismiss() }
                }
            }

            // 🔥 Popup xác nhận xoá tất cả
            .alert(
                String(localized: "are_you_sure_you_want_to_delete_all_events_for_this_week"),
                isPresented: $showConfirmClear
            ) {
                Button(String(localized: "delete_all"), role: .destructive) {
                    clearAll()
                }
                Button(String(localized: "cancel"), role: .cancel) {}
            }
        }
    }

    // MARK: - Swipe delete
    private func deleteAt(at offsets: IndexSet) {
        let arr = eventsThisWeek
        for index in offsets {
            let item = arr[index]

            if let realIndex = eventManager.pastEvents.firstIndex(where: { $0.id == item.id }) {
                eventManager.pastEvents.remove(at: realIndex)
            }
        }
        eventManager.savePastEvents()
    }

    // MARK: - Clear All
    private func clearAll() {
        eventManager.pastEvents.removeAll {
            Calendar.current.component(.weekOfYear, from: $0.date) == week.week &&
            Calendar.current.component(.yearForWeekOfYear, from: $0.date) == week.year
        }
        eventManager.savePastEvents()
    }

    // MARK: - Lọc events trong tuần này
    private var eventsThisWeek: [CalendarEvent] {
        eventManager.pastEvents.filter {
            Calendar.current.component(.weekOfYear, from: $0.date) == week.week &&
            Calendar.current.component(.yearForWeekOfYear, from: $0.date) == week.year
        }
        .sorted(by: { $0.startTime < $1.startTime })
    }

    // MARK: - Format time
    private func formatted(_ date: Date) -> String {
        date.formatted(.dateTime
            .hour(.twoDigits(amPM: .abbreviated))
            .minute(.twoDigits)
            .day()
            .month()
            .year()
        )
    }

    // MARK: - Title cho Navigation Bar
    private var weekOfMonthTitle: String {
        guard let sample = eventsThisWeek.first else { return "" }

        let calendar = Calendar.current
        let weekOfMonth = calendar.component(.weekOfMonth, from: sample.date)

        let weekPrefix = String(localized: "week_prefix")
        let monthName = sample.date.formatted(.dateTime.month(.wide))

        return "\(weekPrefix) \(weekOfMonth) \(monthName)"
    }
}

