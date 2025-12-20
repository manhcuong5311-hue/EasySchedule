//
//  ChatentryR.swift
//  Easy Schedule
//
//  Created by Sam Manh Cuong on 20/12/25.
//
import SwiftUI
import Combine
import FirebaseAuth

struct ChatEntryResolverView: View {
    let eventId: String
    @EnvironmentObject var eventManager: EventManager

    var body: some View {
        if let event = eventManager.event(by: eventId),
           let myId = Auth.auth().currentUser?.uid {

            ChatView(
                eventId: eventId,
                otherUserId: event.otherUserId(currentUserId: myId),
                otherName: event.otherUserName(
                    currentUserId: myId,
                    userNames: eventManager.userNames
                ),
                eventEndTime: event.endTime,
                eventInfo: event
            )

        } else {
            ProgressView()
                .onAppear {
                    eventManager.fetchEventIfNeeded(eventId: eventId)
                }
        }
    }
}

extension EventManager {

    func event(by id: String) -> CalendarEvent? {
        events.first { $0.id == id }
    }

    func fetchEventIfNeeded(eventId: String) {
        // nếu event chưa có → fetch Firestore
        // nếu đã có → bỏ qua
    }
}
extension CalendarEvent {

    /// Trả về uid của người còn lại trong chat (vì chỉ có 2 người)
    func otherUserId(currentUserId: String) -> String {
        if owner == currentUserId {
            return sharedUser
        } else {
            return owner
        }
    }

    /// Trả về tên người còn lại (fallback nếu chưa cache)
    func otherUserName(
        currentUserId: String,
        userNames: [String: String]
    ) -> String {
        let uid = otherUserId(currentUserId: currentUserId)
        return userNames[uid] ?? uid
    }
}




