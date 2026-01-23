//
//  ChatMetaViewModel.swift
//  Easy Schedule
//
//  Created by Sam Manh Cuong on 2/1/26.
//

import SwiftUI
import Combine
import Foundation
import FirebaseFirestore
import FirebaseAuth
import CoreLocation
import MapKit



class ChatMetaViewModel: ObservableObject {
    @Published var lastMessage: String = ""
    @Published var unread: Bool = false

    private var lastNotifiedMessage: String? {
        didSet {
            UserDefaults.standard.set(
                lastNotifiedMessage,
                forKey: "lastNotified_\(eventId)"
            )
        }
    }

    private let db = Firestore.firestore()
    private let eventId: String
    private let myId: String
    private var listener: ListenerRegistration?

    init(eventId: String, myId: String) {
        self.eventId = eventId
        self.myId = myId

        self.lastNotifiedMessage =
            UserDefaults.standard.string(forKey: "lastNotified_\(eventId)")
    }
    static func placeholder(eventId: String) -> ChatMetaViewModel {
        let vm = ChatMetaViewModel(eventId: eventId, myId: "")
        return vm
    }

    func startListening() {
        guard listener == nil else { return }
        listen()
    }
    func markSeen() {
        let chatRef = Firestore.firestore()
            .collection("chats")
            .document(eventId)

        chatRef.updateData([
            "unread.\(myId)": false
        ])
    }


    deinit {
        listener?.remove()
    }

    private func listen() {
        listener = db.collection("chats")
            .document(eventId)
            .addSnapshotListener { snap, _ in
                guard let data = snap?.data() else { return }

                let lastMsg = data["lastMessage"] as? String ?? ""
                let unreadDict = data["unread"] as? [String: Bool] ?? [:]
                let isUnread = unreadDict[self.myId] ?? false

                let shouldNotify =
                    isUnread &&
                    !lastMsg.isEmpty &&
                    lastMsg != self.lastNotifiedMessage &&
                    UIApplication.shared.applicationState != .active &&
                    ChatForegroundTracker.shared.activeChatEventId != self.eventId

                DispatchQueue.main.async {

                    // ✅ chỉ publish khi thật sự thay đổi
                    if self.lastMessage != lastMsg {
                        self.lastMessage = lastMsg
                    }

                    if self.unread != isUnread {
                        self.unread = isUnread
                    }

                    if shouldNotify {
                        self.lastNotifiedMessage = lastMsg
                        pushLocalChatNotification(
                            title: String(localized: "notification_new_message_title"),
                            body: lastMsg,
                            identifier: "chat-\(self.eventId)"
                        )
                    }
                }

            }
    }
}




