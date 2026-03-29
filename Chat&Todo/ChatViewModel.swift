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

enum MessageSendStatus: String, Codable {
    case sending   // đang chờ sync
    case sent      // đã sync server
    case failed    // gửi lỗi (hiếm)
}

class ChatViewModel: ObservableObject {

    // MARK: - Published
    @Published var messages: [ChatMessage] = []
    @Published var messageText: String = ""
    @Published var reachedFreeLimit = false
    @Published var myTier: PremiumTier = .free

    // MARK: - Constants
  
    @Published var chatPremiumUnlocked: Bool = false
    @Published var freeSentCount: Int = 0

    private var didRetryOnce = false

    // MARK: - Firestore
    private let db = Firestore.firestore()
    private var listener: ListenerRegistration?

    
    //New
    
    private let participants: [String]

    // MARK: - Identity
    let eventId: String
    let myId: String
    let myName: String

    // MARK: - Init
    init(
        eventId: String,
        participants: [String],
        myId: String,
        myName: String
    ) {
        self.eventId = eventId
        self.participants = participants
        self.myId = myId
        self.myName = myName
        loadOfflineMessages()
        listenChatMeta()
        listenMessages()   // 🔥🔥🔥 BẮT BUỘC
        EventManager.shared.preloadUsersIfNeeded()
    }
    
    private var offlineKey: String {
        "offline_messages_\(eventId)_\(myId)"
    }


    deinit {
        listener?.remove()
    }

    // MARK: - Ensure chat exists (BẮT BUỘC)
    @MainActor
    func ensureChatExists(eventEndTime: Date) async throws {
        let ref = db.collection("chats").document(eventId)

        let snap = try await ref.getDocument()
        if snap.exists { return }

        try await ref.setData([
            "participants": participants,
            "eventEndTime": Timestamp(date: eventEndTime),
            "createdAt": Timestamp()
        ])
    }



    // MARK: - Realtime listener
    func listenMessages() {
        listener?.remove()

        listener = db.collection("chats")
            .document(eventId)
            .collection("messages")
            .order(by: "timestamp")
            .limit(toLast: 100)
            .addSnapshotListener { snap, _ in
                guard let snap else { return }

                let serverMessages: [ChatMessage] = snap.documents.compactMap { doc in
                    let data = doc.data()

                    guard
                        let senderId = data["senderId"] as? String,
                        let timestamp = (data["timestamp"] as? Timestamp)?.dateValue()
                    else {
                        return nil
                    }

                    // ⭐ FALLBACK NAME (QUAN TRỌNG)
                    EventManager.shared.fetchUserNameIfNeeded(uid: senderId)

                    let senderName =
                        (data["senderName"] as? String)
                        ?? EventManager.shared.userNames[senderId]
                        ?? senderId



                    let text = data["text"] as? String ?? ""
                    let seenBy = data["seenBy"] as? [String: Bool] ?? [:]
                    let lat = data["latitude"] as? Double
                    let lon = data["longitude"] as? Double

                    return ChatMessage(
                        id: doc.documentID,
                        clientId: doc.documentID,
                        text: text,
                        senderId: senderId,
                        senderName: senderName,
                        timestamp: timestamp,
                        seenBy: seenBy,
                        latitude: lat,
                        longitude: lon,
                        sendStatus: .sent
                    )
                }


                DispatchQueue.main.async {
                    let pending = self.messages.filter {
                        $0.sendStatus == .sending || $0.sendStatus == .failed
                    }

                    let merged = pending.filter { local in
                        !serverMessages.contains(where: {
                            $0.clientId == local.clientId
                        })
                    } + serverMessages

                    self.messages = merged.sorted { $0.timestamp < $1.timestamp }
                    self.saveOfflineMessages()
                }
            }
    }

    private func saveOfflineMessages() {
        let pending = messages.filter {
            $0.sendStatus == .sending || $0.sendStatus == .failed
        }
        guard !pending.isEmpty else {
            UserDefaults.standard.removeObject(forKey: offlineKey)
            return
        }
        guard let data = try? JSONEncoder().encode(pending) else { return }
        UserDefaults.standard.set(data, forKey: offlineKey)
    }

    private func loadOfflineMessages() {
        guard
            let data = UserDefaults.standard.data(forKey: offlineKey),
            let cached = try? JSONDecoder().decode([ChatMessage].self, from: data)
        else { return }
        // All cached messages are pending — mark as .sending for retry
        self.messages = cached.map { msg in
            var m = msg
            m.sendStatus = .sending
            return m
        }
    }
    
    func retryPendingMessagesIfNeeded() {
        guard NetworkMonitor.shared.isOnline else { return }

        let pendingMessages = messages.filter {
            $0.sendStatus == .sending || $0.sendStatus == .failed
        }

        guard !pendingMessages.isEmpty else { return }

        guard !didRetryOnce else { return }
        didRetryOnce = true

        let chatRef = db.collection("chats").document(eventId)

        for msg in pendingMessages {

            var messageData: [String: Any] = [
                "senderId": msg.senderId,
                "senderName": msg.senderName ?? "",
                "timestamp": Timestamp(date: msg.timestamp),
                "seenBy": msg.seenBy ?? [msg.senderId: true]
            ]

            if let lat = msg.latitude, let lon = msg.longitude {
                messageData["latitude"] = lat
                messageData["longitude"] = lon
                messageData["text"] = String(localized: "location_sent")
            } else {
                messageData["text"] = msg.text
            }

            chatRef.collection("messages")
                .document(msg.id)
                .setData(messageData, merge: true) { error in

                    DispatchQueue.main.async {
                        if let index = self.messages.firstIndex(where: {
                            $0.id == msg.id
                        }) {
                            self.messages[index].sendStatus =
                                error == nil ? .sent : .failed
                        }

                        // ⭐ nếu còn lỗi → cho phép retry lần sau
                        if error != nil {
                            self.didRetryOnce = false
                        }

                        self.saveOfflineMessages()
                    }
                }
        }
    }




    @MainActor
    func stopListening() {
        listener?.remove()
        listener = nil
    }


    
    private func buildUnreadMap() -> [String: Bool] {
        var map: [String: Bool] = [:]
        for uid in participants {
            map[uid] = (uid != myId)
        }
        return map
    }


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

        let isOnline = NetworkMonitor.shared.isOnline
        let chatRef = db.collection("chats").document(eventId)

        // ⭐ 1. TẠO LOCAL MESSAGE (CHO UI)
        let uuid = UUID().uuidString

        let localMessage = ChatMessage(
            id: uuid,
            clientId: uuid,
            text: text,
            senderId: myId,
            senderName: myName,
            timestamp: Date(),
            seenBy: [myId: true],
            sendStatus: .sending
        )

        // ⭐ 2. APPEND NGAY → UI PHẢN HỒI LIỀN
        messages.append(localMessage)
        messageText = ""
        saveOfflineMessages()
        // ⭐ 3. UPDATE META + COUNT (KHÔNG PHỤ THUỘC ONLINE)
        chatRef.updateData([
            "freeCount.\(myId)": FieldValue.increment(Int64(1))
        ])

        let displayName = EventManager.shared.displayName(for: myId)

        chatRef.setData([
            "lastMessage": "\(displayName): \(text)",
            "lastMessageTime": Timestamp(),
            "unread": buildUnreadMap()
        ], merge: true)



        // ⭐ 4. NẾU OFFLINE → DỪNG Ở sending
        guard isOnline else { return }

        // ⭐ 5. NẾU ONLINE → GỬI FIRESTORE
        let messageData: [String: Any] = [
            "text": text,
            "senderId": myId,
            "senderName": myName,
            "timestamp": Timestamp(),
            "seenBy": [myId: true]
        ]

        chatRef.collection("messages")
            .document(localMessage.id)
            .setData(messageData, merge: true) { error in
                DispatchQueue.main.async {
                    guard let index = self.messages.firstIndex(where: {
                        $0.id == localMessage.id
                    }) else { return }

                    if let error {
                        print("❌ Send failed:", error)
                        self.messages[index].sendStatus = .failed
                    } else {
                        self.messages[index].sendStatus = .sent
                    }
                    self.saveOfflineMessages()
                }
            }

    }





    // MARK: - Send location message
    func sendCurrentLocation(
        lat: Double,
        lon: Double,
        isPremium: Bool,
        onLimitReached: @escaping () -> Void
    ) {
        // 🔒 Check limit
        if reachedFreeLimit && !isPremium {
            onLimitReached()
            return
        }

        let isOnline = NetworkMonitor.shared.isOnline
        let chatRef = db.collection("chats").document(eventId)

        // ⭐ 1. LOCAL MESSAGE (UI)
        let uuid = UUID().uuidString

        let localMessage = ChatMessage(
            id: uuid,
            clientId: uuid,
            text: String(localized: "location_sent"),
            senderId: myId,
            senderName: myName,
            timestamp: Date(),
            seenBy: [myId: true],
            latitude: lat,
            longitude: lon,
            sendStatus: .sending
        )

        messages.append(localMessage)

        // ⭐ 2. META + COUNT (luôn chạy)
        chatRef.updateData([
            "freeCount.\(myId)": FieldValue.increment(Int64(1))
        ])

        let displayName = EventManager.shared.displayName(for: myId)

        chatRef.setData([
            "lastMessage": "\(displayName): \(String(localized: "location_sent"))",
            "lastMessageTime": Timestamp(),
            "unread": buildUnreadMap()

        ], merge: true)


        // ⭐ 3. OFFLINE → UI giữ sending
        guard isOnline else { return }

        // ⭐ 4. ONLINE → GỬI FIRESTORE
        let messageData: [String: Any] = [
            "latitude": lat,
            "longitude": lon,
            "senderId": myId,
            "senderName": myName,
            "timestamp": Timestamp(),
            "seenBy": [myId: true]
        ]

        chatRef.collection("messages")
            .document(localMessage.id)
            .setData(messageData, merge: true) { error in
                DispatchQueue.main.async {
                    guard let index = self.messages.firstIndex(where: {
                        $0.id == localMessage.id
                    }) else { return }

                    if let error {
                        print("❌ Send location failed:", error)
                        self.messages[index].sendStatus = .failed
                    } else {
                        self.messages[index].sendStatus = .sent
                    }
                    self.saveOfflineMessages()
                }
            }

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
        let chatRef = db.collection("chats").document(eventId)

        chatRef.collection("messages")
            .whereField("senderId", isNotEqualTo: myId)
            .order(by: "senderId")
            .order(by: "timestamp", descending: true)
            .limit(to: 100)
            .getDocuments { snap, _ in
                guard let docs = snap?.documents else { return }

                let batch = self.db.batch()
                var hasUpdates = false

                for doc in docs {
                    let seenBy = doc.data()["seenBy"] as? [String: Bool] ?? [:]
                    if seenBy[self.myId] != true {
                        batch.updateData(
                            ["seenBy.\(self.myId)": true],
                            forDocument: doc.reference
                        )
                        hasUpdates = true
                    }
                }

                batch.updateData(
                    ["unread.\(self.myId)": false],
                    forDocument: chatRef
                )

                batch.commit()
            }
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
            "unread": buildUnreadMap()
        ], merge: true)
    }
   
    }

