
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
            .addSnapshotListener { snap, err in
                guard let snap = snap else { return }

                for change in snap.documentChanges {
                    switch change.type {
                    case .added:
                        if let msg = try? change.document.data(as: ChatMessage.self) {
                            self.messages.append(msg)
                        }
                    default:
                        break
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
            latitude: lat,                 // ⭐ tọa độ truyền vào
            longitude: lon                 // ⭐ tọa độ truyền vào
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
            "unread": [otherUserId: true]
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

        chatRef.updateData([
            "unread.\(myId)": false
        ])

        db.collection("chats")
            .document(eventId)
            .collection("messages")
            .whereField("seenBy.\(myId)", isEqualTo: false)
            .getDocuments { snap, _ in
                snap?.documents.forEach { doc in
                    doc.reference.updateData([
                        "seenBy.\(self.myId)": true
                    ])
                }
            }
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
    @State private var showMapPicker = false
    @StateObject private var locationManager = LocationManager()
    @State private var addressCache: [String: String] = [:]
    @State private var sendCooldown = false

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

            HStack {
                // Nút GỬI VỊ TRÍ HIỆN TẠI
                Button {
                    sendMyGPS()
                } label: {
                    Image(systemName: "location.fill")
                        .font(.title2)
                }

                // Nút CHỌN VỊ TRÍ TRÊN BẢN ĐỒ
                Button {
                    showMapPicker = true
                } label: {
                    Image(systemName: "map.fill")
                        .font(.title2)
                }

                TextField(String(localized: "enter_message"), text: $vm.messageText)
                    .textFieldStyle(.roundedBorder)

                Button {
                    guard !sendCooldown else { return }
                    sendCooldown = true

                    vm.sendMessage()

                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                        sendCooldown = false
                    }
                } label: {
                    Image(systemName: "paperplane.fill")
                        .font(.title2)
                        .padding(.horizontal)
                }

            }
            .padding()

        }
        .sheet(isPresented: $showMapPicker) {
            MapPickerView(location: locationManager.location) { coord in
                vm.sendCurrentLocation(lat: coord.latitude, lon: coord.longitude)
            }
            .interactiveDismissDisabled(false)

        }
        .navigationTitle(otherName)
        .onAppear {
            vm.markSeen()
            vm.autoDeleteIfPast(eventEndTime)
        }
     

        
    }
    func fetchAddress(lat: Double, lon: Double, id: String, completion: @escaping (String) -> Void) {

        // Nếu đã có rồi → dùng cache
        if let cached = addressCache[id] {
            completion(cached)
            return
        }

        let geocoder = CLGeocoder()
        geocoder.reverseGeocodeLocation(CLLocation(latitude: lat, longitude: lon)) { places, _ in
            if let p = places?.first {
                let parts = [
                    p.name,
                    p.subLocality,
                    p.locality,
                    p.administrativeArea,
                    p.country
                ].compactMap { $0 }

                let addr = parts.joined(separator: ", ")

                DispatchQueue.main.async {
                    addressCache[id] = addr
                    completion(addr)
                }
            } else {
                DispatchQueue.main.async {
                    let fallback = String(localized: "location_sent")
                    addressCache[id] = fallback
                    completion(fallback)
                }
            }
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
