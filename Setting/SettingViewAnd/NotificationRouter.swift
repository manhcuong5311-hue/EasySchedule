//
//  NotificationRouter.swift
//  Easy Schedule
//
//  Created by Sam Manh Cuong on 4/2/26.
//
import SwiftUI

final class NotificationRouter {
    static let shared = NotificationRouter()
    private init() {}

    func handle(type: String, eventId: String) {
        switch type {
        case "chat":
            openChat(eventId: eventId)

        case "event":
            openEvent(eventId: eventId)

        default:
            break
        }
    }

    private func openChat(eventId: String) {
        // Lưu tạm eventId để RootView đọc
        UserDefaults.standard.set(eventId, forKey: "pendingChatEventId")
    }

    private func openEvent(eventId: String) {
        UserDefaults.standard.set(eventId, forKey: "pendingEventId")
    }
    func handleAccessRequest() {
        UserDefaults.standard.set(true, forKey: "pendingAccessRequest")
    }

}
