//
//  ChatViewModel.swift
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

class ChatViewModel: ObservableObject {

    // MARK: - Published
    @Published var messages: [ChatMessage] = []
    @Published var messageText: String = ""
    @Published var reachedFreeLimit = false
    @Published var myTier: PremiumTier = .free

    // MARK: - Constants
  
    @Published var chatPremiumUnlocked: Bool = false
    @Published var freeSentCount: Int = 0

    // MARK: - Firestore
    private let db = Firestore.firestore()
    private var listener: ListenerRegistration?

    // MARK: - Identity
    let eventId: String
    let otherUserId: String
    let myId: String
    let myName: String

    // MARK: - Init
    init(eventId: String, otherUserId: String, myName: String) {
        self.eventId = eventId
        self.otherUserId = otherUserId
        self.myId = Auth.auth().currentUser?.uid ?? ""
        self.myName = myName

        startListener()
        listenChatMeta()
    }

    deinit {
        listener?.remove()
    }

    // MARK: - Ensure chat exists (BẮT BUỘC)
    @MainActor
    func ensureChatExists(
        participants: [String],
        eventEndTime: Date
    ) async {

        let ref = db.collection("chats").document(eventId)

        do {
            let snap = try await ref.getDocument()
            if snap.exists { return }

            try await ref.setData([
                "participants": participants,
                "eventEndTime": Timestamp(date: eventEndTime),
                "createdAt": Timestamp()
            ])
        } catch {
            print("❌ ensureChatExists failed:", error)
        }
    }

    // MARK: - Realtime listener
    func startListener() {
        listener?.remove()

        listener = db.collection("chats")
            .document(eventId)
            .collection("messages")
            .order(by: "timestamp")
            .limit(toLast: 20)
            .addSnapshotListener { snap, _ in
                guard let snap else { return }

                DispatchQueue.main.async {
                    self.messages = snap.documents.compactMap {
                        try? $0.data(as: ChatMessage.self)
                    }
                 
                }
            }
    }

    // MARK: - Update free limit (CLIENT SIDE)
   
    // MARK: - Send text message
    func sendMessage(
        isPremium: Bool,
        onLimitReached: @escaping () -> Void
    ) {
        let text = messageText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        // 🔒 Check limit
        if reachedFreeLimit && !isPremium {
            onLimitReached()
            return
        }

        let chatRef = db.collection("chats").document(eventId)

        let messageData: [String: Any] = [
            "text": text,
            "senderId": myId,
            "senderName": myName,
            "timestamp": Timestamp(),
            "seenBy": [myId: true]
        ]

        // 1️⃣ Send message
        chatRef.collection("messages").addDocument(data: messageData)

        // 2️⃣ Increment counter (vẫn đếm, nhưng Premium không bị chặn)
        chatRef.updateData([
            "freeCount.\(myId)": FieldValue.increment(Int64(1))
        ])

        // 3️⃣ Update chat meta
        chatRef.setData([
            "lastMessage": text,
            "lastMessageTime": Timestamp(),
            "unread": [
                myId: false,
                otherUserId: true
            ]
        ], merge: true)

        messageText = ""
    }




    // MARK: - Send location message
    func sendCurrentLocation(
        lat: Double,
        lon: Double,
        isPremium: Bool,
        onLimitReached: @escaping () -> Void
    ) {
        // 🔒 Check limit (Premium được bypass)
        if reachedFreeLimit && !isPremium {
            onLimitReached()
            return
        }

        let chatRef = db.collection("chats").document(eventId)

        let messageData: [String: Any] = [
            "latitude": lat,
            "longitude": lon,
            "senderId": myId,
            "senderName": myName,
            "timestamp": Timestamp(),
            "seenBy": [myId: true]
        ]

        // 1️⃣ Send location message
        chatRef.collection("messages").addDocument(data: messageData)

        // 2️⃣ Increment counter (vẫn đếm, nhưng Premium không bị chặn)
        chatRef.updateData([
            "freeCount.\(myId)": FieldValue.increment(Int64(1))
        ])

        // 3️⃣ Update chat meta
        chatRef.setData([
            "lastMessage": String(localized: "location_sent"),
            "lastMessageTime": Timestamp(),
            "unread": [
                myId: false,
                otherUserId: true
            ]
        ], merge: true)
    }



    private func listenChatMeta() {
        let chatRef = db.collection("chats").document(eventId)

        chatRef.addSnapshotListener { snap, _ in
            guard let data = snap?.data() else { return }

            DispatchQueue.main.async {

                let freeCount = data["freeCount"] as? [String: Int] ?? [:]
                let sentByMe = freeCount[self.myId] ?? 0

                self.freeSentCount = sentByMe

                // 🔑 LIMIT THEO TIER
                if let limit = self.chatLimit(for: self.myTier) {
                    self.reachedFreeLimit = sentByMe >= limit
                } else {
                    self.reachedFreeLimit = false
                }
            }
        }
    }
    private func chatLimit(for tier: PremiumTier) -> Int? {
        switch tier {
        case .free:
            return 100
        case .premium:
            return 500
        case .pro:
            return nil // unlimited
        }
    }



    // MARK: - Mark seen
    func markSeen() {
        db.collection("chats")
            .document(eventId)
            .updateData([
                "unread.\(myId)": false
            ])
    }

    // MARK: - Auto delete
    func autoDeleteIfPast(_ eventEndTime: Date) {
        if eventEndTime > Date() { return }

        let chatRef = db.collection("chats").document(eventId)

        chatRef.collection("messages").getDocuments { snap, _ in
            snap?.documents.forEach { $0.reference.delete() }
        }

        chatRef.collection("todos").getDocuments { snap, _ in
            snap?.documents.forEach { $0.reference.delete() }
        }

        chatRef.delete()
    }
    private func updateChatMeta(lastMessage: String) {
        let chatRef = Firestore.firestore()
            .collection("chats")
            .document(eventId)

        chatRef.setData([
            "lastMessage": lastMessage,
            "lastMessageTime": Timestamp(),
            "unread": [
                myId: false,
                otherUserId: true
            ]
        ], merge: true)
    }
   
    }

