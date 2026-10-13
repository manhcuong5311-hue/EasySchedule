//
//  QuickReply.swift
//  Easy Schedule
//
//  "Tôi đang tới" / "Trễ 10 phút" from a reminder notification or the Live
//  Activity → posts a message into the event's chat (the other side gets the
//  usual chat push).
//

import Foundation
import UserNotifications

enum QuickReply {

    /// Reminder category for events shared with someone (has the two buttons).
    static let sharedEventCategory = "EVENT_SHARED"
    static let onMyWayAction = "QUICK_ON_MY_WAY"
    static let runningLateAction = "QUICK_LATE_10"

    static func registerNotificationCategories() {
        let onMyWay = UNNotificationAction(identifier: onMyWayAction,
                                           title: String(localized: "quick_on_my_way_button"),
                                           options: [])
        let late = UNNotificationAction(identifier: runningLateAction,
                                        title: String(localized: "quick_late_button"),
                                        options: [])
        let category = UNNotificationCategory(identifier: sharedEventCategory,
                                              actions: [onMyWay, late],
                                              intentIdentifiers: [],
                                              options: [])
        UNUserNotificationCenter.current().setNotificationCategories([category])
    }

    static func kind(forAction identifier: String) -> QuickReplyKind? {
        switch identifier {
        case onMyWayAction:     return .onMyWay
        case runningLateAction: return .runningLate
        default:                return nil
        }
    }

    @MainActor
    static func send(_ kind: QuickReplyKind, eventId: String) async {
        let text: String
        switch kind {
        case .onMyWay:     text = String(localized: "quick_on_my_way_message")
        case .runningLate: text = String(localized: "quick_late_message")
        }
        if await ChatPoster.post(text, eventId: eventId) {
            AppAnalytics.log(AppAnalyticsEvent.quickReplySent,
                             ["kind": kind == .onMyWay ? "on_my_way" : "late"])
        }
    }
}
