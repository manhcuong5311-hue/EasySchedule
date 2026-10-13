//
//  WidgetEsLiveActivity.swift
//  WidgetEs (widget target)
//
//  Live Activity (màn khoá) + Dynamic Island cho "việc đang/sắp diễn ra".
//
import WidgetKit
import SwiftUI
import ActivityKit
import AppIntents

struct ScheduleLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: ScheduleActivityAttributes.self) { context in
            // Màn khoá / banner
            LiveActivityLockView(state: context.state)
                .activityBackgroundTint(context.state.color.opacity(0.12))
                .activitySystemActionForegroundColor(context.state.color)
        } dynamicIsland: { context in
            let s = context.state
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 6) {
                        Circle().fill(s.color).frame(width: 10, height: 10)
                        Text(s.isUpcoming ? WidgetStrings.next : WidgetStrings.now)
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(s.color)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(timerInterval: timerRange(to: s.target), countsDown: true)
                        .font(.caption.weight(.semibold).monospacedDigit())
                        .frame(maxWidth: 64)
                        .multilineTextAlignment(.trailing)
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(s.title).font(.headline).lineLimit(1)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 6) {
                        (Text(s.start, style: .time) + Text(" – ") + Text(s.end, style: .time))
                            .font(.caption2).foregroundStyle(.secondary)
                        if s.canChat == true {
                            QuickReplyButtons(eventID: s.eventID, tint: s.color)
                        }
                    }
                }
            } compactLeading: {
                Circle().fill(s.color).frame(width: 9, height: 9)
            } compactTrailing: {
                Text(timerInterval: timerRange(to: s.target), countsDown: true)
                    .font(.caption2.monospacedDigit())
                    .frame(maxWidth: 44)
            } minimal: {
                Circle().fill(s.color).frame(width: 9, height: 9)
            }
            .keylineTint(s.color)
        }
    }
}

// MARK: - Lock screen view
struct LiveActivityLockView: View {
    let state: ScheduleActivityAttributes.ContentState
    var body: some View {
        VStack(spacing: 10) {
            mainRow
            if state.canChat == true {
                QuickReplyButtons(eventID: state.eventID, tint: state.color)
            }
        }
        .padding(14)
    }

    private var mainRow: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 3).fill(state.color).frame(width: 4, height: 40)

            VStack(alignment: .leading, spacing: 3) {
                Text(state.isUpcoming ? WidgetStrings.next : WidgetStrings.now)
                    .font(.caption2.weight(.bold)).foregroundStyle(state.color)
                Text(state.title).font(.headline).lineLimit(1)
                (Text(state.start, style: .time) + Text(" – ") + Text(state.end, style: .time))
                    .font(.caption2).foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 2) {
                Text(state.isUpcoming ? WidgetStrings.startsIn : WidgetStrings.endsIn)
                    .font(.caption2).foregroundStyle(.secondary)
                Text(timerInterval: timerRange(to: state.target), countsDown: true)
                    .font(.title3.weight(.semibold).monospacedDigit())
                    .foregroundStyle(state.color)
                    .frame(maxWidth: 76)
                    .multilineTextAlignment(.trailing)
            }
        }
    }
}

// MARK: - Quick replies ("Tôi đang tới" / "Trễ 10 phút")
/// Each button runs `QuickReplyIntent` in the app process, which posts the
/// message into the event chat.
struct QuickReplyButtons: View {
    let eventID: String
    let tint: Color

    var body: some View {
        HStack(spacing: 8) {
            Button(intent: QuickReplyIntent(eventId: eventID, kind: .onMyWay)) {
                Label(WidgetStrings.onMyWay, systemImage: "car.fill")
                    .frame(maxWidth: .infinity)
            }
            Button(intent: QuickReplyIntent(eventId: eventID, kind: .runningLate)) {
                Label(WidgetStrings.runningLate, systemImage: "clock.badge.exclamationmark")
                    .frame(maxWidth: .infinity)
            }
        }
        .font(.caption.weight(.semibold))
        .buttonStyle(.bordered)
        .tint(tint)
    }
}
