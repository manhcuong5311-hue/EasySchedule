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

    @EnvironmentObject var network: NetworkMonitor

    @EnvironmentObject var eventManager: EventManager
    @AppStorage("chat_my_preset") private var myPresetRaw: String = ChatColorPreset.blue.rawValue
    @AppStorage("chat_other_preset") private var otherPresetRaw: String = ChatColorPreset.graphite.rawValue


    private let geocoder = CLGeocoder()

    
    private var canManageMembers: Bool {

        guard let myUid = session.currentUserId else { return false }

        return eventInfo.owner == myUid ||
               eventInfo.admins?.contains(myUid) == true
    }

    
    
    
    
    
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
                participants: eventInfo.participants,
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
            // ⭐ OFFLINE BANNER
            if !network.isOnline {
                OfflineBannerView()
                    .padding(.horizontal)
                    .padding(.top, 4)
                    .padding(.bottom, 6)
            }
            Divider()

            if vm.messages.isEmpty {
                chatEmptyState
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(Array(vm.messages.enumerated()), id: \.element.uiId) { index, msg in
                                let prev = index > 0 ? vm.messages[index - 1] : nil
                                let next = index < vm.messages.count - 1 ? vm.messages[index + 1] : nil

                                if Self.needsDateSeparator(prev: prev, current: msg) {
                                    ChatDateSeparator(date: msg.timestamp)
                                }

                                bubble(msg, prev: prev, next: next)
                                    .id(msg.uiId)
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                    }
                    .onChange(of: vm.messages.count) { _, _ in
                        if let last = vm.messages.last {
                            withAnimation(.easeOut(duration: 0.25)) {
                                proxy.scrollTo(last.uiId, anchor: .bottom)
                            }
                        }
                    }
                    .onAppear {
                        if let last = vm.messages.last {
                            proxy.scrollTo(last.uiId, anchor: .bottom)
                        }
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
                    locationManager.start()
                    activeSheet = .attachment
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(locked ? .gray : .blue)
                        .frame(width: 36, height: 36)
                        .background((locked ? Color.gray : Color.blue).opacity(0.12))
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
                            activeAlert = .limit
                        }




                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            sendCooldown = false
                        }
                    } label: {
                        Image(systemName: "paperplane.fill")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(
                                locked || trimmedMessageEmpty ? .gray : .white
                            )
                            .frame(width: 36, height: 36)
                            .background(
                                locked || trimmedMessageEmpty
                                ? Color.gray.opacity(0.3)
                                : Color.blue
                            )
                            .clipShape(Circle())
                    }
                    .disabled(locked || trimmedMessageEmpty)

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
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                chatHeaderPrincipal
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                HStack(spacing: 8) {
                    
                    if canManageMembers {
                                   Button {
                                       activeSheet = .addMember
                                   } label: {
                                       Image(systemName: "person.badge.plus")
                                   }
                               }
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

            case .locationDenied:
                return Alert(
                    title: Text(String(localized: "location_denied_title")),
                    message: Text(String(localized: "location_denied_message")),
                    primaryButton: .default(
                        Text(String(localized: "open_settings")),
                        action: {
                            if let url = URL(string: UIApplication.openSettingsURLString) {
                                UIApplication.shared.open(url)
                            }
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
                MapPickerView(locationManager: locationManager) { coord in
                    vm.sendCurrentLocation(
                        lat: coord.latitude,
                        lon: coord.longitude,
                        isPremium: premium.isPremium
                    ) {
                        activeAlert = .limit
                    }
                }

            case .attachment:
                LocationAttachmentSheet(
                    onSendCurrent: {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                            handleSendCurrentLocation()
                        }
                    },
                    onPickMap: {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                            activeSheet = .mapPicker
                        }
                    }
                )
                .presentationDetents([.height(220)])
                .presentationDragIndicator(.visible)

            case .addMember:
                AddMemberSheet(
                    event: eventInfo
                )
                .environmentObject(eventManager)

            case .premium:
                PremiumUpgradeSheet(
                    preselectProductID: "com.SamCorp.EasySchedule.premium.yearly",
                    autoPurchase: false
                )
                .environmentObject(premium)
                
            case .todo:
                TodoListView(vm: todoVM)
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

            // 3️⃣ Ensure chat document exists (listener already started in init)
            Task {
                do {
                    try await vm.ensureChatExists(eventEndTime: eventEndTime)
                    eventManager.markEventSeen(eventId)
                } catch {
                    print("❌ ensureChatExists failed:", error)
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
    private var chatHeaderPrincipal: some View {
        let isGroup = eventInfo.participants.count > 2
        let title = isGroup ? eventInfo.title : otherName
        return HStack(spacing: 8) {
            ChatAvatarView(name: title, isGroup: isGroup, size: 30)
            VStack(alignment: .leading, spacing: 0) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .lineLimit(1)
                Text(headerSubtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }

    private var headerSubtitle: String {
        let isGroup = eventInfo.participants.count > 2
        if isGroup {
            let start = eventInfo.startTime.formatted(date: .omitted, time: .shortened)
            let end   = eventInfo.endTime.formatted(date: .omitted, time: .shortened)
            return "\(start) – \(end)"
        }
        return eventInfo.title
    }

    private var chatEmptyState: some View {
        let isGroup = eventInfo.participants.count > 2
        return VStack(spacing: 12) {
            Spacer()
            ChatAvatarView(name: isGroup ? eventInfo.title : otherName,
                           isGroup: isGroup, size: 64)
            Text(String(localized: "chat_empty_title"))
                .font(.headline)
            Text(String(localized: "chat_empty_subtitle"))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 40)
    }

    private var locked: Bool {
        !premium.isPremium && vm.reachedFreeLimit
    }

    private var trimmedMessageEmpty: Bool {
        vm.messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func handleSendCurrentLocation() {
        locationManager.requestOnce { loc in
            if loc != nil {
                activeAlert = .confirmSendLocation
            } else if locationManager.isDenied {
                activeAlert = .locationDenied
            } else {
                activeAlert = .locationNotReady
            }
        }
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

    static func needsDateSeparator(prev: ChatMessage?, current: ChatMessage) -> Bool {
        guard let prev else { return true }
        return !Calendar.current.isDate(prev.timestamp, inSameDayAs: current.timestamp)
    }

    // MARK: - Bubble (grouped by sender)
    private func bubble(_ msg: ChatMessage, prev: ChatMessage?, next: ChatMessage?) -> some View {
        let isMe    = msg.senderId == session.currentUserId
        let style   = style(for: isMe)
        let isGroup = eventInfo.participants.count > 2
        let cal     = Calendar.current

        let isFirstInGroup = prev == nil
            || prev!.senderId != msg.senderId
            || !cal.isDate(prev!.timestamp, inSameDayAs: msg.timestamp)
            || msg.timestamp.timeIntervalSince(prev!.timestamp) > 300
        let isLastInGroup = next == nil
            || next!.senderId != msg.senderId
            || !cal.isDate(next!.timestamp, inSameDayAs: msg.timestamp)
            || next!.timestamp.timeIntervalSince(msg.timestamp) > 300

        let senderName =
            msg.senderName
            ?? eventManager.userNames[msg.senderId]
            ?? eventManager.displayName(for: msg.senderId)

        return HStack(alignment: .bottom, spacing: 6) {
            if isMe { Spacer(minLength: 48) }

            if !isMe && isGroup {
                if isLastInGroup {
                    ChatAvatarView(name: senderName, size: 26)
                } else {
                    Color.clear.frame(width: 26, height: 1)
                }
            }

            VStack(alignment: isMe ? .trailing : .leading, spacing: 2) {
                if !isMe && isGroup && isFirstInGroup {
                    Text(senderName)
                        .font(.caption2.weight(.semibold))
                        .foregroundColor(.secondary)
                        .padding(.leading, 10)
                }

                bubbleContent(msg, isMe: isMe, style: style)

                if isLastInGroup {
                    bubbleFooter(msg, isMe: isMe)
                }
            }

            if !isMe { Spacer(minLength: 48) }
        }
        .padding(.top, isFirstInGroup ? 8 : 1)
    }

    @ViewBuilder
    private func bubbleContent(_ msg: ChatMessage, isMe: Bool, style: ChatBubbleStyle) -> some View {
        if let lat = msg.latitude, let lon = msg.longitude {
            locationBubble(msg, lat: lat, lon: lon, isMe: isMe, style: style)
        } else {
            Text(msg.text)
                .foregroundColor(style.text)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(style.background)
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(style.border, lineWidth: 0.8)
                        )
                )
                .textSelection(.enabled)
        }
    }

    private func locationBubble(_ msg: ChatMessage, lat: Double, lon: Double, isMe: Bool, style: ChatBubbleStyle) -> some View {
        let key = msg.uiId
        return VStack(alignment: isMe ? .trailing : .leading, spacing: 6) {
            Text(addressCache[key] ?? String(localized: "fetching_address"))
                .font(.subheadline)
                .foregroundColor(style.text)
                .onAppear {
                    if addressCache[key] == nil {
                        fetchAddress(lat: lat, lon: lon, id: key) { _ in }
                    }
                }
                .contextMenu {
                    if let address = addressCache[key] {
                        Button {
                            UIPasteboard.general.string = address
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        } label: {
                            Label(String(localized: "copy_address"), systemImage: "doc.on.doc")
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
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous).fill(style.background)
        )
    }

    @ViewBuilder
    private func bubbleFooter(_ msg: ChatMessage, isMe: Bool) -> some View {
        let time = msg.timestamp.formatted(date: .omitted, time: .shortened)
        HStack(spacing: 4) {
            if isMe {
                switch msg.sendStatus {
                case .sending:
                    Image(systemName: "clock")
                    Text(String(localized: "message_sending"))
                case .failed:
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        vm.retryPendingMessagesIfNeeded()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "exclamationmark.circle.fill")
                            Text(String(localized: "message_failed"))
                        }
                        .foregroundColor(.red)
                    }
                    .buttonStyle(.plain)
                case .sent:
                    Text(time)
                    let seen = eventInfo.participants
                        .filter { $0 != myId }
                        .allSatisfy { msg.seenBy?[$0] == true }
                    Text("·")
                    Text(seen ? String(localized: "seen") : String(localized: "delivered"))
                }
            } else {
                Text(time)
            }
        }
        .font(.caption2)
        .foregroundColor(.secondary)
        .padding(.horizontal, 4)
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
    case locationDenied

    var id: String {
        switch self {
        case .limit: return "limit"
        case .locationNotReady: return "locationNotReady"
        case .confirmSendLocation: return "confirmSendLocation"
        case .locationDenied: return "locationDenied"
        }
    }
}

enum ChatSheet: Identifiable {
    case mapPicker
    case premium
    case todo
    // ⭐ ADD
    case addMember
    case attachment

    var id: Int { hashValue }
}


// MARK: - Shared chat UI components

struct ChatAvatarView: View {
    let name: String
    var isGroup: Bool = false
    var size: CGFloat = 34

    var body: some View {
        ZStack {
            Circle().fill(Self.color(for: name).gradient)
            if isGroup {
                Image(systemName: "person.2.fill")
                    .font(.system(size: size * 0.42, weight: .semibold))
                    .foregroundStyle(.white)
            } else {
                Text(Self.initials(name))
                    .font(.system(size: size * 0.40, weight: .bold))
                    .foregroundStyle(.white)
            }
        }
        .frame(width: size, height: size)
    }

    static func initials(_ name: String) -> String {
        let parts = name.split(separator: " ").prefix(2)
        let chars = parts.compactMap { $0.first }
        let s = String(chars).uppercased()
        return s.isEmpty ? "?" : s
    }

    static func color(for name: String) -> Color {
        let palette: [Color] = [.blue, .purple, .pink, .orange, .teal, .indigo, .green, Color(hex: "#E0457B")]
        let h = name.unicodeScalars.reduce(0) { $0 &+ Int($1.value) }
        return palette[h % palette.count]
    }
}

struct ChatDateSeparator: View {
    let date: Date

    var body: some View {
        Text(Self.label(for: date))
            .font(.caption2.weight(.medium))
            .foregroundColor(.secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .background(Capsule().fill(Color(.systemGray5).opacity(0.7)))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
    }

    static func label(for date: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(date) { return String(localized: "today") }
        if cal.isDateInYesterday(date) { return String(localized: "yesterday") }
        return date.formatted(.dateTime.weekday(.abbreviated).day().month())
    }
}

// MARK: - Location attachment sheet (Messenger-style)

struct LocationAttachmentSheet: View {
    @Environment(\.dismiss) private var dismiss
    let onSendCurrent: () -> Void
    let onPickMap: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Text(String(localized: "location_sheet_title"))
                .font(.headline)
                .padding(.top, 22)

            HStack(spacing: 14) {
                tile(title: String(localized: "send_current_location"),
                     systemImage: "location.fill",
                     colors: [Color.blue, Color.cyan]) {
                    dismiss(); onSendCurrent()
                }
                tile(title: String(localized: "pick_location_on_map"),
                     systemImage: "map.fill",
                     colors: [Color.green, Color.teal]) {
                    dismiss(); onPickMap()
                }
            }
            .padding(.horizontal, 20)

            Spacer(minLength: 0)
        }
    }

    private func tile(
        title: String,
        systemImage: String,
        colors: [Color],
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(
                            LinearGradient(colors: colors,
                                           startPoint: .topLeading,
                                           endPoint: .bottomTrailing)
                        )
                        .frame(height: 72)
                    Image(systemName: systemImage)
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundStyle(.white)
                }
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .frame(height: 32, alignment: .top)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }
}
