//
//  TimelineEventNodeView.swift
//  Easy Schedule
//
//  Created by Sam Manh Cuong on 26/1/26.
//
// NOTE: Participants cannot self-leave events. Only owner/creator/admin can remove users.

import SwiftUI
import FirebaseAuth

struct TimelineEventNodeView: View {

    let event: CalendarEvent
    let date: Date
    let startHour: Int
    let endHour: Int
    let timeDisplayMode: EventTimeDisplayMode

    @EnvironmentObject var eventManager: EventManager
    @EnvironmentObject var uiAccent: UIAccentStore
    // ===== ACTION STATE =====
    @State private var showDeleteConfirm = false
    @State private var showLeaveConfirm = false

    // MARK: - Timeline bounds
    private var safeStartHour: Int {
        min(max(startHour, 0), 23)
    }

    private var safeEndHour: Int {
        min(max(endHour, safeStartHour + 1), 23)
    }


    private var timelineStart: Date? {
        Calendar.current.date(
            bySettingHour: safeStartHour,
            minute: 0,
            second: 0,
            of: date
        )
    }

    private var timelineEnd: Date? {
        if endHour >= 24 {
            // 23:59:59 của ngày hiện tại
            return Calendar.current.date(
                bySettingHour: 23,
                minute: 59,
                second: 59,
                of: date
            )
        }

        return Calendar.current.date(
            bySettingHour: endHour,
            minute: 0,
            second: 0,
            of: date
        )
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


    // MARK: - Clamp

    private var visibleStart: Date? {
        guard let start = timelineStart else { return nil }
        return max(event.startTime, start)
    }

    private var visibleEnd: Date? {
        guard let end = timelineEnd else { return nil }
        return min(event.endTime, end)
    }

    private var isVisible: Bool {
        guard let vs = visibleStart,
              let ve = visibleEnd
        else { return false }

        return ve > vs
    }


    // MARK: - Geometry

    private var offsetY: CGFloat {
        guard let start = timelineStart,
              let vs = visibleStart
        else { return 0 }

        let minutes = vs.timeIntervalSince(start) / 60
        return CGFloat(minutes) * TimelineLayout.minuteHeight
    }

    private var height: CGFloat {
        guard let vs = visibleStart,
              let ve = visibleEnd
        else { return 0 }

        let minutes = ve.timeIntervalSince(vs) / 60
        return max(16, CGFloat(minutes) * TimelineLayout.minuteHeight)
    }


    // MARK: - Event type

 

    
    private var hasUnreadChat: Bool {
        event.origin != .busySlot &&
        eventManager.chatMeta(for: event.id).unread
    }

    @ObservedObject private var todoStore = LocalTodoStore.shared

    private var hasUnfinishedTodo: Bool {
        isPersonalEvent && todoStore.hasUnfinishedTodo(for: event.id)
    }


    @State private var showAddMemberSheet = false
    @State private var showActionSheet = false

    
    private var isPersonalEvent: Bool {
        event.participants.count == 1
    }

    // MARK: - Body

    var body: some View {
        if !isVisible {
            EmptyView()
        } else if event.origin == .busySlot {
            BusySlotCardView(
                start: event.startTime,
                end: event.endTime,
                date: date,
                startHour: startHour
            )
            .zIndex(0)   // 🔒 luôn nằm dưới event thật
        } else {
            content
                .zIndex(1)
        }
        
    }

    
    
//Content
    
    private var content: some View {
        HStack(alignment: .top, spacing: 0) {

            // ===== DOT COLUMN =====
            ZStack(alignment: .topTrailing) {

                // Main dot
                ZStack {
        
                    Image(systemName: isPersonalEvent ? "person.fill" : "person.2.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.primary)

                }
            }
            .frame(width: TimelineLayout.dotColumnWidth)
            .padding(.top, 12)


            // ===== CARD COLUMN =====
            eventCard
            .padding(.leading, 4)
        }
        .padding(.leading, 6)
        .offset(y: offsetY)
        .zIndex(event.origin == .busySlot ? 0.5 : 1)
        .onTapGesture {
            handleTap()
        }
        .onLongPressGesture(minimumDuration: 0.35) {
            guard event.origin != .busySlot else { return }
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()

            // Owner / Creator / Admin → full action
            if canDeleteEvent || canLeaveEvent {
                showActionSheet = true
            }
        }

        .confirmationDialog(
            String(localized: "event_open_action"),
            isPresented: $showActionSheet
        ) {

            // 📌 Open
            Button(String(localized: "open_todo")) {
                eventManager.openEvent(eventId: event.id)
            }

            Button(String(localized: "open_chat")) {
                eventManager.openChat(eventId: event.id)
            }

            // 👥 Add member (Owner / Creator / Admin)
            if canDeleteEvent {
                Button(String(localized: "add_member_title")) {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    showAddMemberSheet = true
                }
            }

            // ❌ Delete event
            if canDeleteEvent {
                Button(String(localized: "delete"), role: .destructive) {
                    showDeleteConfirm = true
                }
            }

            // 🚪 Leave event
            if canLeaveEvent {
                Button(String(localized: "leave_event"), role: .destructive) {
                    showLeaveConfirm = true
                }
            }

            Button(String(localized: "cancel"), role: .cancel) {}
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
            Button(String(localized: "cancel"), role: .cancel) {}
        } message: {
            Text(String(localized: "delete_event_confirm"))
        }

    }


    private var eventCard: some View {
        VStack(alignment: .leading, spacing: 2) {

            HStack(spacing: 6) {
                Text(event.title)
                    .font(.subheadline)

                if hasUnfinishedTodo {
                    Image(systemName: "checklist")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Text(timeDisplayMode.primaryText(for: event))
                .font(.caption)
                .foregroundColor(.secondary)
        }

        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(.systemGray5))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(
                    hasUnreadChat ? Color.red.opacity(0.4) : Color.clear,
                    lineWidth: 1
                )
        )

    }


    private var indicators: some View {
        HStack(spacing: 4) {
            if hasUnfinishedTodo {
                Image(systemName: "checklist")
            }
          
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
    }

    
    // MARK: - Tap behavior

    private func handleTap() {
        guard event.origin != .busySlot else { return }

        if event.participants.count > 1 {
            eventManager.openChat(eventId: event.id)
        } else {
            eventManager.openEvent(eventId: event.id)
        }
    }



    
    private func deleteEvent() {
        guard canDeleteEvent else { return }

        withAnimation {
            eventManager.deleteEvent(event)
        }
    }

   
}

