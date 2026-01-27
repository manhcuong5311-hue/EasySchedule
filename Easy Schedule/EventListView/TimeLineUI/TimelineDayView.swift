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

        let screenWidth = UIScreen.main.bounds.width
        let leadingPadding: CGFloat = 40
        let hourWidth = TimelineLayout.hourLabelWidth + 1
        let contentWidth = screenWidth - hourWidth - leadingPadding

        ScrollView {
            HStack(alignment: .top, spacing: 0) {

                // ⏰ HOUR COLUMN — NHỎ, CỐ ĐỊNH
                TimelineHourColumn(
                    startHour: safeStartHour,
                    endHour: safeEndHour,
                    timeFontSize: timeFontSize
                )
                .frame(width: hourWidth)

                // 📅 CONTENT COLUMN — PHẦN CÒN LẠI
                TimelineContentColumn(
                    date: date,
                    startHour: safeStartHour,
                    endHour: safeEndHour,
                    events: events,
                    manualBusySlots: manualBusySlots,
                    timeDisplayMode: timeDisplayMode
                )
                .frame(width: contentWidth, alignment: .leading)
            }
            .padding(.leading, leadingPadding)
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
        ScrollView {
            VStack(spacing: 16) {

                // ===== HEADER =====
                VStack(alignment: .leading, spacing: 8) {

                    Text(event.title)
                        .font(.title3)
                        .fontWeight(.semibold)

                    Text(EventTimeDisplayMode.timeRange.primaryText(for: event))
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color(.systemGray6))
                )

                // ===== TODO SECTION =====
                VStack(alignment: .leading, spacing: 12) {

                    Label("Tasks", systemImage: "checklist")
                        .font(.headline)

                    LocalTodoListView(eventId: event.id)
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color(.systemGray6))
                )
            }
            .padding()
        }
        .navigationTitle("Event")
        .navigationBarTitleDisplayMode(.inline)
    }
}
