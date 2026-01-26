import SwiftUI

struct TimelineDayView: View {

    let date: Date
    let events: [CalendarEvent]
    let manualBusySlots: [CalendarEvent]
    let timeDisplayMode: EventTimeDisplayMode

    @EnvironmentObject var eventManager: EventManager
    @EnvironmentObject var uiAccent: UIAccentStore

    @AppStorage("timeline_start_hour") private var startHour: Int = 8
    @AppStorage("timeline_end_hour")   private var endHour: Int = 22

  
    private var safeStartHour: Int {
        min(max(startHour, 0), 23)
    }

    private var safeEndHour: Int {
        min(max(endHour, safeStartHour + 1), 23)
    }

    private var timelineHeight: CGFloat {
        CGFloat(safeEndHour - safeStartHour) * TimelineLayout.hourHeight
    }
    
    @AppStorage("timeFontSize")
       private var timeFontSize: Double = 13

    var body: some View {
        ScrollView {
            HStack(alignment: .top, spacing: 0) {

                TimelineHourColumn(
                    startHour: safeStartHour,
                    endHour: safeEndHour,
                    timeFontSize: timeFontSize
                )
                .frame(width: TimelineLayout.hourLabelWidth + 1)

                TimelineContentColumn(
                    date: date,
                    startHour: safeStartHour,
                    endHour: safeEndHour,
                    events: events,
                    manualBusySlots: manualBusySlots,
                    timeDisplayMode: timeDisplayMode
                )
                .frame(maxWidth: .infinity, alignment: .leading)

            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: timelineHeight)
            
        }
        .sheet(item: $eventManager.selectedEventWrapper) { wrapper in
            if let event = eventManager.event(for: wrapper) {
                EventDetailView(event: event)
            }
        }

    }
}

import SwiftUI

import Combine

struct EventDetailView: View {
    let event: CalendarEvent

    var body: some View {
        VStack(spacing: 12) {
            Text(event.title)
                .font(.headline)

            Text(EventTimeDisplayMode.timeRange.primaryText(for: event))
                .font(.subheadline)
                .foregroundColor(.secondary)

            Divider()

            LocalTodoListView(eventId: event.id)
        }
        .padding()
    }
}
