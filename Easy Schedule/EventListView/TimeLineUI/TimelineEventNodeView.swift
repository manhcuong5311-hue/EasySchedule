//
//  TimelineEventNodeView.swift
//  Easy Schedule
//
//  Created by Sam Manh Cuong on 26/1/26.
//
import SwiftUI

struct TimelineEventNodeView: View {

    let event: CalendarEvent
    let date: Date
    let startHour: Int
    let endHour: Int
    let timeDisplayMode: EventTimeDisplayMode

    @EnvironmentObject var eventManager: EventManager
    @EnvironmentObject var uiAccent: UIAccentStore

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

    private var isMyEvent: Bool {
        event.origin != .busySlot &&
        event.createdBy == event.owner
    }

    
    private var hasUnreadChat: Bool {
        event.origin != .busySlot &&
        eventManager.chatMeta(for: event.id).unread
    }

    @ObservedObject private var todoStore = LocalTodoStore.shared

    private var hasUnfinishedTodo: Bool {
        isMyEvent && todoStore.hasUnfinishedTodo(for: event.id)
    }

    // MARK: - Body

    var body: some View {
        if !isVisible {
            EmptyView()
        } else {
            content
        }
    }
    
    
//Content
    
    private var content: some View {
        HStack(alignment: .top, spacing: 0) {

            // ===== DOT COLUMN =====
            ZStack(alignment: .topTrailing) {
                Circle()
                    .fill(Color(hex: event.colorHex))
                    .frame(
                        width: TimelineLayout.dotSize,
                        height: TimelineLayout.dotSize
                    )

                if hasUnreadChat {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 4, height: 4)
                        .offset(x: 3, y: -3)
                }
            }
            .frame(width: TimelineLayout.dotColumnWidth)
            .padding(.top, 12)

            // ===== CARD COLUMN =====
            eventCard
        }
        .offset(y: offsetY)
        .zIndex(event.origin == .busySlot ? 0.5 : 1)
        .onTapGesture {
            handleTap()
        }
    }


    private var eventCard: some View {
        HStack(alignment: .top, spacing: 8) {

            icon

            VStack(alignment: .leading, spacing: 4) {

                HStack(spacing: 6) {
                    Text(event.title)
                        .font(.subheadline)
                        .fixedSize(horizontal: false, vertical: true)

                    indicators
                }

                Text(timeDisplayMode.primaryText(for: event))
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: TimelineLayout.blockCornerRadius)
                .fill(Color(hex: event.colorHex).opacity(0.07))
        )
        .overlay(
            RoundedRectangle(cornerRadius: TimelineLayout.blockCornerRadius)
                .stroke(uiAccent.color.opacity(0.6), lineWidth: 0.8)
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

    
    // MARK: - Icon

    private var icon: some View {
        Image(systemName: isMyEvent ? "person.fill" : "person.2.fill")
            .font(.caption)
            .foregroundColor(Color(hex: event.colorHex))
    }

    // MARK: - Tap behavior

    private func handleTap() {
        guard event.origin != .busySlot else { return }

        if isMyEvent {
            eventManager.openEvent(eventId: event.id)
        } else {
            eventManager.openChat(eventId: event.id)
        }
    }
}
