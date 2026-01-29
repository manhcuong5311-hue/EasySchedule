//
//  CompactUI.swift
//  Easy Schedule
//
//  Created by Sam Manh Cuong on 26/1/26.
//
// NOTE: Participants cannot self-leave events. Only owner/creator/admin can remove users.

import SwiftUI
import Combine
import FirebaseAuth

private enum StatusIndicator {
    case unreadChat
    case none
}

struct CompactEventRowView: View {
    @Environment(\.colorScheme) private var colorScheme
    // ===== INPUT =====
    let event: CalendarEvent
    let timeFontSize: Double
    let timeDisplayMode: EventTimeDisplayMode

    @Binding var expandedEvents: Set<String>
    @ObservedObject var chatMeta: ChatMetaViewModel

    // ===== ENV =====
    @EnvironmentObject var eventManager: EventManager
    @EnvironmentObject var uiAccent: UIAccentStore

    // ===== STATE =====
    @State private var showDeleteConfirm = false
    @ObservedObject private var todoStore = LocalTodoStore.shared

    // ===== DERIVED =====
    private var isMyEvent: Bool {
        event.createdBy == event.owner
    }

    private var isExpanded: Bool {
        expandedEvents.contains(event.id)
    }

    private var hasUnfinishedTodo: Bool {
        isMyEvent && todoStore.hasUnfinishedTodo(for: event.id)
    }

    private var unfinishedTodoCount: Int {
        todoStore.unfinishedCount(for: event.id)
    }


    private var statusIndicator: StatusIndicator {
        chatMeta.unread ? .unreadChat : .none
    }

    private var myUid: String? {
        Auth.auth().currentUser?.uid
    }

    private var isOwner: Bool {
        myUid == event.owner
    }

    private var isAdmin: Bool {
        event.admins?.contains(myUid ?? "") == true
    }

    private var canDeleteEvent: Bool {
        isOwner || isAdmin || (myUid == event.createdBy)
    }


    private var shouldShowLeaveNotAllowed: Bool {
        !canDeleteEvent && event.participants.contains(myUid ?? "")
    }


    @State private var showLeaveConfirm = false

    @State private var showAddMemberSheet = false

    // ===== BODY =====
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {

            rowContent

            if isMyEvent && isExpanded {
                todoList
            }
        }
        .background(
            ZStack {
                // FILL — chỉ hiện khi expanded
                if isExpanded {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color(.secondarySystemBackground))
                }

                // STROKE — luôn hiện
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(
                        colorScheme == .light
                        ? Color.black.opacity(0.1)
                        : Color.white.opacity(0.1),
                        lineWidth: 1
                    )
            }
        )
        .animation(.easeInOut(duration: 0.2), value: isExpanded)

        .contextMenu {
            contextMenuContent
        }
        .onLongPressGesture(minimumDuration: 0.3) {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            toggleExpand()
        }
        .onAppear {
            chatMeta.startListening()
        }
        .sheet(isPresented: $showAddMemberSheet) {
            AddMemberSheet(event: event)
                .environmentObject(eventManager)
        }

        .alert(
            String(localized: "delete_event"),
            isPresented: $showDeleteConfirm,
            actions: deleteAlertActions,
            message: {
                Text(String(localized: "delete_event_confirm"))
            }
        )
        .alert(
            String(localized: "leave_event"),
            isPresented: $showLeaveConfirm
        ) {
            Button(String(localized: "close"), role: .cancel) {}
        } message: {
            Text(String(localized: "leave_event_not_allowed"))
        }


    }

    

    // ===== ROW CONTENT =====

    private var rowContent: some View {
        HStack(alignment: .top, spacing: 8) {

            timeColumn

            colorDot

            titleView

            Spacer()

            trailingIndicators
        }
        .contentShape(Rectangle())
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .onTapGesture {
            if isMyEvent {
                toggleExpand()
            } else {
                openChatIfNeeded()
            }
        }

    }

    private var titleView: some View {
        HStack(spacing: 4) {

            // TITLE
            Text(event.title)
                .font(.subheadline)
                .fontWeight(.medium)
                .lineLimit(1)

            // CONTEXT (INLINE)
            if !isMyEvent {
                Text("• \(externalEventContext)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }

    @ViewBuilder
    private var contextMenuContent: some View {

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
        else if shouldShowLeaveNotAllowed {

            Button {
                showLeaveConfirm = true
            } label: {
                Label(
                    String(localized: "leave_event"),
                    systemImage: "rectangle.portrait.and.arrow.right"
                )
            }
        }

        else {
            EmptyView()
        }
    }



    private var externalEventContext: String {
        switch event.origin {
        case .iCreatedForOther:
            return "To \(eventManager.displayName(for: event.owner))"
        default:
            return "From \(eventManager.displayName(for: event.createdBy))"
        }
    }


    
    
    private var colorDot: some View {
        Circle()
            .fill(Color(hex: event.colorHex))
            .frame(width: 6, height: 6)
            .padding(.top, 6)
    }

    // ===== TRAILING =====

    private var trailingIndicators: some View {
        HStack(spacing: 6) {

            statusDot

            if isMyEvent && unfinishedTodoCount > 0 {
                todoCountView
            }
        }
    }

    @ViewBuilder
    private var statusDot: some View {
        switch statusIndicator {
        case .unreadChat:
            Circle()
                .fill(Color.red)
                .frame(width: 6, height: 6)

        case .none:
            EmptyView()
        }
    }

    private var todoCountView: some View {
        HStack(spacing: 2) {
            Image(systemName: "checklist")
                .font(.system(size: 10))
            Text("\(unfinishedTodoCount)")
                .font(.caption2)
        }
        .foregroundColor(uiAccent.color)
    }


    // ===== TODO LIST =====

    private var todoList: some View {
        LocalTodoListView(eventId: event.id)
            .padding(.horizontal, 12)
            .padding(.top, 4)
    }

    // ===== TIME COLUMN =====

    private var timeColumn: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(timeDisplayMode.primaryText(for: event))
                .font(
                    .system(
                        size: CGFloat(timeFontSize - 1),
                        weight: .semibold,
                        design: .monospaced
                    )
                )
                .foregroundColor(uiAccent.color)
        }
        .padding(.leading, 6)
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(uiAccent.color)
                .frame(width: 2)
        }
    }

    // ===== MENU & ALERT =====

    private var deleteMenu: some View {
        Button(role: .destructive) {
            showDeleteConfirm = true
        } label: {
            Label(
                String(localized: "delete"),
                systemImage: "trash"
            )
        }
    }

    @ViewBuilder
    private func deleteAlertActions() -> some View {
        Button(String(localized: "delete"), role: .destructive) {
            deleteEvent()
        }
        Button(String(localized: "cancel"), role: .cancel) {}
    }

    // ===== ACTIONS =====

    private func toggleExpand() {
        withAnimation(.easeInOut(duration: 0.2)) {
            if expandedEvents.contains(event.id) {
                expandedEvents.remove(event.id)
            } else {
                expandedEvents.insert(event.id)
            }
        }
    }


    private func openChatIfNeeded() {
        guard !isMyEvent else { return }
        eventManager.selectedChatEventId = event.id
        chatMeta.markSeen()
        EventSeenStore.shared.markSeen(eventId: event.id)
    }

    private func deleteEvent() {
        withAnimation {
            eventManager.deleteEvent(event)
        }
    }
}
