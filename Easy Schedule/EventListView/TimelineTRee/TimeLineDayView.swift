//
//  TimeLineDayView.swift
//  Easy Schedule
//
//  Created by Sam Manh Cuong on 26/1/26.
//

import SwiftUI

struct TimelineDayView: View {

    // INPUT
    let date: Date
    let events: [CalendarEvent]
    let timeDisplayMode: EventTimeDisplayMode

    // MOCK manual busy (v1)
    let manualBusySlots: [CalendarEvent]

    // ENV
    @EnvironmentObject var eventManager: EventManager
    @EnvironmentObject var uiAccent: UIAccentStore

    @AppStorage("timeline_start_hour")
    private var startHour: Int = 6

    @AppStorage("timeline_end_hour")
    private var endHour: Int = 22

    private let hourHeight: CGFloat = 64

    private var totalHours: Int {
        max(endHour - startHour, 1)
    }

    
    
    private var dayEvents: [CalendarEvent] {
        events.filter {
            Calendar.current.isDate($0.startTime, inSameDayAs: date)
        }
    }

    private var dayManualBusy: [CalendarEvent] {
        manualBusySlots.filter {
            Calendar.current.isDate($0.startTime, inSameDayAs: date)
        }
    }

    private var safeStartHour: Int {
        min(max(startHour, 0), 23)
    }

    private var safeEndHour: Int {
        min(max(endHour, safeStartHour + 1), 24)
    }

    
    var body: some View {
        ScrollView {
            ZStack(alignment: .topLeading) {

                timelineGrid

                timelineEvents
                
                TimelineNowIndicatorView(
                             date: date,
                             startHour: startHour,
                             endHour: endHour,
                             hourHeight: hourHeight
                         )
            }
            .padding(.leading, 48)
            .padding(.trailing, 16)
        }
    }
    
    
   

    
    
    
    
    
    
    
}


private extension TimelineDayView {

    var timelineGrid: some View {
        VStack(spacing: 0) {
            ForEach(safeStartHour..<min(safeEndHour, 24), id: \.self) { hour in
                HStack(alignment: .top, spacing: 8) {

                    Text(String(format: "%02d:00", hour))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .frame(width: 40, alignment: .trailing)

                    Rectangle()
                        .fill(Color.secondary.opacity(0.2))
                        .frame(width: 2)

                    Spacer()
                }
                .frame(height: hourHeight)
            }
        }
    }
}



private extension TimelineDayView {

    var timelineEvents: some View {

        let allEvents = dayEvents + dayManualBusy

        return ZStack(alignment: .topLeading) {
            ForEach(allEvents) { event in
                TimelineEventNodeView(
                    event: event,
                    timeDisplayMode: timeDisplayMode,
                    hourHeight: hourHeight,
                    startHour: startHour,
                    endHour: endHour,
                    date: date
                ) {
                    handleTap(event)
                }

            }
        }
    }
}


private extension TimelineDayView {

    func handleTap(_ event: CalendarEvent) {

        switch event.origin {

        case .busySlot:
            return   // v1: busy chỉ hiển thị

        default:
            if event.createdBy == event.owner {
                // MY EVENT → mở todo
                eventManager.selectedEventId = event.id
            } else {
                // EVENT WITH OTHER → open chat
                eventManager.openChat(eventId: event.id)
            }
        }
    }
}




struct TimelineEventNodeView: View {

    let event: CalendarEvent
    let timeDisplayMode: EventTimeDisplayMode
    let hourHeight: CGFloat
    let startHour: Int
    let endHour: Int
    let date: Date
    let onTap: () -> Void

    @EnvironmentObject var uiAccent: UIAccentStore

    private var isMyEvent: Bool {
        event.createdBy == event.owner
    }

    private var icon: String {
        isMyEvent ? "person.fill" : "person.2.fill"
    }

    
    
    
    private var safeStartHour: Int {
        min(max(startHour, 0), 23)
    }

    private var safeEndHour: Int {
        min(max(endHour, safeStartHour + 1), 24)
    }

    
    
    
    // MARK: - Timeline bounds

    private var timelineStart: Date {
        Calendar.current.date(
            bySettingHour: safeStartHour,
            minute: 0,
            second: 0,
            of: date
        )!
    }


    private var timelineEnd: Date {
        let hour = min(safeEndHour, 23)

        return Calendar.current.date(
            bySettingHour: hour,
            minute: 59,
            second: 59,
            of: date
        )!
    }


    // MARK: - Clamped times

    private var clampedStart: Date {
        max(event.startTime, timelineStart)
    }

    private var clampedEnd: Date {
        min(event.endTime, timelineEnd)
    }

    private var isBusySlot: Bool {
        event.origin == .busySlot
    }

    // MARK: - Position & Size

    private var topOffset: CGFloat {
        let delta = clampedStart.timeIntervalSince(timelineStart)
        return CGFloat(delta / 3600) * hourHeight
    }

    private var height: CGFloat {
        let duration = clampedEnd.timeIntervalSince(clampedStart)
        return max(CGFloat(duration / 3600) * hourHeight, 20)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {

            Circle()
                .fill(Color(hex: event.colorHex))
                .frame(width: 10, height: 10)
                .overlay(
                    Image(systemName: "lock.fill")
                        .font(.system(size: 10))
                        .foregroundColor(.orange)
                )

            VStack(alignment: .leading, spacing: 4) {

                Text(event.title)
                    .font(.footnote)
                    .fontWeight(.medium)
                    .lineLimit(1)

                Text(timeDisplayMode.primaryText(for: event))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(
                        isBusySlot
                        ? Color.orange.opacity(0.15)
                        : Color(.secondarySystemBackground)
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(
                        isBusySlot
                        ? Color.orange.opacity(0.4)
                        : Color.clear,
                        lineWidth: 1
                    )
            )

        }
        .frame(height: height, alignment: .top)
        .offset(x: 56, y: topOffset)
        .onTapGesture {
            onTap()
        }
    }
}

