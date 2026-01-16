//
//  ChatView.swift
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


struct ChatView: View {
    let eventId: String
       let otherUserId: String
       let otherName: String
       let eventEndTime: Date
       let eventInfo: CalendarEvent

       let myId: String
       let myName: String

    @EnvironmentObject var session: SessionStore
    @StateObject var vm: ChatViewModel
    
    @StateObject private var locationManager = LocationManager()
    @State private var addressCache: [String: String] = [:]
    
    @State private var sendCooldown = false
    @State private var geocodeInProgress: Set<String> = []
    
    @EnvironmentObject var premium: PremiumStoreViewModel
    @StateObject private var todoVM: TodoViewModel
   
    @State private var activeAlert: ChatAlert?
    @State private var activeSheet: ChatSheet?

    @State private var showActionPopover = false
    @EnvironmentObject var network: NetworkMonitor

    @EnvironmentObject var eventManager: EventManager
    @AppStorage("chat_my_preset") private var myPresetRaw: String = ChatColorPreset.blue.rawValue
    @AppStorage("chat_other_preset") private var otherPresetRaw: String = ChatColorPreset.graphite.rawValue





    private let geocoder = CLGeocoder()

    
    init(
        eventId: String,
        otherUserId: String,
        otherName: String,
        eventEndTime: Date,
        eventInfo: CalendarEvent,
        myId: String,
        myName: String
    ) {
        self.eventId = eventId
        self.otherUserId = otherUserId
        self.otherName = otherName
        self.eventEndTime = eventEndTime
        self.eventInfo = eventInfo
        self.myId = myId
        self.myName = myName

        _vm = StateObject(
            wrappedValue: ChatViewModel(
                eventId: eventId,
                otherUserId: otherUserId,
                myId: myId,
                myName: myName
            )
        )

        // ⭐ BẮT BUỘC
        _todoVM = StateObject(
            wrappedValue: TodoViewModel(
                chatId: eventId,
                myId: myId
            )
        )
    }


    
    var body: some View {
        VStack(spacing: 0) {
            eventHeader
            // ⭐ OFFLINE BANNER
                if !network.isOnline {
                    OfflineBannerView()
                        .padding(.horizontal)
                        .padding(.top, 4)
                        .padding(.bottom, 6)
                }
            Divider()
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(vm.messages, id: \.uiId) { msg in
                            bubble(msg)
                                .id(msg.uiId)
                        }
                    }
                    .padding()
                }
                .onChange(of: vm.messages.count) { _, _ in
                    if let last = vm.messages.last {
                        proxy.scrollTo(last.uiId, anchor: .bottom)
                    }
                }
            }
            Divider()

            HStack(spacing: 8) {

                // NÚT +
                Button {
                    if locked {
                        activeAlert = .limit
                        return
                    }
                    showActionPopover = true
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(locked ? .gray : .blue)
                        .frame(width: 36, height: 36)
                        .background((locked ? Color.gray : Color.blue).opacity(0.12))
                        .clipShape(Circle())
                }
                .popover(isPresented: $showActionPopover, arrowEdge: .bottom) {
                    actionMenuContent
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
                        vm.sendMessage(isPremium: premium.isPremium) {
                            activeAlert = .limit
                        }




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
                        activeSheet = .todo
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
        .alert(item: $activeAlert) { alert in
            switch alert {

            case .limit:
                return Alert(
                    title: Text(String(localized: "chat_limit_title")),
                    message: Text(String(localized: "chat_limit_message")),
                    primaryButton: .default(
                        Text(String(localized: "upgrade_to_premium")),
                        action: {
                            activeSheet = .premium
                        }
                    ),
                    secondaryButton: .cancel(
                        Text(String(localized: "wait_ok"))
                    )
                )

            case .locationNotReady:
                return Alert(
                    title: Text(String(localized: "location_not_ready_title")),
                    message: Text(String(localized: "location_not_ready_message")),
                    dismissButton: .cancel(
                        Text(String(localized: "ok"))
                    )
                )

            case .confirmSendLocation:
                return Alert(
                    title: Text(String(localized: "you_sure_sending_your_location")),
                    primaryButton: .destructive(
                        Text(String(localized: "send")),
                        action: {
                            sendMyGPS()
                        }
                    ),
                    secondaryButton: .cancel(
                        Text(String(localized: "cancel"))
                    )
                )
            }
        }
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .mapPicker:
                MapPickerView(location: locationManager.location) { coord in
                    vm.sendCurrentLocation(
                        lat: coord.latitude,
                        lon: coord.longitude,
                        isPremium: premium.isPremium
                    ) {
                        activeAlert = .limit
                    }
                }

            case .premium:
                PremiumUpgradeSheet()

            case .todo:
                TodoListView(
                    chatId: eventId,
                    myId: session.currentUserId ?? ""
                )
            }
        }
        
        .onAppear {
            // 1️⃣ Foreground tracker
            ChatForegroundTracker.shared.activeChatEventId = eventId

            // 2️⃣ Backend state
            if let uid = session.currentUserId {
                Firestore.firestore()
                    .collection("users")
                    .document(uid)
                    .setData(
                        ["activeChatEventId": eventId],
                        merge: true
                    )
            }

            // 3️⃣ Đảm bảo chat tồn tại → listen messages
            Task {
                await vm.ensureChatExists(
                    participants: [
                        session.currentUserId!,
                        otherUserId
                    ],
                    eventEndTime: eventEndTime
                )
                try? await Task.sleep(nanoseconds: 300_000_000)
                vm.listenMessages()

                // ⭐ MARK SEEN sau khi listener attach
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    vm.markSeen()
                }
            }

            // 4️⃣ Retry message gửi offline (⭐ DÒNG BẠN HỎI)
            vm.retryPendingMessagesIfNeeded()

            // 5️⃣ Listener phụ
            todoVM.listen()

            // 6️⃣ Auto delete
            vm.autoDeleteIfPast(eventEndTime)
        }


        .onDisappear {
            handleDisappear()
        }



        .onChange(of: vm.messages.count) { _, count in
            if count > 0 {
                vm.markSeen()
            }
        }
        .onChange(of: vm.reachedFreeLimit) { _, reached in
            guard reached else { return }

            // Không spam alert nếu đã là Premium
            if !premium.isPremium {
                activeAlert = .limit
            }
        }

        
    }
    func fetchAddress(
        lat: Double,
        lon: Double,
        id: String,
        completion: @escaping (String) -> Void
    )
 {

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

    private var actionMenuContent: some View {
        VStack(spacing: 12) {

            Button {
                showActionPopover = false
                activeAlert = .confirmSendLocation
            } label: {
                Label(String(localized: "send_current_location"),
                      systemImage: "location.fill")
            }

            Divider()

            Button {
                showActionPopover = false
                DispatchQueue.main.async {
                    activeSheet = .mapPicker
                }
            } label: {
                Label(String(localized: "pick_location_on_map"),
                      systemImage: "map.fill")
            }
        }
        .padding()
        .frame(minWidth: 220)
    }

    private func style(for isMe: Bool) -> ChatBubbleStyle {
        let preset = isMe
            ? ChatColorPreset(rawValue: myPresetRaw) ?? .blue
            : ChatColorPreset(rawValue: otherPresetRaw) ?? .graphite

        return ChatBubbleStyleFactory.make(
            backgroundHex: preset.hex,
            isMe: isMe,
            isPremium: premium.isPremium
        )
    }

    // MARK: - Bubble
    private func bubble(_ msg: ChatMessage) -> some View {
        let isMe = msg.senderId == session.currentUserId
        let style = style(for: isMe)

        return HStack {
            if isMe { Spacer(minLength: 40) }

            VStack(alignment: isMe ? .trailing : .leading, spacing: 4) {

                // 👤 Tên người gửi (chỉ hiện bên kia)
                if !isMe {
                    Text(eventManager.displayName(for: msg.senderId))
                        .font(.caption2)
                        .foregroundColor(style.secondaryText)
                }

                // 📍 MESSAGE: LOCATION
                if let lat = msg.latitude, let lon = msg.longitude {

                    VStack(alignment: isMe ? .trailing : .leading, spacing: 6) {

                        let key = msg.uiId

                        Text(addressCache[key] ?? String(localized: "fetching_address"))
                            .font(.subheadline)
                            .foregroundColor(style.text)
                            .onAppear {
                                if addressCache[key] == nil {
                                    fetchAddress(
                                        lat: lat,
                                        lon: lon,
                                        id: key
                                    ) { _ in }
                                }
                            }
                            .contextMenu {
                                if let address = addressCache[key] {
                                    Button {
                                        UIPasteboard.general.string = address
                                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                    } label: {
                                        Label(String(localized: "copy_address"),
                                              systemImage: "doc.on.doc")
                                    }
                                }
                            }



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
                            .foregroundColor(style.text)
                        }
                        .padding(8)
                        .background(style.innerButtonBackground)
                        .cornerRadius(10)
                    }
                    .padding(10)
                    .background(style.background)
                    .cornerRadius(12)
                }

                // 💬 MESSAGE: TEXT
                else {
                    Text(msg.text)
                        .foregroundColor(style.text)
                        .padding(10)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(style.background)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(style.border, lineWidth: 0.8)
                                )
                        )
                        .contextMenu {
                            Button {
                                UIPasteboard.general.string = msg.text
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            } label: {
                                Label(String(localized: "copy"), systemImage: "doc.on.doc")
                            }
                        }


                }

                // 👁 Seen / Delivered
                if isMe {
                    let seen = msg.seenBy?[otherUserId] == true
                    Text(seen
                         ? String(localized: "seen")
                         : String(localized: "delivered")
                    )
                    .font(.caption2)
                    .foregroundColor(style.secondaryText)
                }
            }

            if !isMe { Spacer(minLength: 40) }
        }
    }

    
    func sendMyGPS() {
        guard !vm.reachedFreeLimit || premium.isPremium else {
            activeAlert = .limit
            return
        }

        guard let loc = locationManager.location else {
            activeAlert = .locationNotReady
            return
        }

        vm.sendCurrentLocation(
            lat: loc.coordinate.latitude,
            lon: loc.coordinate.longitude,
            isPremium: premium.isPremium
        ) {
            activeAlert = .limit
        }
    }

    private func handleDisappear() {
        vm.stopListening()
        todoVM.stop()

        if ChatForegroundTracker.shared.activeChatEventId == eventId {
            ChatForegroundTracker.shared.activeChatEventId = nil
        }

        if let uid = session.currentUserId {
            Firestore.firestore()
                .collection("users")
                .document(uid)
                .setData(
                    ["activeChatEventId": FieldValue.delete()],
                    merge: true
                )
        }
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
enum ChatAlert: Identifiable {
    case limit
    case locationNotReady
    case confirmSendLocation

    var id: String {
        switch self {
        case .limit: return "limit"
        case .locationNotReady: return "locationNotReady"
        case .confirmSendLocation: return "confirmSendLocation"
        }
    }
}

enum ChatSheet: Identifiable {
    case mapPicker
    case premium
    case todo

    var id: Int { hashValue }
}
