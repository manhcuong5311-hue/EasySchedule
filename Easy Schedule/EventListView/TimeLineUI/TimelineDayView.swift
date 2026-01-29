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
        CGFloat(effectiveEndHour - effectiveStartHour)
        * TimelineLayout.hourHeight
    }
    private var isAutoExpanded: Bool {
        guard let r = eventHourRange else { return false }
        return r.start < safeStartHour || r.end > safeEndHour
    }

    
    @AppStorage("timeFontSize")
       private var timeFontSize: Double = 13

    var body: some View {

        let screenWidth = UIScreen.main.bounds.width
        let leadingPadding: CGFloat = 40
        let hourWidth = TimelineLayout.hourLabelWidth + 1
        let contentWidth = screenWidth - hourWidth - leadingPadding

        ScrollView {
            VStack(alignment: .leading, spacing: 6) {

                // 💡 AUTO-EXPAND HINT
                if isAutoExpanded {
                    Text(String(localized: "timeline_auto_expanded_hint"))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .padding(.leading, leadingPadding + 4)
                }

                HStack(alignment: .top, spacing: 0) {

                    // ⏰ HOUR COLUMN
                    TimelineHourColumn(
                        startHour: effectiveStartHour,
                        endHour: effectiveEndHour,
                        timeFontSize: timeFontSize
                    )
                    .frame(width: hourWidth)

                    // 📅 CONTENT COLUMN
                    TimelineContentColumn(
                        date: date,
                        startHour: effectiveStartHour,
                        endHour: effectiveEndHour,
                        events: events,
                        manualBusySlots: eventManager.myManualBusySlots,
                        timeDisplayMode: timeDisplayMode
                    )
                    .frame(width: contentWidth, alignment: .leading)
                }
                .padding(.leading, leadingPadding)
                .frame(height: timelineHeight)
            }
        }

        .sheet(item: $eventManager.selectedEventWrapper) { wrapper in
            if let event = eventManager.event(for: wrapper) {
                EventDetailView(event: event)
            }
        }
    }

    
    private var eventHourRange: (start: Int, end: Int)? {
        let all = events + manualBusySlots
        guard !all.isEmpty else { return nil }

        let cal = Calendar.current

        let startHours = all.map {
            cal.component(.hour, from: $0.startTime)
        }

        let endHours = all.map {
            cal.component(.hour, from: $0.endTime)
        }

        return (start: startHours.min()!, end: endHours.max()!)
    }

    private var effectiveStartHour: Int {
        guard let r = eventHourRange else { return safeStartHour }
        return min(safeStartHour, r.start)
    }

    private var effectiveEndHour: Int {
        guard let r = eventHourRange else { return safeEndHour }
        return max(safeEndHour, r.end)
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

                    Label(
                        String(localized: "tasks"),
                        systemImage: "checklist"
                    )
                
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
        .navigationTitle(
            String(localized: "event_navigation_title")
        )
        .navigationBarTitleDisplayMode(.inline)
    }
}
