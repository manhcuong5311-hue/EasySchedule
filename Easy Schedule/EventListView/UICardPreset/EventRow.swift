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

    private var canDelete: Bool {
        true
    }

    @State private var showDeleteConfirm = false

    
    
    
    let timeDisplayMode: EventTimeDisplayMode
    
    
    @ObservedObject private var todoStore = LocalTodoStore.shared
    private var unfinishedTodoCount: Int {
        todoStore.unfinishedCount(for: event.id)
    }

    private var isOffDay: Bool {
        eventManager.isOffDay(event.date)
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
                // ===== TRAILING =====
                HStack(spacing: 8) {

                    // 🔴 UNREAD CHAT
                    if chatMeta.unread {
                        Circle()
                            .fill(Color.red)
                            .frame(width: 8, height: 8)
                    }

                    // 🔵 TODO COUNT (MY EVENT)
                    if isMyEvent && unfinishedTodoCount > 0 {
                        Text("\(unfinishedTodoCount)")
                            .font(.system(size: 11, weight: .medium))
                                   .foregroundColor(uiAccent.color.opacity(0.8))
                                   .padding(.horizontal, 6)
                                   .padding(.vertical, 2)
                                   .background(
                                       Capsule()
                                           .fill(uiAccent.color.opacity(0.12))
                                   )
                    }

                    // ▶️ CHEVRON
                    if isMyEvent {
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
                            colorScheme == .light
                            ? Color.black.opacity(0.15)   // ⭐ viền nhẹ cho light
                            : Color.white.opacity(0.15)
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
        .contextMenu {
            if canDelete {
                Button(role: .destructive) {
                    showDeleteConfirm = true
                } label: {
                    Label(
                        String(localized: "delete"),
                        systemImage: "trash"
                    )
                }
            }
        }
        .onLongPressGesture(minimumDuration: 0.3) {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        }

        .onAppear {
            chatMeta.startListening()
        }
        .alert(
            String(localized: "delete_event"),
            isPresented: $showDeleteConfirm
        ) {
            Button(String(localized: "delete"), role: .destructive) {
                deleteEvent()
            }
            Button(String(localized: "cancel"), role: .cancel) { }
        } message: {
            Text(String(localized: "delete_event_confirm"))
        }

    }
    
    private func deleteEvent() {
        withAnimation {
            eventManager.deleteEvent(event)
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
        VStack(alignment: .leading, spacing: 2) {

            Text(timeDisplayMode.primaryText(for: event))
                .font(
                    .system(
                        size: CGFloat(timeFontSize),
                        weight: .semibold,
                        design: .monospaced
                    )
                )
                .foregroundColor(uiAccent.color)

            if let secondary = timeDisplayMode.secondaryText(for: event) {
                Text(secondary)
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
        colorScheme == .light
        ? Color(.systemGray6)
        : Color(.tertiarySystemBackground)
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
            return String(localized: "event_owner_assigned_to")
        default:
            return String(localized: "event_owner_created_by")
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


