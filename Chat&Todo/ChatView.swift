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
    @State private var showLocationNotReadyAlert = false
   

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
                        if locked {
                            showLimitAlert = true
                            return
                        }
                        showLocationConfirm = true
                    } label: {
                        Label(String(localized: "send_current_location"), systemImage: "location.fill")
                    }

                    Button {
                        if locked {
                            showLimitAlert = true
                            return
                        }
                        showMapPicker = true
                    } label: {
                        Label(String(localized: "pick_location_on_map"), systemImage: "map.fill")
                    }
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(locked ? .gray : .blue)
                        .frame(width: 36, height: 36)
                        .background(
                            (locked ? Color.gray : Color.blue).opacity(0.12)
                        )
                        .clipShape(Circle())
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
                            showLimitAlert = true
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
        .sheet(isPresented: $showMapPicker) {
            MapPickerView(location: locationManager.location) { coord in
                vm.sendCurrentLocation(
                    lat: coord.latitude,
                    lon: coord.longitude,
                    isPremium: premium.isPremium
                ) {
                    showLimitAlert = true
                }
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
        .alert(
            String(localized: "location_not_ready_title"),
            isPresented: $showLocationNotReadyAlert
        ) {
            Button(String(localized: "ok"), role: .cancel) {}
        } message: {
            Text(String(localized: "location_not_ready_message"))
        }

        .alert(String(localized:"you_sure_sending_your_location"),
               isPresented: $showLocationConfirm) {
            Button(String(localized:"cancel"), role: .cancel) {}
            Button(String(localized:"send"), role: .destructive) {
                sendMyGPS()
            }
        }


        .sheet(isPresented: $showPremiumSheet) {
            PremiumUpgradeSheet()
        }


        .sheet(isPresented: $showTodoList) {
            TodoListView(chatId: eventId, myId: session.currentUserId ?? "")
        }
        .onAppear {
            // ⭐ Local state (giữ nguyên)
            ChatForegroundTracker.shared.activeChatEventId = eventId

            // ⭐ Backend state (THÊM)
            if let uid = session.currentUserId {
                Firestore.firestore()
                    .collection("users")
                    .document(uid)
                    .setData([
                        "activeChatEventId": eventId
                    ], merge: true)
            }

            // ===== code cũ của bạn =====
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
            // ⭐ Local state (giữ nguyên)
            if ChatForegroundTracker.shared.activeChatEventId == eventId {
                ChatForegroundTracker.shared.activeChatEventId = nil
            }

            // ⭐ Backend state (THÊM)
            if let uid = session.currentUserId {
                Firestore.firestore()
                    .collection("users")
                    .document(uid)
                    .setData([
                        "activeChatEventId": FieldValue.delete()
                    ], merge: true)
            }

            todoVM.stop()
        }
        .onChange(of: vm.reachedFreeLimit) { _, reached in
            guard reached else { return }

            // Không spam alert nếu đã là Premium
            if !premium.isPremium {
                showLimitAlert = true
            }
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
        guard !vm.reachedFreeLimit || premium.isPremium else {
            showLimitAlert = true
            return
        }

        guard let loc = locationManager.location else {
            showLocationNotReadyAlert = true
            return
        }

        vm.sendCurrentLocation(
            lat: loc.coordinate.latitude,
            lon: loc.coordinate.longitude,
            isPremium: premium.isPremium
        ) {
            showLimitAlert = true
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
