
import SwiftUI
import Combine
import Foundation
import FirebaseFirestore


struct ChatMessage: Identifiable, Codable {
    @DocumentID var id: String?
    var text: String
    var senderId: String
    var senderName: String
    var timestamp: Date
    var seenBy: [String: Bool]?

    init(
        id: String? = nil,
        text: String,
        senderId: String,
        senderName: String,
        timestamp: Date = Date(),
        seenBy: [String: Bool] = [:]
    ) {
        self.id = id
        self.text = text
        self.senderId = senderId
        self.senderName = senderName
        self.timestamp = timestamp
        self.seenBy = seenBy
    }
}

import Foundation
import FirebaseFirestore
import FirebaseAuth

class ChatViewModel: ObservableObject {
    @Published var messages: [ChatMessage] = []
    @Published var messageText: String = ""
    @Published var unreadCount = 0
    @Published var limitReached = false

    private let db = Firestore.firestore()
    private var listener: ListenerRegistration?

    let eventId: String
    let otherUserId: String
    let myId: String
    let myName: String

    init(eventId: String, otherUserId: String, myName: String) {
        self.eventId = eventId
        self.otherUserId = otherUserId
        self.myId = Auth.auth().currentUser?.uid ?? ""
        self.myName = myName

        startListener()
        markSeen()
    }

    deinit {
        listener?.remove()
    }

    // MARK: - Load realtime messages
    func startListener() {
        listener = db.collection("chats")
            .document(eventId)
            .collection("messages")
            .order(by: "timestamp")
            .limit(toLast: 50)
            .addSnapshotListener { snap, err in
                guard let docs = snap?.documents else { return }
                self.messages = docs.compactMap { try? $0.data(as: ChatMessage.self) }
            }
    }

    // MARK: - Send message
    func sendMessage() {
        guard !messageText.trimmingCharacters(in: .whitespaces).isEmpty else { return }

        let message = ChatMessage(
            text: messageText,
            senderId: myId,
            senderName: myName,
            timestamp: Date(),
            seenBy: [myId: true]
        )

        let chatRef = db.collection("chats").document(eventId)

        do {
            try chatRef.collection("messages").addDocument(from: message)

            // Update metadata
            chatRef.setData([
                "lastMessage": messageText,
                "lastMessageTime": Timestamp(date: Date()),
                "unread": [ otherUserId : true ]   // ✔ đúng
            ], merge: true)

            messageText = ""

        } catch {
            print("❌ Error sending message:", error)
        }
    }

    // MARK: - Mark messages seen
    func markSeen() {
        let chatRef = db.collection("chats").document(eventId)

        chatRef.collection("messages")
            .getDocuments { snap, _ in
                snap?.documents.forEach { doc in
                    doc.reference.updateData([
                        "seenBy.\(self.myId)": true
                    ])
                }
            }

        chatRef.updateData([
            "unread.\(myId)": false
        ])
    }

    // MARK: - Auto delete chat when event is past
    func autoDeleteIfPast(_ eventEndTime: Date) {
        if eventEndTime > Date() { return }

        let chatRef = db.collection("chats").document(eventId)

        chatRef.collection("messages")
            .getDocuments { snap, _ in
                snap?.documents.forEach { $0.reference.delete() }
            }

        chatRef.delete()
    }
}


import SwiftUI

struct ChatView: View {
    let eventId: String
    let otherUserId: String
    let otherName: String
    let eventEndTime: Date

    @EnvironmentObject var session: SessionStore
    @StateObject var vm: ChatViewModel

    init(eventId: String, otherUserId: String, otherName: String, eventEndTime: Date) {
        self.eventId = eventId
        self.otherUserId = otherUserId
        self.otherName = otherName
        self.eventEndTime = eventEndTime

        _vm = StateObject(
            wrappedValue: ChatViewModel(
                eventId: eventId,
                otherUserId: otherUserId,
                myName: SessionStore().currentUserName
            )
        )
    }

    var body: some View {
        VStack(spacing: 0) {

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 12) {
                        ForEach(vm.messages) { msg in
                            bubble(msg)
                        }
                    }
                    .padding()
                }
                .onChange(of: vm.messages.count) { _, _ in
                    if let last = vm.messages.last?.id {
                        proxy.scrollTo(last, anchor: .bottom)
                    }
                }
            }

            Divider()

            HStack {
                TextField(String(localized: "enter_message"), text: $vm.messageText)
                    .textFieldStyle(.roundedBorder)

                Button {
                    vm.sendMessage()
                } label: {
                    Image(systemName: "paperplane.fill")
                        .font(.title2)
                        .padding(.horizontal)
                }
            }
            .padding()
        }
        .navigationTitle(otherName)
        .onAppear {
            vm.markSeen()
            vm.autoDeleteIfPast(eventEndTime)
        }
    }

    // MARK: - Bubble
    private func bubble(_ msg: ChatMessage) -> some View {
        let isMe = msg.senderId == session.currentUserId

        return HStack {
            if isMe { Spacer(minLength: 40) }

            VStack(alignment: isMe ? .trailing : .leading) {

                if !isMe {
                    Text(msg.senderName)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

                Text(msg.text)
                    .padding(10)
                    .background(isMe ? Color.blue.opacity(0.9) : Color.gray.opacity(0.2))
                    .foregroundColor(isMe ? .white : .primary)
                    .cornerRadius(12)

                if isMe {
                    let seen = msg.seenBy?[otherUserId] == true
                    Text(seen ? String(localized:"seen") : String(localized:"delivered"))
                        .font(.caption2)
                        .foregroundColor(.gray)
                }
            }

            if !isMe { Spacer(minLength: 40) }
        }
        .id(msg.id)
    }
}


extension EventManager {
    func cleanChatIfEventIsPast(_ event: CalendarEvent) {
        if event.endTime > Date() { return }

        let db = Firestore.firestore()
        let ref = db.collection("chats").document(event.id)

        // delete messages
        ref.collection("messages").getDocuments { snap, _ in
            snap?.documents.forEach { $0.reference.delete() }
        }

        ref.delete()
    }
}

import Foundation
import FirebaseFirestore
import FirebaseAuth

class ChatMetaViewModel: ObservableObject {
    @Published var lastMessage: String = ""
    @Published var unread: Bool = false

    private let db = Firestore.firestore()
    private let eventId: String
    private let myId: String
    private var listener: ListenerRegistration?

    init(eventId: String) {
        self.eventId = eventId
        self.myId = Auth.auth().currentUser?.uid ?? ""
        listen()
    }

    deinit { listener?.remove() }

    private func listen() {
        listener = db.collection("chats")
            .document(eventId)
            .addSnapshotListener { snap, _ in
                guard let data = snap?.data() else { return }

                self.lastMessage = data["lastMessage"] as? String ?? ""

                let unreadDict = data["unread"] as? [String: Bool] ?? [:]
                self.unread = unreadDict[self.myId] ?? false
            }
    }
}

import SwiftUI

struct EventRowWithChat: View {
    let event: CalendarEvent
    let timeFontSize: Int
    let timeColorHex: String
    let showOwnerLabel: Bool
    @EnvironmentObject var eventManager: EventManager

    @StateObject private var chatMeta: ChatMetaViewModel

    init(event: CalendarEvent,
         timeFontSize: Int = 14,
         timeColorHex: String = "#333333",
         showOwnerLabel: Bool = true)
    {
        self.event = event
        self.timeFontSize = timeFontSize
        self.timeColorHex = timeColorHex
        self.showOwnerLabel = showOwnerLabel
        _chatMeta = StateObject(wrappedValue: ChatMetaViewModel(eventId: event.id))
    }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Circle()
                .fill(Color(hex: event.colorHex.isEmpty ? "#FF0000" : event.colorHex))
                .frame(width: 12, height: 12)

            VStack(alignment: .leading, spacing: 4) {
                Text(event.title).font(.headline)

                if showOwnerLabel {
                    Text(originLabel(for: event))
                        .font(.caption)
                        .foregroundColor(.blue)
                }

                if showOwnerLabel {
                    if event.origin == .iCreatedForOther {
                        HStack(spacing: 4) {
                            UserNameView(uid: event.createdBy)
                            Text("→")
                            UserNameView(uid: event.owner)
                        }
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    } else {
                        Text(displayName(for: event, uid: event.createdBy, eventManager: eventManager))
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }

                Text("\(formattedTime(event.startTime)) - \(formattedTime(event.endTime))")
                    .font(.system(size: CGFloat(timeFontSize), weight: .regular))
                    .foregroundColor(Color(hex: timeColorHex))

                // CHAT PREVIEW + BADGE
                HStack(spacing: 6) {
                    if !chatMeta.lastMessage.isEmpty {
                        Text(chatMeta.lastMessage)
                            .font(.caption)
                            .foregroundColor(.gray)
                            .lineLimit(1)
                    }
                    if chatMeta.unread {
                        Circle()
                            .fill(Color.red)
                            .frame(width: 8, height: 8)
                    }
                }
                .padding(.top, 2)
            }

            Spacer()
        }
        .contentShape(Rectangle())
    }

    // Helpers: reuse the same formatters as your main view (copy or call shared funcs)
    private func formattedTime(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }

    // You need to either implement these helpers here or access global ones:
    private func originLabel(for ev: CalendarEvent) -> String {
        let ownerPrefix = String(localized: "owner_prefix")
        return "\(ownerPrefix) \(ev.owner)"
    }
}

struct ChatButtonWithBadge: View {
    let event: CalendarEvent
    let otherUserId: String

    @EnvironmentObject var session: SessionStore
    @StateObject private var chatMeta: ChatMetaViewModel

    init(event: CalendarEvent, otherUserId: String) {
        self.event = event
        self.otherUserId = otherUserId
        _chatMeta = StateObject(wrappedValue: ChatMetaViewModel(eventId: event.id))
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {

            NavigationLink {
                ChatView(
                    eventId: event.id,
                    otherUserId: otherUserId,
                    otherName: "",
                    eventEndTime: event.endTime
                )
            } label: {

                Image(systemName: "bubble.right.fill")
                    .symbolRenderingMode(.monochrome)        // ⭐ CỰC QUAN TRỌNG
                    .foregroundColor(chatMeta.unread ? .red : .blue)
                    .font(.system(size: 20))

            }

            // Badge đỏ như cũ
            if chatMeta.unread {
                Circle()
                    .fill(Color.red)
                    .frame(width: 10, height: 10)
                    .offset(x: 6, y: -4)
            }
        }
    }
}
