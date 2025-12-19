
import SwiftUI
import Combine
import Foundation
import FirebaseFirestore
import FirebaseAuth
import CoreLocation
import MapKit

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
import Foundation

class ChatForegroundTracker {
    static let shared = ChatForegroundTracker()
    private init() {}

    // eventId đang mở chat
    var activeChatEventId: String? = nil
}

struct TodoItem: Identifiable, Codable {
    @DocumentID var id: String?
    var text: String
    var doneBy: [String: Bool]
    var createdAt: Date
    var createdBy: String   // ⭐️ THÊM

    init(
        id: String? = nil,
        text: String,
        doneBy: [String: Bool] = [:],
        createdAt: Date = Date(),
        createdBy: String
    ) {
        self.id = id
        self.text = text
        self.doneBy = doneBy
        self.createdAt = createdAt
        self.createdBy = createdBy
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
    var unfinishedCount: Int {
        todos.filter { !($0.doneBy[myId] ?? false) }.count
    }

    func listen() {
        listener?.remove()
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
            "createdAt": Timestamp(date: Date()),
            "createdBy": myId   // ⭐️ THÊM
        ]

        db.collection("chats")
            .document(chatId)
            .collection("todos")
            .addDocument(data: data)
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
    private let freeLimit = 5
    private let premiumLimit = 20
    @State private var showPaywall = false
    @StateObject private var vm: TodoViewModel
    @ObservedObject private var nameCache = SessionStore.UserNameCache.shared
    
    @ObservedObject private var network = NetworkMonitor.shared


    @State private var isSending = false

    @EnvironmentObject var premium: PremiumStoreViewModel
    @State private var newTodo = ""
    @State private var showDeleteConfirm = false
    @State private var todoToDelete: TodoItem? = nil
    enum TodoLimitAlertType: Identifiable {
        case freeLimit        // Free user vượt 5
        case chatMaxReached   // Chat premium vượt 20

        var id: Int { hashValue }
    }

    @State private var limitAlert: TodoLimitAlertType? = nil



    init(chatId: String, myId: String) {
        self.chatId = chatId
        self.myId = myId
        _vm = StateObject(wrappedValue: TodoViewModel(chatId: chatId, myId: myId))
    }

    var body: some View {
        NavigationView {
            VStack {
                
                // ===== OFFLINE BANNER =====
                if !network.isOnline {
                    HStack(spacing: 6) {
                        Image(systemName: "wifi.slash")
                        Text(String(localized: "offline_banner"))
                            .font(.caption)
                    }
                    .foregroundColor(.white)
                    .padding(8)
                    .frame(maxWidth: .infinity)
                    .background(Color.orange)
                }


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
                        guard !isSending else { return }

                        let text = newTodo.trimmingCharacters(in: .whitespaces)
                        guard !text.isEmpty else { return }

                        let limit = premium.isPremium ? premiumLimit : freeLimit

                        if vm.todos.count >= limit {
                            limitAlert = premium.isPremium ? .chatMaxReached : .freeLimit
                            return
                        }

                        isSending = true
                        vm.addTodo(text: text)
                        newTodo = ""

                        // 🔑 chống spam (offline & online)
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            isSending = false
                        }
                    }



                    label: {
                        Image(systemName: isSending ? "hourglass" : "plus")
                            .foregroundColor(.white)
                            .frame(width: 40, height: 40)
                            .background(isSending ? Color.gray : Color.blue)
                            .clipShape(Circle())
                    }
                    .disabled(isSending || newTodo.trimmingCharacters(in: .whitespaces).isEmpty)


                }
                .padding(.horizontal)
                .padding(.vertical, 10)

            }
            .navigationTitle(String(localized: "todo_list_title"))
            .navigationBarTitleDisplayMode(.inline)
            .onAppear { vm.listen()
            }
            .onDisappear { vm.stop()
            }
            .sheet(isPresented: $showPaywall) {
                PremiumUpgradeSheet()
                    .environmentObject(premium)
            }
            .alert(String(localized: "delete_confirm_title"), isPresented: $showDeleteConfirm) {
                Button(String(localized:"cancel"), role: .cancel) {}

                Button(String(localized:"delete"), role: .destructive) {
                    if let item = todoToDelete {
                        vm.delete(item)
                    }
                }
            }
            .alert(item: $limitAlert) { type in
                switch type {

                // ===== Free user vượt 5 =====
                case .freeLimit:
                    return Alert(
                        title: Text(String(localized: "todo_limit_title")),
                        message: Text(
                            String(
                                format: String(localized: "todo_free_limit_message"),
                                freeLimit
                            )
                        ),
                        primaryButton: .default(Text(String(localized: "upgrade_to_premium"))) {
                            showPaywall = true
                            limitAlert = nil
                        },
                        secondaryButton: .cancel {
                            limitAlert = nil
                        }
                    )

                // ===== Chat premium chạm 20 =====
                case .chatMaxReached:
                    return Alert(
                        title: Text(String(localized: "todo_limit_title")),
                        message: Text(String(localized: "todo_limit_reached_message")),
                        dismissButton: .default(Text(String(localized: "ok"))) {
                            limitAlert = nil
                        }
                    )
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

                        Text(
                            String(
                                format: String(localized: "todo_done_by"),
                                name
                            )
                        )

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









class ChatViewModel: ObservableObject {

    // MARK: - Published
    @Published var messages: [ChatMessage] = []
    @Published var messageText: String = ""
    @Published var reachedFreeLimit = false

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

        if !isPremium && reachedFreeLimit {
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

        chatRef.collection("messages").addDocument(data: messageData)
        // ⭐ TĂNG COUNTER CHO FREE
        if !isPremium {
            chatRef.updateData([
                "freeCount.\(myId)": FieldValue.increment(Int64(1))
            ])
        }

        // ⭐ PREMIUM → UNLOCK CHAT
        if isPremium {
            chatRef.setData([
                "premiumUnlocked": true
            ], merge: true)
        }

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
        if !isPremium && reachedFreeLimit {
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

        chatRef.collection("messages").addDocument(data: messageData)
        // ⭐ TĂNG COUNTER CHO FREE
        if !isPremium {
            chatRef.updateData([
                "freeCount.\(myId)": FieldValue.increment(Int64(1))
            ])
        }

        // ⭐ PREMIUM → UNLOCK CHAT
        if isPremium {
            chatRef.setData([
                "premiumUnlocked": true
            ], merge: true)
        }

        chatRef.setData([
            "lastMessage": String(localized: "location_message"),
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
                self.chatPremiumUnlocked = data["premiumUnlocked"] as? Bool ?? false

                let freeCount = data["freeCount"] as? [String: Int] ?? [:]
                self.freeSentCount = freeCount[self.myId] ?? 0

                let limit = self.chatPremiumUnlocked ? 100 : 10
                self.reachedFreeLimit = self.freeSentCount >= limit
            }
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
    @EnvironmentObject var premium: PremiumStoreViewModel
    @StateObject private var todoVM: TodoViewModel

    @State private var showLimitAlert = false
    @State private var showPremiumSheet = false

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
        _todoVM = StateObject(
               wrappedValue: TodoViewModel(
                   chatId: eventId,
                   myId: SessionStore().currentUserId ?? ""
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
                    .disabled(locked)
                    .opacity(locked ? 0.6 : 1)

                    Button {
                        guard !sendCooldown,
                              !vm.messageText.trimmingCharacters(in: .whitespaces).isEmpty
                        else { return }

                        sendCooldown = true
                        vm.sendMessage(
                            isPremium: premium.isPremium,
                            onLimitReached: {
                                showLimitAlert = true
                            }
                        )

                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            sendCooldown = false
                        }
                    } label: {
                        Image(systemName: "paperplane.fill")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(
                                locked || vm.messageText.isEmpty ? .gray : .white
                            )
                            .frame(width: 36, height: 36)
                            .background(
                                locked || vm.messageText.isEmpty
                                ? Color.gray.opacity(0.3)
                                : Color.blue
                            )
                            .clipShape(Circle())
                    }
                    .disabled(locked || vm.messageText.isEmpty)

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
                vm.sendCurrentLocation(
                    lat: coord.latitude,
                    lon: coord.longitude,
                    isPremium: premium.isPremium,
                    onLimitReached: {
                        showLimitAlert = true
                    }
                )

            }
            .interactiveDismissDisabled(false)
            
        }
        .navigationTitle(otherName)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                HStack(spacing: 8) {
                    // ⭐ Premium indicator
                    if premium.isPremium {
                        Image(systemName: "star.fill")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(AppColors.premiumGold)
                            .opacity(0.8)
                    }

                    Button {
                        showTodoList = true
                    } label: {
                        Image(systemName: "checklist")
                            .font(.system(size: 20))
                        if todoVM.unfinishedCount > 0 {
                                           Text("\(todoVM.unfinishedCount)")
                                               .font(.caption2.bold())
                                               .foregroundColor(.secondary)
                                       }
                    }
                }
            }
        }
        .alert(
            String(localized: "chat_limit_title"),
            isPresented: $showLimitAlert
        ) {
            Button(String(localized: "upgrade_to_premium")) {
                showLimitAlert = false
                showPremiumSheet = true
            }
            Button(String(localized: "wait_ok"), role: .cancel) {}
        } message: {
            Text(String(localized: "chat_limit_message"))
        }


        .sheet(isPresented: $showPremiumSheet) {
            PremiumUpgradeSheet()
        }


        .sheet(isPresented: $showTodoList) {
            TodoListView(chatId: eventId, myId: session.currentUserId ?? "")
        }
        .onAppear {
            ChatForegroundTracker.shared.activeChatEventId = eventId

            Task {
                await vm.ensureChatExists(
                    participants: [
                        session.currentUserId!,
                        otherUserId
                    ],
                    eventEndTime: eventEndTime
                )
            }
            vm.markSeen()
            vm.autoDeleteIfPast(eventEndTime)
            todoVM.listen()
        }
        .onDisappear {
            if ChatForegroundTracker.shared.activeChatEventId == eventId {
                ChatForegroundTracker.shared.activeChatEventId = nil
            }
            todoVM.stop()
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

    private var locked: Bool {
        !premium.isPremium && vm.reachedFreeLimit
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
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(isMe ? Color.blue.opacity(0.9) : Color.gray.opacity(0.2))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(
                                            (isMe && premium.isPremium)
                                            ? AppColors.premiumAccent.opacity(0.4)
                                            : Color.clear,
                                            lineWidth: 0.8
                                        )
                                )

                        )
                        .foregroundColor(isMe ? .white : .primary)
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
            lon: loc.coordinate.longitude,
            isPremium: premium.isPremium,
            onLimitReached: {
                showLimitAlert = true
            }
        )
    }



    private var timeSummary: String {
        let date = eventInfo.startTime.formatted(
            .dateTime.day().month().year()
        )

        let start = eventInfo.startTime.formatted(
            date: .omitted,
            time: .shortened
        )

        let end = eventInfo.endTime.formatted(
            date: .omitted,
            time: .shortened
        )

        return "\(date) · \(start)–\(end)"
    }

}



extension EventManager {
    
    func cleanChatIfEventIsPast(_ event: CalendarEvent) {
        if event.endTime > Date() { return }

        Firestore.firestore()
            .collection("chats")
            .document(event.id)
            .updateData([
                "expired": true
            ])
    }

}



class ChatMetaViewModel: ObservableObject {
    @Published var lastMessage: String = ""
    @Published var unread: Bool = false
    private var lastNotifiedMessage: String?
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
                    self.lastMessage = lastMsg
                    self.unread = isUnread

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
        metaVM!
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



class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()

    @Published var location: CLLocation?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        manager.requestWhenInUseAuthorization()
        manager.requestLocation() // 🔑 chỉ lấy 1 lần
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locs: [CLLocation]) {
        location = locs.first
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("Location error:", error)
    }
}


struct ChatButtonWithBadge: View {
    let event: CalendarEvent
    let otherUserId: String

    @EnvironmentObject var session: SessionStore
    @EnvironmentObject var eventManager: EventManager

    @State private var metaVM: ChatMetaViewModel?
    @State private var didBindMeta = false

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
                    .foregroundColor((metaVM?.unread ?? false) ? .red : .blue)
                    .font(.system(size: 20))
            }

            if metaVM?.unread == true {
                Circle()
                    .fill(Color.red)
                    .frame(width: 10, height: 10)
                    .offset(x: 6, y: -4)
            }
        }
        .onAppear {
            guard !didBindMeta else { return }
            didBindMeta = true
            metaVM = eventManager.chatMeta(for: event.id)
        }
    }
}





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

