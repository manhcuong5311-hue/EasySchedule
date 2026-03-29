import SwiftUI
import FirebaseAuth
// NOTE: Participants cannot self-leave events. Only owner/creator/admin can remove users.

struct EventRowView: View {

    let event: CalendarEvent
    let showOwnerLabel: Bool
    @AppStorage("timeFontSize")
    private var timeFontSize: Double = 13


    @Binding var expandedEvents: Set<String>

    @EnvironmentObject var eventManager: EventManager
    @Environment(\.colorScheme) private var colorScheme

    // ⭐ CHAT META – đúng lifecycle
    @ObservedObject var chatMeta: ChatMetaViewModel
    @ObservedObject private var todoHintStore =
        LocalEventTodoHintStore.shared


    private var isMyEvent: Bool {
        event.createdBy == event.owner
    }

    private var isPersonalEvent: Bool {
        event.participants.count == 1
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

    private var myUid: String? {
        Auth.auth().currentUser?.uid
    }

    private var isOwner: Bool {
        myUid == event.owner
    }

    private var isCreator: Bool {
        myUid == event.createdBy
    }

    private var isAdmin: Bool {
        event.admins?.contains(myUid ?? "") == true
    }

    private var canDeleteEvent: Bool {
        isOwner || isCreator || isAdmin
    }

    private var canLeaveEvent: Bool {
        !canDeleteEvent && event.participants.contains(myUid ?? "")
    }

    @State private var showLeaveConfirm = false

    @State private var showAddMemberSheet = false

    private var hasAnyTodoHint: Bool {
        if isPersonalEvent {
            return unfinishedTodoCount > 0
        } else {
            return todoHintStore.hasTodoHint(eventId: event.id)
        }
    }

    private var todoHintDot: some View {
        Circle()
            .fill(Color.secondary.opacity(0.6))
            .frame(width: 6, height: 6)
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
                HStack(spacing: 8) {

                    // 🔴 UNREAD CHAT
                    if chatMeta.unread {
                        Circle()
                            .fill(Color.red)
                            .frame(width: 8, height: 8)
                    }

                    // ➕ ADD PEOPLE (personal events, owner/admin only)
                    if isPersonalEvent && canDeleteEvent {
                        Button {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            showAddMemberSheet = true
                        } label: {
                            Image(systemName: "person.badge.plus")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(uiAccent.color.opacity(0.75))
                        }
                        .buttonStyle(.plain)
                    }

                    // 🔵 TODO COUNT (MY EVENT)
                    if isPersonalEvent && unfinishedTodoCount > 0 {
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
                    
                    else if !isPersonalEvent && hasAnyTodoHint {
                        todoHintDot
                    }

                    // ▶️ CHEVRON
                    if isPersonalEvent {
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
                handleEventTap()
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
                            ? Color.black.opacity(0.05)   // ⭐ viền nhẹ cho light
                            : Color.white.opacity(0.05)
                        ),
                        lineWidth: chatMeta.unread ? 1.5 : 1
                    )
            )

            // ===== TODO =====
            if isExpanded {
                LocalTodoListView(eventId: event.id)
                    .padding(.horizontal, 12)
            }

        }
        .contextMenu {

            // 👑 Owner / Creator / Admin
            if canDeleteEvent {

                // 👥 Add people (SAFE ACTION)
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    showAddMemberSheet = true
                } label: {
                    Label(
                        String(localized: "add_member_title"),
                        systemImage: "person.badge.plus"
                    )
                }

                Divider() // ⭐ TÁCH DELETE RA XA

                // ❌ Delete event
                Button(role: .destructive) {
                    showDeleteConfirm = true
                } label: {
                    Label(
                        String(localized: "delete"),
                        systemImage: "trash"
                    )
                }
            }

            // 👤 Member thường → chỉ được leave
            else if canLeaveEvent {

                Button {
                    showLeaveConfirm = true
                } label: {
                    Label(
                        String(localized: "leave_event"),
                        systemImage: "rectangle.portrait.and.arrow.right"
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
        .sheet(isPresented: $showAddMemberSheet) {
            AddMemberSheet(event: event)
                .environmentObject(eventManager)
        }

        .alert(
            String(localized: "leave_event"),
            isPresented: $showLeaveConfirm
        ) {
            Button(String(localized: "close"), role: .cancel) {}
        } message: {
            Text(String(localized: "leave_event_not_allowed"))
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
    
    
    
    
    
    
    
    
    
    private func handleEventTap() {
        if isPersonalEvent {
            toggleExpand()
        } else {
            openChat()
        }
    }


    
    
    private func deleteEvent() {
        guard canDeleteEvent else { return }

        withAnimation {
            eventManager.deleteEvent(event)
        }
    }

    private func openChat() {

        // 🔒 Đóng todo nếu đang mở
        expandedEvents.remove(event.id)

        // 1️⃣ Set event đang mở chat
        eventManager.selectedChatEventId = event.id

        // 2️⃣ Mark seen
        chatMeta.markSeen()
        EventSeenStore.shared.markSeen(eventId: event.id)
    }



    
    
    private func toggleExpand() {
        withAnimation {
            if expandedEvents.contains(event.id) {
                expandedEvents.remove(event.id)
            } else {
                expandedEvents.insert(event.id)

                // ⭐️ set hint cho event nhóm
                if !isPersonalEvent {
                    LocalEventTodoHintStore.shared
                        .markHasTodo(eventId: event.id)
                }
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


