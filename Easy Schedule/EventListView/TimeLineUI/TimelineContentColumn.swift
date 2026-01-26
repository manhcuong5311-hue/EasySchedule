//
//  Untitled.swift
//  Easy Schedule
//
//  Created by Sam Manh Cuong on 26/1/26.
//
import SwiftUI
import Combine

struct TimelineContentColumn: View {

    let date: Date
    let startHour: Int
    let endHour: Int

    let events: [CalendarEvent]
    let manualBusySlots: [CalendarEvent]
    let timeDisplayMode: EventTimeDisplayMode

    private var allItems: [CalendarEvent] {
        events + manualBusySlots
    }
    
    @State private var now = Date()

    private let timer = Timer.publish(
        every: 60,
        on: .main,
        in: .common
    ).autoconnect()

    
    var body: some View {
        ZStack(alignment: .topLeading) {

            // ⭐ NOW INDICATOR
            TimelineNowIndicatorView(
                date: date,
                startHour: startHour,
                endHour: endHour,
                now: now
            )


            
            ForEach(allItems) { event in
                TimelineEventNodeView(
                    event: event,
                    date: date,
                    startHour: startHour,
                    endHour: endHour,
                    timeDisplayMode: timeDisplayMode
                )
            }
        }
        .onReceive(timer) { now = $0 }

        .frame(maxWidth: .infinity)
    
    }
}
