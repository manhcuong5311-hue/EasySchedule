
import SwiftUI
import Combine
import Foundation
import FirebaseFirestore


struct ChatMessage: Identifiable, Codable {
    @DocumentID var id: String?
    var text: String = ""
    var senderId: String
    var senderName: String
    var timestamp: Date
    var seenBy: [String: Bool]?
    var latitude: Double?
    var longitude: Double?
    
    init(
        id: String? = nil,
        text: String,
        senderId: String,
        senderName: String,
        timestamp: Date = Date(),
        seenBy: [String: Bool] = [:],
        latitude: Double? = nil,
        longitude: Double? = nil
    ) {
        self.id = id
        self.text = text
        self.senderId = senderId
        self.senderName = senderName
        self.timestamp = timestamp
        self.seenBy = seenBy
        self.latitude = latitude
        self.longitude = longitude
    }
    
}
struct TodoItem: Identifiable, Codable {
    @DocumentID var id: String?
    var text: String
    var doneBy: [String: Bool]
    var createdAt: Date
    
    init(id: String? = nil, text: String, doneBy: [String: Bool] = [:], createdAt: Date = Date()) {
        self.id = id
        self.text = text
        self.doneBy = doneBy
        self.createdAt = createdAt
    }
}


class TodoViewModel: ObservableObject {
    @Published var todos: [TodoItem] = []

    private let db = Firestore.firestore()
    private var listener: ListenerRegistration?

    let chatId: String
    let myId: String

    init(chatId: String, myId: String) {
        self.chatId = chatId
        self.myId = myId
    }

    deinit {
        listener?.remove()
    }

    func listen() {
        listener = db.collection("chats")
            .document(chatId)
            .collection("todos")
            .order(by: "createdAt")
            .addSnapshotListener { snap, err in
                guard let snap = snap else { return }
                let items = snap.documents.compactMap { try? $0.data(as: TodoItem.self) }

                DispatchQueue.main.async {
                    self.todos = items
                }
            }
    }


    func toggle(_ todo: TodoItem) {
        guard let id = todo.id else { return }

        let newValue = !(todo.doneBy[myId] ?? false)

        db.collection("chats")
            .document(chatId)
            .collection("todos")
            .document(id)
            .updateData([
                "doneBy.\(myId)": newValue
            ])
    }

    func stop() {
        listener?.remove()
        listener = nil
    }

    func addTodo(text: String) {
        let data: [String: Any] = [
            "text": text,
            "doneBy": [:],
            "createdAt": Timestamp(date: Date())
        ]

        db.collection("chats")
            .document(chatId)
            .collection("todos")
            .addDocument(data: data) { err in
                if let err = err {
                    print("❌ add TODO FAILED:", err)
                } else {
                    print("✅ TODO CREATED SUCCESS")
                }
            }
    }
    func delete(_ todo: TodoItem) {
        guard let id = todo.id else { return }

        db.collection("chats")
            .document(chatId)
            .collection("todos")
            .document(id)
            .delete { err in
                if let err = err {
                    print("❌ DELETE FAILED:", err)
                } else {
                    print("🗑️ TODO DELETED")
                }
            }
    }

}

struct TodoListView: View {
    let chatId: String
    let myId: String

    @StateObject private var vm: TodoViewModel
    @ObservedObject private var nameCache = SessionStore.UserNameCache.shared


    @State private var newTodo = ""
    @State private var showDeleteConfirm = false
    @State private var todoToDelete: TodoItem? = nil

    init(chatId: String, myId: String) {
        self.chatId = chatId
        self.myId = myId
        _vm = StateObject(wrappedValue: TodoViewModel(chatId: chatId, myId: myId))
    }

    var body: some View {
        NavigationView {
            VStack {
                List {
                    ForEach(vm.todos) { item in
                        todoRow(item)
                    }
                    .onDelete { indexSet in
                        if let index = indexSet.first {
                            todoToDelete = vm.todos[index]
                            showDeleteConfirm = true
                        }
                    }
                }

                HStack(spacing: 8) {

                    // INPUT TODO
                    TextField(
                        String(localized: "add_task_placeholder"),
                        text: $newTodo,
                        axis: .vertical
                    )
                    .lineLimit(1...3)
                    .font(.system(size: 16))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 20)
                            .fill(Color(.systemGray6))
                    )

                    // NÚT ADD
                    Button {
                        guard !newTodo.trimmingCharacters(in: .whitespaces).isEmpty else { return }
                        vm.addTodo(text: newTodo)
                        newTodo = ""
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(width: 40, height: 40)
                            .background(
                                newTodo.trimmingCharacters(in: .whitespaces).isEmpty
                                ? Color.gray.opacity(0.4)
                                : Color.blue
                            )
                            .clipShape(Circle())
                    }
                    .disabled(newTodo.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                .padding(.horizontal)
                .padding(.vertical, 10)
                .background(
                    Color(.systemBackground)
                        .ignoresSafeArea(edges: .bottom)
                )

            }
            .navigationTitle(String(localized: "todo_list_title"))
            .navigationBarTitleDisplayMode(.inline)
            .onAppear { vm.listen() }
            .onDisappear { vm.stop() }
            .alert(String(localized: "delete_confirm_title"), isPresented: $showDeleteConfirm) {
                Button(String(localized:"cancel"), role: .cancel) {}

                Button(String(localized:"delete"), role: .destructive) {
                    if let item = todoToDelete {
                        vm.delete(item)
                    }
                }
            }
        }
    }

    // MARK: - Row View
    private func todoRow(_ item: TodoItem) -> some View {
        HStack(alignment: .top, spacing: 12) {

            // Tick
            Button {
                vm.toggle(item)
            } label: {
                Image(systemName: (item.doneBy[myId] ?? false)
                       ? "checkmark.circle.fill"
                       : "circle")
                    .font(.system(size: 22))
                    .foregroundColor(.blue)
            }

            VStack(alignment: .leading, spacing: 6) {

                // ⭐⭐ HIỆN TEXT CỦA TODO (MẤT DÒNG NÀY NÊN UI TRỐNG)
                Text(item.text)
                    .font(.body)
                    .foregroundColor(.primary)
                    .lineLimit(nil)

                // Hiện người tick
                ForEach(Array(item.doneBy.keys).sorted(), id: \.self) { uid in
                    if item.doneBy[uid] == true {

                        let name = uid == myId
                        ? String(localized:"you")
                            : (nameCache.names[uid] ?? uid)

                        Text("✓ \(name)")
                            .font(.caption2)
                            .foregroundColor(uid == myId ? .blue : .green)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.gray.opacity(0.15))
                            .cornerRadius(6)
                            .onAppear {
                                if nameCache.names[uid] == nil {
                                    SessionStore.UserNameCache.shared.getName(for: uid) { _ in }
                                }
                            }

                    }
                }
            }

            Spacer()
        }
        .padding(.vertical, 6)
    }

}
import FirebaseFirestore


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
        listener?.remove()

        listener = db.collection("chats")
            .document(eventId)
            .collection("messages")
            .order(by: "timestamp")
            .limit(toLast: 20)    // ⭐ CHỈ LOAD 50 TIN GẦN NHẤT
            .addSnapshotListener { snap, err in
                guard let snap = snap else { return }

                DispatchQueue.main.async {
                    self.messages = snap.documents.compactMap {
                        try? $0.data(as: ChatMessage.self)
                    }
                }
            }
    }


    
    func sendCurrentLocation(lat: Double, lon: Double) {
        let message = ChatMessage(
            text: "[location]",
            senderId: myId,
            senderName: myName,
            timestamp: Date(),
            seenBy: [myId: true],
            latitude: lat,
            longitude: lon
        )
        
        let chatRef = db.collection("chats").document(eventId)
        
        do {
            try chatRef.collection("messages").addDocument(from: message)
        } catch {
            print("❌ Failed to send location:", error)
        }
        
        chatRef.setData([
            "lastMessage": "📍 Location",
            "lastMessageTime": Timestamp(date: Date()),
            "unread": [
                myId: false,          // Tôi đã đọc
                otherUserId: true     // Người kia chưa đọc
            ]
        ], merge: true)
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
                "unread": [
                    myId: false,
                    otherUserId: true
                ]
            ], merge: true)

            
            messageText = ""
            
        } catch {
            print("❌ Error sending message:", error)
        }
    }
    
    // MARK: - Mark messages seen
    func markSeen() {
        let chatRef = db.collection("chats").document(eventId)

        chatRef.updateData([
            "unread.\(myId)": false
        ])
    }

    
    
    // MARK: - Auto delete chat when event is past
    func autoDeleteIfPast(_ eventEndTime: Date) {
        if eventEndTime > Date() { return }

        let chatRef = db.collection("chats").document(eventId)

        // 🧹 delete messages
        chatRef.collection("messages").getDocuments { snap, _ in
            snap?.documents.forEach { $0.reference.delete() }
        }

        // 🧹 delete todos
        chatRef.collection("todos").getDocuments { snap, _ in
            snap?.documents.forEach { $0.reference.delete() }
        }

        // 🗑 delete chat doc
        chatRef.delete()
    }

}


import SwiftUI

struct ChatView: View {
    let eventId: String
    let otherUserId: String
    let otherName: String
    let eventEndTime: Date
    let eventInfo: CalendarEvent

    @EnvironmentObject var session: SessionStore
    @StateObject var vm: ChatViewModel
    @State private var showMapPicker = false
    @StateObject private var locationManager = LocationManager()
    @State private var addressCache: [String: String] = [:]
    @State private var sendCooldown = false
    @State private var showLocationConfirm = false
    @State private var geocodeInProgress: Set<String> = []
    @State private var showTodoList = false

    private let geocoder = CLGeocoder()

    
    init(eventId: String, otherUserId: String, otherName: String, eventEndTime: Date,eventInfo: CalendarEvent ) {
        self.eventId = eventId
        self.otherUserId = otherUserId
        self.otherName = otherName
        self.eventEndTime = eventEndTime
        self.eventInfo = eventInfo     // ⭐ GÁN GIÁ TRỊ
               
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
            eventHeader
            Divider()
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 12) {
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

            HStack(spacing: 8) {

                // NÚT +
                Menu {
                    Button {
                        showLocationConfirm = true
                    } label: {
                        Label(String(localized: "send_current_location"), systemImage: "location.fill")
                    }

                    Button {
                        showMapPicker = true
                    } label: {
                        Label(String(localized: "pick_location_on_map"), systemImage: "map.fill")
                    }
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.blue)
                        .frame(width: 36, height: 36)
                        .background(Color.blue.opacity(0.12))
                        .clipShape(Circle())
                }
                .alert(String(localized:"you_sure_sending_your_location"), isPresented: $showLocationConfirm) {
                    Button(String(localized:"cancel"), role: .cancel) {}
                    Button(String(localized:"send"), role: .destructive) {
                        sendMyGPS()
                    }
                }

                // INPUT + SEND (1 KHỐI)
                HStack(spacing: 6) {

                    TextField(
                        String(localized: "enter_message"),
                        text: $vm.messageText,
                        axis: .vertical
                    )
                    .lineLimit(1...4)
                    .font(.system(size: 16))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)

                    Button {
                        guard !sendCooldown,
                              !vm.messageText.trimmingCharacters(in: .whitespaces).isEmpty
                        else { return }

                        sendCooldown = true
                        vm.sendMessage()

                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            sendCooldown = false
                        }
                    } label: {
                        Image(systemName: "paperplane.fill")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(
                                vm.messageText.isEmpty ? .gray : .white
                            )
                            .frame(width: 36, height: 36)
                            .background(
                                vm.messageText.isEmpty
                                ? Color.gray.opacity(0.3)
                                : Color.blue
                            )
                            .clipShape(Circle())
                    }
                    .disabled(vm.messageText.isEmpty)
                }
                .background(
                    RoundedRectangle(cornerRadius: 22)
                        .fill(Color(.systemGray6))
                )
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(
                Color(.systemBackground)
                    .ignoresSafeArea(edges: .bottom)
            )

        }
        .sheet(isPresented: $showMapPicker) {
            MapPickerView(location: locationManager.location) { coord in
                vm.sendCurrentLocation(lat: coord.latitude, lon: coord.longitude)
            }
            .interactiveDismissDisabled(false)
            
        }
        .navigationTitle(otherName)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    showTodoList = true
                } label: {
                    Image(systemName: "checklist")
                        .font(.system(size: 20))
                }
            }
        }
        .sheet(isPresented: $showTodoList) {
            TodoListView(chatId: eventId, myId: session.currentUserId ?? "")
        }


        .onAppear {
            vm.markSeen()
            vm.autoDeleteIfPast(eventEndTime)
        }
        
        
        
    }
    func fetchAddress(lat: Double, lon: Double, id: String, completion: @escaping (String) -> Void) {

        // 1. Dùng cache
        if let cached = addressCache[id] {
            completion(cached)
            return
        }

        // 2. Không request lại nếu đang chạy
        if geocodeInProgress.contains(id) {
            return
        }

        // 3. Đánh dấu đang xử lý
        geocodeInProgress.insert(id)

        // 4. Cancel yêu cầu cũ
        geocoder.cancelGeocode()

        let location = CLLocation(latitude: lat, longitude: lon)

        geocoder.reverseGeocodeLocation(location) { places, error in
            DispatchQueue.main.async {
                // Xóa flag đang xử lý
                geocodeInProgress.remove(id)

                let fallback = String(localized: "location_sent")

                guard let place = places?.first, error == nil else {
                    addressCache[id] = fallback
                    completion(fallback)
                    return
                }

                let parts = [
                    place.name,
                    place.subLocality,
                    place.locality,
                    place.administrativeArea,
                    place.country
                ].compactMap { $0 }

                let result = parts.joined(separator: ", ")

                addressCache[id] = result
                completion(result)
            }
        }
    }
    private var eventHeader: some View {
        HStack {
            Text("\(eventInfo.title) · \(timeSummary)")
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(1)

            Spacer()
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 12)
        .background(Color(.systemGray6))
        .cornerRadius(10)
        .padding(.horizontal)
        .padding(.top, 6)
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
                // ⭐ Tin nhắn định vị
                if let lat = msg.latitude, let lon = msg.longitude {
                    
                    VStack(alignment: isMe ? .trailing : .leading, spacing: 6) {
                        
                        // Hiển thị địa chỉ
                        Text(addressCache[msg.id ?? ""] ?? String(localized: "fetching_address"))
                            .font(.subheadline)
                            .foregroundColor(isMe ? .white : .primary)
                            .onAppear {
                                if addressCache[msg.id ?? ""] == nil {
                                    fetchAddress(lat: lat, lon: lon, id: msg.id ?? "") { _ in }
                                }
                            }
                        
                        // Nút mở Apple Maps
                        Button {
                            if let url = URL(string: "http://maps.apple.com/?ll=\(lat),\(lon)") {
                                UIApplication.shared.open(url)
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "map")
                                Text(String(localized: "open_in_apple_maps"))
                            }
                            .font(.caption)
                        }
                        .padding(8)
                        .background(isMe ? Color.white.opacity(0.25) : Color.blue.opacity(0.15))
                        .cornerRadius(10)
                    }
                    .padding(10)
                    .background(isMe ? Color.blue.opacity(0.9) : Color.gray.opacity(0.2))
                    .foregroundColor(isMe ? .white : .primary)
                    .cornerRadius(12)
                }
                
                // ⭐ Ngược lại là tin nhắn văn bản bình thường
                else {
                    Text(msg.text)
                        .padding(10)
                        .background(isMe ? Color.blue.opacity(0.9) : Color.gray.opacity(0.2))
                        .foregroundColor(isMe ? .white : .primary)
                        .cornerRadius(12)
                }
                
                
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
    func sendMyGPS() {
        guard let loc = locationManager.location else { return }
        vm.sendCurrentLocation(
            lat: loc.coordinate.latitude,
            lon: loc.coordinate.longitude
        )
    }
    private var timeSummary: String {
        let dfDate = DateFormatter()
        dfDate.locale = Locale(identifier: "vi_VN")
        dfDate.dateFormat = "dd/MM/yyyy"

        let dfTime = DateFormatter()
        dfTime.locale = Locale(identifier: "vi_VN")
        dfTime.dateFormat = "HH:mm"

        let date = dfDate.string(from: eventInfo.startTime)
        let start = dfTime.string(from: eventInfo.startTime)
        let end = dfTime.string(from: eventInfo.endTime)

        return "\(date) · \(start)–\(end)"
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
    
    // ⭐ giữ VM optional
    @State private var metaVM: ChatMetaViewModel? = nil

    // ⭐ computed → luôn trả về instance hợp lệ
    private var chatMeta: ChatMetaViewModel {
        metaVM ?? eventManager.chatMeta(for: event.id)
    }

    // ❗ init KHÔNG được động chạm vào environmentObject
    init(event: CalendarEvent,
         timeFontSize: Int = 14,
         timeColorHex: String = "#333333",
         showOwnerLabel: Bool = true)
    {
        self.event = event
        self.timeFontSize = timeFontSize
        self.timeColorHex = timeColorHex
        self.showOwnerLabel = showOwnerLabel
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
                        Text(displayName(for: event,
                                         uid: event.createdBy,
                                         eventManager: eventManager))
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }

                Text("\(formattedTime(event.startTime)) - \(formattedTime(event.endTime))")
                    .font(.system(size: CGFloat(timeFontSize), weight: .regular))
                    .foregroundColor(Color(hex: timeColorHex))

                // ⭐ Chat preview
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
        .onAppear {
            if metaVM == nil {
                metaVM = eventManager.chatMeta(for: event.id)
            }
        }
    }
    
    private func formattedTime(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }
    
    private func originLabel(for ev: CalendarEvent) -> String {
        let ownerPrefix = String(localized: "owner_prefix")
        return "\(ownerPrefix) \(ev.owner)"
    }
}

import CoreLocation

class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    
    @Published var location: CLLocation?
    
    override init() {
        super.init()
        manager.delegate = self
        manager.requestWhenInUseAuthorization()
        manager.startUpdatingLocation()
    }
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locs: [CLLocation]) {
        location = locs.first
    }
}


struct ChatButtonWithBadge: View {
    let event: CalendarEvent
    let otherUserId: String
    
    @EnvironmentObject var session: SessionStore
    @EnvironmentObject var eventManager: EventManager
    
    @State private var metaVM: ChatMetaViewModel? = nil   // ⭐ optional để gán sau
    
    // ⭐ computed property → luôn có VM hợp lệ
    private var chatMeta: ChatMetaViewModel {
        metaVM ?? eventManager.chatMeta(for: event.id)
    }
    
    var body: some View {
        ZStack(alignment: .topTrailing) {
            
            NavigationLink {
                ChatView(
                    eventId: event.id,
                    otherUserId: otherUserId,
                    otherName: "",
                    eventEndTime: event.endTime,
                    eventInfo: event
                )
            } label: {
                Image(systemName: "bubble.right.fill")
                    .symbolRenderingMode(.monochrome)
                    .foregroundColor(chatMeta.unread ? .red : .blue)
                    .font(.system(size: 20))
            }
            
            if chatMeta.unread {
                Circle()
                    .fill(Color.red)
                    .frame(width: 10, height: 10)
                    .offset(x: 6, y: -4)
            }
        }
        .onAppear {
            // ⭐ Gán 1 lần duy nhất, không tạo duplicate listener
            if metaVM == nil {
                metaVM = eventManager.chatMeta(for: event.id)
            }
        }
    }
}




import SwiftUI
import MapKit

struct MapPickerView: View {
    @Environment(\.dismiss) var dismiss
    let location: CLLocation?
    var onPick: (CLLocationCoordinate2D) -> Void
    
    @State private var region: MKCoordinateRegion
    
    init(location: CLLocation?, onPick: @escaping (CLLocationCoordinate2D) -> Void) {
        self.location = location
        self.onPick = onPick
        
        let coord = location?.coordinate ??
        CLLocationCoordinate2D(latitude: 10.7626, longitude: 106.6601)
        
        _region = State(initialValue: MKCoordinateRegion(
            center: coord,
            span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
        ))
    }
    
    var body: some View {
        ZStack {
            Map(coordinateRegion: $region, showsUserLocation: true)
                .ignoresSafeArea()
            
            Image(systemName: "mappin.circle.fill")
                .font(.system(size: 42))
                .foregroundColor(.red)
                .offset(y: -22)
            
            VStack {
                // NÚT ĐÓNG
                HStack {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 34))
                            .foregroundColor(.white)
                            .shadow(radius: 4)
                    }
                    .padding(.leading, 16)
                    .padding(.top, 30)
                    
                    Spacer()
                }
                
                Spacer()
                
                // NÚT VỀ VỊ TRÍ CỦA TÔI
                if let loc = location {
                    Button {
                        withAnimation {
                            region.center = loc.coordinate
                        }
                    } label: {
                        HStack {
                            Image(systemName: "location.fill")
                            Text(String(localized:"go_to_my_location"))
                        }
                        .padding(8)
                        .background(Color.white.opacity(0.9))
                        .cornerRadius(12)
                    }
                    .padding(.bottom, 8)
                }
                
                // NÚT CHỌN VỊ TRÍ
                Button(String(localized:"pick_location")) {
                    onPick(region.center)
                    dismiss()
                }
                .padding()
                .background(Color.blue)
                .foregroundColor(.white)
                .cornerRadius(12)
                .padding(.bottom, 40)
            }
        }
        .interactiveDismissDisabled(false)
    }
}

