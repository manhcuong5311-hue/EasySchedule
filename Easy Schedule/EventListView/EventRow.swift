import SwiftUI

struct EventRowView: View {

    let event: CalendarEvent
    let showOwnerLabel: Bool
    let timeFontSize: Double
    let timeColorHex: String

    @Binding var expandedEvents: Set<String>

    @EnvironmentObject var eventManager: EventManager
    @Environment(\.colorScheme) private var colorScheme

    // ⭐ CHAT META – đúng lifecycle
    @ObservedObject var chatMeta: ChatMetaViewModel


    private var isMyEvent: Bool {
        event.createdBy == event.owner
    }

    private var isExpanded: Bool {
        expandedEvents.contains(event.id)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {

            // ===== EVENT CARD =====
            HStack(alignment: .top, spacing: 12) {

                timeText

                Circle()
                    .fill(Color(hex: event.colorHex))
                    .frame(width: 8, height: 8)
                    .padding(.top, 10)

                VStack(alignment: .leading, spacing: 6) {
                    Text(event.title)
                        .font(.headline)

                    if showOwnerLabel && !isMyEvent {
                        Text(eventManager.displayName(for: event.owner))
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()

                // ===== TRAILING =====
                if chatMeta.unread {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 8, height: 8)
                } else if isMyEvent {
                    Button {
                        toggleExpand()
                    } label: {
                        Image(systemName: "chevron.down")
                            .rotationEffect(.degrees(isExpanded ? 180 : 0))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                } else {
                    Image(systemName: "chevron.right")
                        .foregroundStyle(.tertiary)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                openChatIfNeeded()
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(cardBackground)
            )
            .shadow(
                color: chatMeta.unread
                    ? unreadBorderColor.opacity(0.6)
                    : .clear,
                radius: chatMeta.unread ? 6 : 0
            )

            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(
                        chatMeta.unread
                        ? unreadBorderColor
                        : (
                            colorScheme == .dark
                            ? Color.white.opacity(0.06)
                            : Color.clear
                        ),
                        lineWidth: chatMeta.unread ? 1.5 : 1
                    )
            )



            // ===== TODO =====
            if isMyEvent && isExpanded {
                LocalTodoListView(eventId: event.id)
                    .padding(.horizontal, 12)
            }
        }
        .onAppear {
            chatMeta.startListening()
        }

    }
    
    
    
    private func openChatIfNeeded() {
        guard !isMyEvent else { return }

        // 1️⃣ Set event đang mở chat
        eventManager.selectedChatEventId = event.id

        // 2️⃣ Clear unread
        chatMeta.markSeen()
        // ⭐ ADD DÒNG NÀY
            EventSeenStore.shared.markSeen(eventId: event.id)
    }

    
    
    private func toggleExpand() {
        withAnimation {
            if expandedEvents.contains(event.id) {
                expandedEvents.remove(event.id)
            } else {
                expandedEvents.insert(event.id)
            }
        }
    }

    private var timeText: some View {
        let minutes = Int(event.endTime.timeIntervalSince(event.startTime) / 60)

        return VStack(alignment: .leading, spacing: 2) {
            Text(event.startTime.formatted(date: .omitted, time: .shortened))
                .font(.system(size: CGFloat(timeFontSize), weight: .semibold, design: .monospaced))
                .foregroundColor(Color(hex: timeColorHex))

            Text("\(minutes) min")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding(.leading, 8)
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(Color(hex: timeColorHex))
                .frame(width: 2)
        }
    }
    
    
    private var cardBackground: Color {
        switch colorScheme {
        case .light:
            return Color(.secondarySystemBackground)
        case .dark:
            return Color(.tertiarySystemBackground)
        @unknown default:
            return Color(.systemBackground)
        }
    }

    private var unreadBorderColor: Color {
        guard chatMeta.unread else { return .clear }

        if colorScheme == .dark {
            return Color.red.opacity(0.35)
        } else {
            return Color.red.opacity(0.25)
        }
    }


    private var cardShadow: (color: Color, radius: CGFloat, y: CGFloat) {
        if colorScheme == .dark {
            return (Color.white.opacity(0.08), 12, 6)
        } else {
            return (Color.black.opacity(0.08), 8, 4)
        }
    }

    
    
    
    
    
    
    
    
    
    
    
    
}


