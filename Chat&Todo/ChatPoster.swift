//
//  ChatPoster.swift
//  Easy Schedule
//
//  Posts a message into an event's chat without a ChatViewModel (no listeners):
//  used for automatic notes ("Đã xác nhận", "Đề xuất đổi giờ…") and for the
//  quick replies on notifications / the Live Activity.
//

import Foundation
import FirebaseCore
import FirebaseAuth
import FirebaseFirestore

@MainActor
enum ChatPoster {

    /// Sends `text` as the current user. Creates the chat first when needed —
    /// a message is rejected by the rules until `chats/{eventId}` exists with
    /// `participants` + `eventEndTime`. Returns false for solo / unknown events.
    @discardableResult
    static func post(_ text: String, eventId: String) async -> Bool {
        if FirebaseApp.app() == nil { FirebaseApp.configure() }
        guard let myId = Auth.auth().currentUser?.uid else { return false }

        let db = Firestore.firestore()
        guard let event = await loadEvent(eventId, db: db) else { return false }

        var participants = event.participants
        if participants.isEmpty { participants = [event.owner, event.sharedUser] }
        participants = Array(Set(participants)).filter { !$0.isEmpty }
        guard participants.count > 1, participants.contains(myId) else { return false }

        let chatRef = db.collection("chats").document(eventId)
        let myName = UserDefaults.standard.string(forKey: "currentUserName")
            ?? EventManager.shared.displayName(for: myId)

        do {
            try await withTimeout(seconds: 15) {
                let chat = try await chatRef.getDocument()
                if !chat.exists {
                    try await chatRef.setData([
                        "participants": participants,
                        "eventEndTime": Timestamp(date: event.endTime),
                        "createdAt": Timestamp()
                    ])
                }

                try await chatRef.collection("messages").document(UUID().uuidString).setData([
                    "text": text,
                    "senderId": myId,
                    "senderName": myName,
                    "timestamp": Timestamp(),
                    "seenBy": [myId: true]
                ])

                var unread: [String: Bool] = [:]
                for uid in participants { unread[uid] = uid != myId }
                try await chatRef.setData([
                    "lastMessage": "\(EventManager.shared.displayName(for: myId)): \(text)",
                    "lastMessageTime": Timestamp(),
                    "unread": unread
                ], merge: true)
            }
            return true
        } catch {
            // Offline: Firestore keeps the queued writes and sends them later.
            print("⚠️ ChatPoster:", error.localizedDescription)
            return false
        }
    }

    private static func loadEvent(_ id: String, db: Firestore) async -> CalendarEvent? {
        if let cached = EventManager.shared.events.first(where: { $0.id == id }) { return cached }
        guard let snap = try? await db.collection("events").document(id).getDocument() else { return nil }
        return CalendarEvent.from(snap)
    }

    private struct Timeout: Error {}

    private static func withTimeout(seconds: Double, _ work: @escaping () async throws -> Void) async throws {
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask { try await work() }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                throw Timeout()
            }
            try await group.next()
            group.cancelAll()
        }
    }
}
