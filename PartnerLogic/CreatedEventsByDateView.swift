//
//  CreatedEventsByDateView.swift
//  Easy Schedule
//
//  Created by Sam Manh Cuong on 2/1/26.
//
import SwiftUI
import Foundation

// MARK: - DAY DETAILS VIEW
struct CreatedEventsByDateView: View {
    let date: Date
    let events: [CalendarEvent]

    @Environment(\.dismiss) private var dismiss

    private var eventsForDay: [CalendarEvent] {
        events.filter { Calendar.current.isDate($0.date, inSameDayAs: date) }
            .sorted { $0.startTime < $1.startTime }
    }

    var body: some View {
        NavigationStack {
            List(eventsForDay) { ev in
                VStack(alignment: .leading) {
                    Text(ev.title).font(.headline)
                    Text(
                        String(
                            format: String(localized: "event_owner1"),
                            ev.owner
                        )
                    )
                    .font(.caption)
                    .foregroundColor(.secondary)
                    Text("\(formatTime(ev.startTime)) – \(formatTime(ev.endTime))")
                        .font(.caption)
                }
            }
            .navigationTitle(formatDate(date))
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(String(localized: "close")) { dismiss() }
                }
            }
        }
    }

    private func formatDate(_ date: Date) -> String {
        date.formatted(.dateTime.weekday(.wide).day().month(.wide))
    }


    private func formatTime(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }

}

