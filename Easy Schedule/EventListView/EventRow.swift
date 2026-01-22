import SwiftUI

struct EventRowView: View {

    let event: CalendarEvent
    let showOwnerLabel: Bool
    let timeFontSize: Double
   

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
//NEWWW
    
    @EnvironmentObject var uiAccent: UIAccentStore

    
    
    
    
    
    let timeDisplayMode: EventTimeDisplayMode

    
    private var timeLabel: String {
        let duration = Int(event.endTime.timeIntervalSince(event.startTime) / 60)

        switch timeDisplayMode {
        case .startTime:
            return event.startTime.formatted(date: .omitted, time: .shortened)

        case .timeRange:
            let s = event.startTime.formatted(date: .omitted, time: .shortened)
            let e = event.endTime.formatted(date: .omitted, time: .shortened)
            return "\(s)–\(e)"

        case .duration:
            return duration >= 60
                ? "\(duration / 60)h \(duration % 60)m"
                : "\(duration) min"
        }
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
                        HStack(spacing: 6) {

                            Text(ownerLabelText)
                                .font(.subheadline)              // ⬅️ tăng size
                                .foregroundColor(.secondary)

                            Text(eventManager.displayName(for: ownerDisplayUID))
                                .font(.subheadline)              // ⬅️ đồng cấp
                                .fontWeight(.medium)             // ⬅️ nhấn nhẹ
                                .foregroundColor(.secondary)
                        }
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
        let duration = Int(event.endTime.timeIntervalSince(event.startTime) / 60)

        return VStack(alignment: .leading, spacing: 2) {

            Text(timeLabel)   // ⭐ DÙNG KẾT QUẢ SWITCH
                .font(
                    .system(
                        size: CGFloat(timeFontSize),
                        weight: .semibold,
                        design: .monospaced
                    )
                )
                .foregroundColor(uiAccent.color)
            // 👉 Chỉ show phụ khi KHÔNG phải duration
            if timeDisplayMode != .duration {
                Text("\(duration) min")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.leading, 8)
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(uiAccent.color)
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


    
    
    
    
    
    private var ownerLabelText: String {
        switch event.origin {
        case .iCreatedForOther:
            return "Assigned to:"
        default:
            return "Created by:"
        }
    }

    private var ownerDisplayUID: String {
        switch event.origin {
        case .iCreatedForOther:
            return event.owner          // người được assign
        default:
            return event.createdBy      // người tạo event
        }
    }


    
    
    
}


