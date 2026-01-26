import SwiftUI

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
