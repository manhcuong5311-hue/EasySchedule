//
//  EventManager.swift
//  Easy Schedule
//
//  Created by Sam Manh Cuong on 2/1/26.
//
import SwiftUI
import Combine
import FirebaseCore
import FirebaseMessaging
import UserNotifications
import FirebaseAuth
import FirebaseFirestore

// MARK: - Mô hình dữ liệu
enum EventOrigin: String, Codable {
    case myEvent
    case createdForMe
    case iCreatedForOther
    case busySlot
}
struct CalendarEvent: Identifiable, Hashable, Codable {

    // MARK: - Core fields
    var id: String = UUID().uuidString
    var title: String
    var date: Date
    var startTime: Date
    var endTime: Date

    // MARK: - Ownership fields
    var owner: String          // Chủ lịch (A)
    var sharedUser: String     // Người được tạo lịch cho (B)
    var createdBy: String      // Người tạo thực sự (A hoặc B)

    // MARK: - Participants
    var participants: [String] = []

    // MARK: - Name resolution fields (⭐ NEW)
    var participantNames: [String: String]? = nil   // <— thêm
    var creatorName: String? = nil                 // <— thêm

    // MARK: - UI fields
    var colorHex: String = "#007AFF"
    var pendingDelete: Bool = false
    var origin: EventOrigin = .myEvent
}



final class EventManager: ObservableObject {
    static let shared = EventManager()
    private var partnerTierCache: [String: PremiumTier] = [:]

    // Firestore listeners
    @Published var busySlotCache: [String: [CalendarEvent]] = [:]
    @Published var busySlotPremiumCache: [String: Bool] = [:]
    // Cache busy slots của đối tác
    private var partnerBusySlotCache: [String: [CalendarEvent]] = [:]
    @Published var offDayCache: [String: Set<Date>] = [:]

    // Cache premium flag của đối tác
    private var partnerPremiumCache: [String: Bool] = [:]
    // Cache busy slots theo UID đối tác
    @Published var partnerBusySlots: [String: [CalendarEvent]] = [:]
    private var isCreatingEvent = false

    private var eventsListener: ListenerRegistration?
    private var appointmentsListener: ListenerRegistration?
    private var createdAppointmentsListener: ListenerRegistration?
    private var busySlotListeners: [String: ListenerRegistration] = [:]

    // --- Persisted user name cache key
    private let kUserNamesKey = "es_userNames_cache_v1"
    private var lastEventCreateTime: Date?
    @Published var selectedChatEventId: String?
    @Published var selectedEventId: String?

    // persisted + in-memory cache
    @Published var userNames: [String: String] = [:] {
        didSet {
            if let data = try? JSONEncoder().encode(userNames) {
                UserDefaults.standard.set(data, forKey: kUserNamesKey)
            }
        }
    }
    @Published var chatMetaCache: [String: ChatMetaViewModel] = [:]

    // ⭐ PREMIUM FLAG
    private var isPremiumUser: Bool {
        PremiumStoreViewModel.shared.isPremium
    }


    var allowDuplicateEvents: Bool {
        get { UserDefaults.standard.bool(forKey: "allowDuplicateEvents") }
        set { UserDefaults.standard.set(newValue, forKey: "allowDuplicateEvents") }
    }
    private var isProcessing = false
    @State private var shareLink: String?
    @State private var showShareSheet = false
    @Published var isAdding = false
    @Published var alertMessage: String = ""
    @Published var showAlert = false
    @Published var sharedLinks: [SharedLink] = [] {
        didSet { saveSharedLinks() }
    }

    @Published var events: [CalendarEvent] = [] {
        didSet {
           
            updateGroupedEvents()
        }
    }

    @Published var pastEvents: [CalendarEvent] = []
    @Published var groupedByDay: [Date: [CalendarEvent]] = [:]
    @Published var userNameCache: [String: String] = [:]

    private let db = Firestore.firestore()

    // MARK: - INIT
    private init() {
        loadEvents()
        loadPastEvents()
        cleanUpPastEvents()
        loadSharedLinks()
        loadPersistedUserNames()
        updateGroupedEvents()
        listenToEvents()
        retryPendingDeletes()
      
    }

    // MARK: - LOCAL SAVE
    private func saveEvents() {
        if isProcessing { return }   // ⭐ NGĂN GHI ĐÈ SAI
        if let data = try? JSONEncoder().encode(events) {
            UserDefaults.standard.set(data, forKey: "upcomingEvents")
        }
        if let data = try? JSONEncoder().encode(pastEvents) {
            UserDefaults.standard.set(data, forKey: "pastEvents")
        }
    }

    private func loadEvents() {
        if let data = UserDefaults.standard.data(forKey: "upcomingEvents"),
           let decoded = try? JSONDecoder().decode([CalendarEvent].self, from: data) {
            self.events = decoded
        }
        if let data = UserDefaults.standard.data(forKey: "pastEvents"),
           let decoded = try? JSONDecoder().decode([CalendarEvent].self, from: data) {
            self.pastEvents = decoded
        }
        updateGroupedEvents()
    }

    func saveSharedLinks() {
        if let data = try? JSONEncoder().encode(sharedLinks) {
            UserDefaults.standard.set(data, forKey: "shared_links")
        }
    }

    private func loadSharedLinks() {
        if let data = UserDefaults.standard.data(forKey: "shared_links"),
           let decoded = try? JSONDecoder().decode([SharedLink].self, from: data) {
            self.sharedLinks = decoded
        }
    }

    func togglePin(_ link: SharedLink) {
        if let idx = sharedLinks.firstIndex(where: { $0.id == link.id }) {
            sharedLinks[idx].isPinned.toggle()
        }
    }
    func reset() {
        // Remove event listeners
        eventsListener?.remove()
        appointmentsListener?.remove()
        createdAppointmentsListener?.remove()

        eventsListener = nil
        appointmentsListener = nil
        createdAppointmentsListener = nil

        // ⭐ Remove ALL busySlot listeners
        for (_, listener) in busySlotListeners {
            listener.remove()
        }
        busySlotListeners.removeAll()

        // Clear local data
        DispatchQueue.main.async {
            self.events.removeAll()
            self.pastEvents.removeAll()
            self.groupedByDay.removeAll()
            self.sharedLinks.removeAll()
            self.saveEvents()
            self.saveSharedLinks()
        }

        print("🧹 EventManager RESET hoàn tất (đã remove ALL busySlot listeners).")
    }


    func reloadForCurrentUser() {
        clearLocalEvents()
        guard let uid = currentUserId else { return }
        print("🔄 Reloading events for user:", uid)
        listenToEvents()
       
        listenToBusySlots(sharedUserId: uid)
        cleanUpPastEvents()
        
    }
    
    func chatMeta(for eventId: String) -> ChatMetaViewModel {
        if let existing = chatMetaCache[eventId] {
            return existing
        }
        let vm = ChatMetaViewModel(eventId: eventId)
        chatMetaCache[eventId] = vm
        return vm
    }

    func name(for uid: String, completion: @escaping (String) -> Void) {
        if let cached = userNames[uid] {
            completion(cached)
            return
        }
        Firestore.firestore()
            .collection("users")
            .document(uid)
            .getDocument { snap, err in
                let name = snap?.data()?["name"] as? String ?? uid
                DispatchQueue.main.async {
                    self.userNames[uid] = name
                    completion(name)
                }
            }
     }

    func preloadUsersIfNeeded() {
        // Nếu cache đã có dữ liệu → KHÔNG gọi Firestore
        if !userNames.isEmpty { return }

        Firestore.firestore().collection("users").getDocuments { snap, _ in
            guard let docs = snap?.documents else { return }

            var temp: [String: String] = [:]

            for doc in docs {
                temp[doc.documentID] = doc["name"] as? String ?? doc.documentID
            }

            DispatchQueue.main.async {
                self.userNames = temp
            }
        }
    }

    private func loadPersistedUserNames() {
        guard let data = UserDefaults.standard.data(forKey: kUserNamesKey) else { return }
        if let decoded = try? JSONDecoder().decode([String: String].self, from: data) {
            DispatchQueue.main.async {
                self.userNames = decoded
            }
        }
    }

    
    private func addHistoryLink(uid: String, url: String) {
        if sharedLinks.contains(where: { $0.url == url }) { return }

        let link = SharedLink(
            id: UUID().uuidString,
            uid: uid,
            url: url,
            createdAt: Date()
        )
        sharedLinks.append(link)
    }

    // MARK: - PENDING DELETE
    private func retryPendingDeletes() {
        let pendings = events.filter { $0.pendingDelete }
        for ev in pendings { deleteRemoteOnly(ev) }
    }

    private func deleteRemoteOnly(_ ev: CalendarEvent) {
        guard !ev.id.isEmpty else { return }

        db.collection("events").document(ev.id).delete { error in
            if let error = error {
                print("⚠ Pending delete FAILED:", error.localizedDescription)
                return
            }

            self.removeBusySlotFromPublicCalendar(event: ev)

            DispatchQueue.main.async {
                self.events.removeAll { $0.id == ev.id }
                self.saveEvents()
                self.updateGroupedEvents()
            }
            print("✅ Pending delete SUCCESS:", ev.id)
        }
    }

    func cleanUpPastEvents() {
        let now = Date()

        // Tách event hết hạn (chỉ trên local)
        let expired = events.filter { $0.endTime < now }
        let upcoming = events.filter { $0.endTime >= now }

        // Gán ngược
        if !expired.isEmpty {
            // Add vào pastEvents local
            self.pastEvents.append(contentsOf: expired)
        }

        // Giữ upcoming
        self.events = upcoming

        // Lưu local
        saveEvents()
    }
    func savePastEvents() {
        if let encoded = try? JSONEncoder().encode(pastEvents) {
            UserDefaults.standard.set(encoded, forKey: "pastEvents")
        }
    }
    func loadPastEvents() {
        if let data = UserDefaults.standard.data(forKey: "pastEvents"),
           let decoded = try? JSONDecoder().decode([CalendarEvent].self, from: data) {
            self.pastEvents = decoded
        }
    }

    


    // MARK: - OFF DAYS
    func fetchOffDays(for userId: String,
                      forceRefresh: Bool = false,
                      completion: @escaping (Set<Date>) -> Void) {

        // 1️⃣ Nếu có cache và không ép refresh → trả về ngay
        if !forceRefresh, let cached = offDayCache[userId] {
            completion(cached)
            return
        }

        // 2️⃣ Gọi Firestore nếu chưa có cache hoặc forceRefresh = true
        db.collection("publicCalendar")
            .document(userId)
            .getDocument { snap, error in

                guard let data = snap?.data() else {
                    completion([])
                    return
                }

                let timestamps = data["offDays"] as? [Double] ?? []
                let dates = Set(timestamps.map { Date(timeIntervalSince1970: $0) })

                // 3️⃣ Lưu cache để lần sau không gọi Firestore nữa
                DispatchQueue.main.async {
                    self.offDayCache[userId] = dates
                }

                completion(dates)
            }
    }
    func syncBusySlotsForCurrentUser(event: CalendarEvent) {
        guard let uid = currentUserId else { return }
        addBusySlot(for: uid, event: event)
    }


    // MARK: - GROUPING
    func updateGroupedEvents() {
        groupedByDay = Dictionary(grouping: events) {
            Calendar.current.startOfDay(for: $0.date)
        }
    }

    func events(for date: Date) -> [CalendarEvent] {
        let d = Calendar.current.startOfDay(for: date)
        return groupedByDay[d]?.sorted { $0.startTime < $1.startTime } ?? []
    }
    
    func addBusySlot(for uid: String, event: CalendarEvent) {
        let docRef = db.collection("publicCalendar").document(uid)

        docRef.getDocument { snap, err in
            var slots = snap?.data()?["busySlots"] as? [[String: Any]] ?? []

            // Remove old slot nếu trùng ID
            slots.removeAll {
                ($0["id"] as? String) == event.id &&
                ($0["source"] as? String) == "event"
            }


            let start = event.startTime.timeIntervalSince1970
            let end = event.endTime.timeIntervalSince1970

            // ⭐ timestamp ALWAYS in seconds
            let newSlot: [String: Any] = [
                "id": event.id,
                "source": "event",          // ⭐ BẮT BUỘC
                "title": event.title,
                "owner": uid,
                "start": Double(start),
                "end": Double(end)
            ]


            slots.append(newSlot)

            docRef.setData(["busySlots": slots], merge: true)
        }
    }

    func syncBusySlots(for event: CalendarEvent) {
        // thêm owner (chính mình)
        addBusySlot(for: event.owner, event: event)

        // thêm partner
        for uid in event.participants {
            addBusySlot(for: uid, event: event)
        }
    }



    func removeBusySlotForAllParticipants(event: CalendarEvent) {
        for uid in event.participants {
            let doc = db.collection("publicCalendar").document(uid)
            doc.getDocument { snap, _ in
                var slots = snap?.data()?["busySlots"] as? [[String: Any]] ?? []
                slots.removeAll { ($0["id"] as? String) == event.id }
                doc.setData(["busySlots": slots], merge: true)
            }
        }
    }

    func cleanupBusySlots(for uid: String) {
        let nowSec = Date().timeIntervalSince1970

        let doc = Firestore.firestore().collection("publicCalendar").document(uid)
        doc.getDocument { snap, _ in
            guard let busySlots = snap?.data()?["busySlots"] as? [[String: Any]] else { return }

            var cleaned: [[String: Any]] = []

            for var slot in busySlots {
                var end = slot["end"] as? Double ?? 0

                // Convert mili → giây
                if end > 10_000_000_000 { end /= 1000 }

                if end > nowSec {
                    slot["end"] = end
                    cleaned.append(slot)
                }
            }

            doc.updateData(["busySlots": cleaned])
        }
    }
    func createRequest(owner: String, requester: String, requesterName: String? = nil) {
        db.collection("calendarAccess")
            .document(owner)
            .collection("requests")
            .document(requester)
            .setData([
                "uid": requester,
                "name": requesterName ?? "",
                "requestedAt": FieldValue.serverTimestamp()
            ]) { error in
                if let error = error {
                    print("❌ Failed to create request:", error.localizedDescription)
                } else {
                    print("📩 Request created for owner: \(owner)")
                }
            }
    }

    /// Kiểm tra event mới có overlap với danh sách events không.
    /// Trả về TRUE nếu bị trùng (không được tạo).
    func isOverlapExceedingLimit(
        newStart: Date,
        newEnd: Date,
        limitMinutes: Int,
        events: [CalendarEvent]
    ) -> Bool {
        
        let limit: TimeInterval = TimeInterval(limitMinutes * 60)

        for ev in events {
            let start = ev.startTime
            let end = ev.endTime

            // 1️⃣ CHO PHÉP CHẠM CẠNH
            if newEnd == start || newStart == end {
                continue
            }

            // 2️⃣ Nếu có overlap:
            if newStart < end && newEnd > start {
                
                // Tính overlap chính xác
                let overlapStart = max(newStart, start)
                let overlapEnd   = min(newEnd, end)
                let overlap = overlapEnd.timeIntervalSince(overlapStart)

                // Nếu overlap vượt quá giới hạn cho phép → TRẢ VỀ TRÙNG
                if overlap > limit {
                    return true
                }
            }
        }

        return false
    }

    func sendNewEventNotification(to uid: String, title: String, body: String) {
        guard let url = URL(string: "https://us-central1-easyschedule-ce98a.cloudfunctions.net/sendToUser") else { return }

        let payload: [String: Any] = [
            "uid": uid,
            "title": title,
            "body": body
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: payload)

        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                print("❌ send notification error:", error.localizedDescription)
            } else {
                print("📨 notification sent!")
            }
        }.resume()
    }

    func validateUserExists(uid: String, completion: @escaping (Bool) -> Void) {
        Firestore.firestore()
            .collection("users")
            .document(uid)
            .getDocument { snap, _ in
                completion(snap?.exists == true)
            }
    }
    func addBusyHoursForDay(
        userId: String,
        slots: [ProSlot],
        completion: (() -> Void)? = nil
    ) {
        let doc = db.collection("publicCalendar").document(userId)

        doc.getDocument { snap, _ in
            var existing = snap?.data()?["busySlots"] as? [[String: Any]] ?? []

            let newSlots: [[String: Any]] = slots.map { slot in
                [
                    "id": UUID().uuidString,      // ⭐ riêng cho manual
                    "source": "manual",           // ⭐ phân biệt
                    "title": String(localized: "busy"),
                    "start": slot.start.timeIntervalSince1970,
                    "end": slot.end.timeIntervalSince1970
                ]
            }

            existing.append(contentsOf: newSlots)

            doc.setData(["busySlots": existing], merge: true) { _ in
                completion?()
            }
        }
    }
    func removeManualBusySlots(
        userId: String,
        slots: [ProSlot],
        completion: (() -> Void)? = nil
    ) {
        let doc = db.collection("publicCalendar").document(userId)

        doc.getDocument { snap, _ in
            var existing = snap?.data()?["busySlots"] as? [[String: Any]] ?? []

            existing.removeAll { dict in
                guard
                    dict["source"] as? String == "manual",
                    let start = dict["start"] as? Double,
                    let end   = dict["end"]   as? Double
                else { return false }

                return slots.contains {
                    $0.start.timeIntervalSince1970 == start &&
                    $0.end.timeIntervalSince1970 == end
                }
            }

            doc.setData(["busySlots": existing], merge: true) { _ in
                completion?()
            }
        }
    }



}

// MARK: CRUD + Firestore
extension EventManager {
    @discardableResult
    func addEvent(title: String,
                  ownerName: String,
                  date: Date,
                  startTime: Date,
                  endTime: Date,
                  colorHex: String = "#007AFF") -> Bool {

        guard let uid = currentUserId else { return false }
       
        let now = Date()

        // ANTI-SPAM CLICK (2 giây trong app)
        if let last = lastEventCreateTime, now.timeIntervalSince(last) < 5 {
            print("🚫 BLOCK: Too fast!")
            return false
        }
        lastEventCreateTime = now

        // KHÔNG ĐƯỢC TẠO LỊCH TRONG QUÁ KHỨ
        if endTime < now {
            self.alertMessage = String(localized: "cant_create_events_in_the_past")
            self.showAlert = true
            return false
        }

        // CHECK TRÙNG LỊCH FULL
        let exactDuplicate = events.contains { ev in
            Calendar.current.isDate(ev.date, inSameDayAs: date) &&
            ev.startTime == startTime &&
            ev.endTime == endTime
        }

        if exactDuplicate {
            self.alertMessage = String(localized: "event_already_exists")
            self.showAlert = true
            return false
        }

        // CHECK OVERLAP
        // ⭐ CHECK OVERLAP ALLOW ≤ 5 PHÚT
        if !allowDuplicateEvents {
            let sameDayEvents = events.filter {
                Calendar.current.isDate($0.date, inSameDayAs: date)
            }

            let isConflict = isOverlapExceedingLimit(
                newStart: startTime,
                newEnd: endTime,
                limitMinutes: 5,                  // ⭐ CHO PHÉP OVERLAP ≤ 5 PHÚT
                events: sameDayEvents
            )

            if isConflict {
                self.alertMessage = String(localized: "time_slot_taken!")
                self.showAlert = true
                return false
            }
        }

        // PREMIUM / PRO LIMIT CHECK (Tier-based)
        let premium = PremiumStoreViewModel.shared
        let limits = premium.limits

        let eventsSameDay = events.filter {
            Calendar.current.isDate($0.date, inSameDayAs: date)
        }

        guard eventsSameDay.count < limits.maxEventsPerDay else {
            self.alertMessage = String(localized: "event_limit_reached")
            self.showAlert = true
            return false
        }


        // TẠO OBJECT
        let newEvent = CalendarEvent(
            id: UUID().uuidString,
            title: title,
            date: date,
            startTime: startTime,
            endTime: endTime,
            owner: uid,
            sharedUser: uid,
            createdBy: uid,
            participants: [uid],
            colorHex: colorHex,
            pendingDelete: false,
            origin: .myEvent
        )

        let ref = db.collection("events").document(newEvent.id)

    do {
            try ref.setData(from: newEvent) { err in

                if let err = err {
                    print("❌ Firestore error:", err.localizedDescription)
                    self.alertMessage = String(localized:"network_error_try_again.")
                    self.showAlert = true
                    return
                }
                NotificationManager.shared.scheduleNotification(for: newEvent)
                self.syncBusySlots(for: newEvent)
            }
        } catch {
            print("❌ Encode error:", error)
            return false
        }

        return true
    }



    func updateEvent(_ event: CalendarEvent,
                     newTitle: String,
                     newDate: Date,
                     newStart: Date,
                     newEnd: Date,
                     newColorHex: String) {

        guard let idx = events.firstIndex(where: { $0.id == event.id }) else { return }

        // Update local
        events[idx].title = newTitle
        events[idx].date = newDate
        events[idx].startTime = newStart
        events[idx].endTime = newEnd
        events[idx].colorHex = newColorHex

        // ⭐ Cập nhật Firestore
        if !event.id.isEmpty {
            db.collection("events").document(event.id).updateData([
                "title": newTitle,
                "date": Timestamp(date: newDate),
                "startTime": Timestamp(date: newStart),
                "endTime": Timestamp(date: newEnd),
                "colorHex": newColorHex
            ]) { error in
                
                // ⭐⭐ ĐẶT ĐOẠN UPDATE BUSYSLOT TRONG NÀY (đúng scope)
                guard error == nil else { return }

                // Tạo event mới dựa trên thông tin đã update
                let updatedEvent = CalendarEvent(
                    id: event.id,
                    title: newTitle,
                    date: newDate,
                    startTime: newStart,
                    endTime: newEnd,
                    owner: event.owner,
                    sharedUser: event.sharedUser,
                    createdBy: event.createdBy,
                    participants: event.participants,
                    colorHex: newColorHex,
                    pendingDelete: false,
                    origin: .myEvent
                )
            // ⭐ Ghi đè busySlot của chủ event
                self.syncBusySlots(for: updatedEvent)
            }
        }
    }


    // MARK: DELETE EVENT with PENDING DELETE
    func deleteEvent(_ event: CalendarEvent) {

        guard let idx = events.firstIndex(where: { $0.id == event.id }) else { return }

        // 1️⃣ Mark pending
        events[idx].pendingDelete = true
        saveEvents()

        // 2️⃣ Xoá local NGAY
        let evId = event.id
        events.removeAll { $0.id == evId }
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: [event.id])

        saveEvents()
        updateGroupedEvents()

        // 3️⃣ Xoá remote (kệ nếu fail — pendingDelete sẽ retry khi app mở lại)
        deleteRemoteOnly(event)

        // 4️⃣ Remove busySlot remote
        removeBusySlotForAllParticipants(event: event)


        // 5️⃣ Clear local busySlots cache for the affected owner (so next fetch reads fresh)
        //    - owner is the publicCalendar document id we use as cache key
        DispatchQueue.main.async {
            self.busySlotCache.removeValue(forKey: event.owner)
            self.busySlotPremiumCache.removeValue(forKey: event.owner)
        }
       
    }

    
    func fetchPremiumStatus(for userId: String, completion: @escaping (Bool) -> Void) {
        db.collection("premiumStatus")
            .document(userId)
            .getDocument { snap, err in
                if let data = snap?.data(),
                   let value = data["isPremium"] as? Bool {
                    completion(value)
                } else {
                    completion(false)
                }
            }
    }

    
    // MARK: - Fetch busy slots (one-shot)
    func fetchBusySlots(
        for userId: String,
        forceRefresh: Bool = false,
        completion: @escaping ([CalendarEvent], PremiumTier) -> Void
    ) {

        // 1️⃣ Cache (nếu có và không force)
        if !forceRefresh,
           let cachedSlots = partnerBusySlotCache[userId],
           let cachedTier  = partnerTierCache[userId] {

            completion(cachedSlots, cachedTier)
            return
        }

        // 2️⃣ Load Firestore
        db.collection("publicCalendar")
            .document(userId)
            .getDocument { snapshot, error in

                guard
                    error == nil,
                    let snapshot = snapshot,
                    snapshot.exists,
                    let data = snapshot.data()
                else {
                    completion([], .free)
                    return
                }

                // ===============================
                // 1️⃣ RESOLVE TIER
                // ===============================
                let tierString = data["tier"] as? String ?? "free"
                let tier: PremiumTier
                switch tierString {
                case "pro":
                    tier = .pro
                case "premium":
                    tier = .premium
                default:
                    tier = .free
                }

                // ===============================
                // 2️⃣ BUSY SLOTS
                // ===============================
                let rawSlots = data["busySlots"] as? [[String: Any]] ?? []
                let now = Date()

                let slots: [CalendarEvent] = rawSlots.compactMap { dict in
                    guard
                        let start = dict["start"] as? TimeInterval,
                        let end   = dict["end"]   as? TimeInterval
                    else { return nil }

                    let s = Date(timeIntervalSince1970: start)
                    let e = Date(timeIntervalSince1970: end)

                    // ❌ Bỏ slot đã kết thúc
                    if e < now { return nil }

                    // ⭐ phân biệt event / manual qua source
                    let source = dict["source"] as? String ?? "event"

                    let colorHex: String = (source == "manual")
                        ? "#FFA500"    // manual → cam
                        : "#FF0000"    // event → đỏ

                    return CalendarEvent(
                        id: dict["id"] as? String ?? UUID().uuidString,
                        title: dict["title"] as? String ?? String(localized: "busy"),
                        date: Calendar.current.startOfDay(for: s),
                        startTime: s,
                        endTime: e,
                        owner: userId,
                        sharedUser: userId,
                        createdBy: userId,
                        participants: [userId],
                        colorHex: colorHex,
                        pendingDelete: false,
                        origin: .busySlot          // 🔒 GIỮ NGUYÊN
                    )
                }

                // ===============================
                // 3️⃣ CACHE
                // ===============================
                DispatchQueue.main.async {
                    self.partnerBusySlotCache[userId] = slots
                    self.partnerTierCache[userId] = tier
                    self.partnerBusySlots[userId] = slots
                }

                completion(slots, tier)
            }
    }


    func openChat(eventId: String) {
          selectedChatEventId = eventId
      }

      func openEvent(eventId: String) {
          selectedEventId = eventId
      }


    // MARK: - Remove busy slot
    private func removeBusySlotFromPublicCalendar(event: CalendarEvent) {
        let uid = event.owner

        let doc = db.collection("publicCalendar").document(uid)
        doc.getDocument { snap, _ in
            var slots = snap?.data()?["busySlots"] as? [[String: Any]] ?? []

            // ✅ CHỈ XOÁ BUSY SLOT CỦA EVENT
            slots.removeAll { dict in
                (dict["id"] as? String) == event.id &&
                (dict["source"] as? String) == "event"
            }

            doc.setData(["busySlots": slots], merge: true)
        }
    }


    // MARK: - Add Appointment (khách đặt lịch cho người share UID)
    func addAppointment(
        forSharedUser ownerUid: String,
        title: String,
        start: Date,
        end: Date,
        createdBy: String,
        completion: @escaping (Bool, String?) -> Void
    ) {
        self.isAdding = true

        guard let currentUid = Auth.auth().currentUser?.uid else {
            self.isAdding = false
            completion(false, String(localized: "you_need_to_log_in"))
            return
        }

        // ⭐ 1) Nếu B đặt lịch cho A ➜ CHECK ALLOW trước
        if ownerUid != currentUid {

            AccessService.shared.isAllowed(ownerUid: ownerUid, otherUid: currentUid) { allowed in

                if !allowed {
                    // ❗ Chưa được phép ➜ Tạo REQUEST
                    let requesterName = self.userNames[currentUid] ?? currentUid

                    AccessService.shared.createRequest(
                        owner: ownerUid,
                        requester: currentUid,
                        requesterName: requesterName
                    )


                    DispatchQueue.main.async {
                        self.isAdding = false
                        completion(false,  String(localized: "request_not_allowed_sent"))
                    }
                    return
                }

                // ⭐ Nếu đã allow → tiếp tục tạo event
                self._actuallyCreateAppointmentEvent(
                    ownerUid: ownerUid,
                    title: title,
                    start: start,
                    end: end,
                    createdBy: createdBy,
                    completion: completion
                )
            }

            return // ⛔ KHÔNG chạy xuống dưới nữa
        }

        // ⭐ 2) A tự đặt cho A → tạo luôn
        self._actuallyCreateAppointmentEvent(
            ownerUid: ownerUid,
            title: title,
            start: start,
            end: end,
            createdBy: createdBy,
            completion: completion
        )
    }
    private func _actuallyCreateAppointmentEvent(
        ownerUid: String,
        title: String,
        start: Date,
        end: Date,
        createdBy: String,
        completion: @escaping (Bool, String?) -> Void
    ) {
        // ❌ CHẶN ĐẶT LỊCH QUÁ KHỨ
        let now = Date()
        if start < now {
            DispatchQueue.main.async { self.isAdding = false }
            completion(false, String(localized: "cannot_book_past_time"))
            return
        }

        // ===============================
        // 1️⃣ KIỂM TRA OVERLAP (OWNER A)
        // ===============================
        fetchBusySlots(for: ownerUid) { busySlots, ownerTier in
            let overlap = busySlots.contains { $0.startTime < end && $0.endTime > start }
            if overlap {
                DispatchQueue.main.async { self.isAdding = false }
                completion(false, String(localized: "this_time_slot_is_already_booked"))
                return
            }

            // ===============================
            // 2️⃣ BOOKING RANGE — THEO TIER CỦA OWNER (A)
            // ===============================
            let ownerLimits = PremiumLimits.limits(for: ownerTier)

            if let maxDate = Calendar.current.date(
                byAdding: .day,
                value: ownerLimits.maxBookingDaysAhead,
                to: now
            ),
            start > maxDate {

                DispatchQueue.main.async { self.isAdding = false }

                let msg = {
                    switch ownerTier {
                    case .free:
                        return String(localized: "booking_limit_7_days")
                    case .premium:
                        return String(localized: "premium_booking_limit_90_days")
                    case .pro:
                        return String(localized: "pro_booking_limit_270_days")
                    }
                }()

                completion(false, msg)
                return
            }

            // ===============================
            // 3️⃣ CHECK LOGIN
            // ===============================
            guard let currentUid = Auth.auth().currentUser?.uid else {
                DispatchQueue.main.async { self.isAdding = false }
                completion(false, String(localized: "you_need_to_log_in"))
                return
            }

            // ===============================
            // 4️⃣ LIMIT EVENT / NGÀY — THEO CREATOR (B)
            // ===============================
            let creatorTier = PremiumStoreViewModel.shared.tier
            let creatorLimits = PremiumLimits.limits(for: creatorTier)

            let calendar = Calendar.current
            let eventsCreatedByMeToday = self.events.filter {
                $0.createdBy == currentUid &&
                calendar.isDate($0.startTime, inSameDayAs: start)
            }

            if eventsCreatedByMeToday.count >= creatorLimits.maxEventsPerDay {
                DispatchQueue.main.async { self.isAdding = false }
                completion(false, String(localized: "event_limit_reached"))
                return
            }
            // ===============================
            // 🔒 4.5️⃣ CHECK TRÙNG GIỜ CỦA CREATOR (B)
            // ===============================
            let myConflict = self.events.contains {
                $0.createdBy == currentUid &&
                $0.startTime < end &&
                $0.endTime > start
            }

            if myConflict {
                DispatchQueue.main.async { self.isAdding = false }
                completion(false, String(localized: "you_have_event_this_time"))
                return
            }
            // ===============================
            // 5️⃣ TẠO EVENT DATA
            // ===============================
            let eventData: [String: Any] = [
                "title": title,
                "owner": ownerUid,
                "sharedUser": currentUid,
                "createdBy": createdBy,
                "participants": Array(Set([ownerUid, currentUid])),
                "date": Timestamp(date: start),
                "startTime": Timestamp(date: start),
                "endTime": Timestamp(date: end),
                "colorHex": "#007AFF"
            ]

            // ===============================
            // 6️⃣ GHI FIRESTORE
            // ===============================
            var ref: DocumentReference?
            ref = self.db.collection("events").addDocument(data: eventData) { err in
                DispatchQueue.main.async { self.isAdding = false }

                if let err = err {
                    completion(
                        false,
                        String(localized: "failed_to_create_event") + ": " + err.localizedDescription
                    )
                    return
                }

                guard let id = ref?.documentID else {
                    completion(false, String(localized: "missing_document_id"))
                    return
                }

                // ===============================
                // 7️⃣ LOAD LẠI EVENT + SYNC BUSY
                // ===============================
                self.db.collection("events").document(id).getDocument { snap, _ in
                    guard let snap = snap,
                          let newEvent = CalendarEvent.from(snap) else {
                        completion(false, String(localized: "failed_to_load_created_event"))
                        return
                    }

                    // cập nhật busySlots cho A & B
                    self.syncBusySlots(for: newEvent)

                    // clear cache để reload realtime
                    self.partnerBusySlotCache.removeValue(forKey: ownerUid)
                    self.partnerBusySlotCache.removeValue(forKey: currentUid)

                    completion(true, nil)

                    DispatchQueue.main.async {
                        self.alertMessage = String(localized: "booking_created_successfully")
                        self.showAlert = true
                    }
                }
            }
        }
    }


    func updatePublicCalendarBusySlot(
        for userId: String,
        start: Date,
        end: Date,
        eventId: String
    ) {
        let doc = db.collection("publicCalendar").document(userId)

        doc.getDocument { snap, _ in
            var existing = snap?.data()?["busySlots"] as? [[String: Any]] ?? []

            // ❗ Xoá slot EVENT cũ cùng eventId (nếu có)
            existing.removeAll {
                ($0["id"] as? String) == eventId &&
                ($0["source"] as? String) == "event"
            }

            let newSlot: [String: Any] = [
                "id": eventId,                    // ⭐ eventId
                "source": "event",                // ⭐ phân biệt
                "title": "busy_event",
                "start": start.timeIntervalSince1970,
                "end": end.timeIntervalSince1970
            ]

            existing.append(newSlot)

            doc.setData(["busySlots": existing], merge: true)
        }
    }

    func listenToEvents() {
        guard let uid = currentUserId else { return }

        eventsListener?.remove()

        eventsListener = db.collection("events")
            .whereField("participants", arrayContains: uid)
            .addSnapshotListener { snapshot, error in
                guard let snapshot = snapshot else { return }

                DispatchQueue.main.async {

                    let now = Date()

                    // 1) Parse Firestore
                    let incoming = snapshot.documents.compactMap { CalendarEvent.from($0) }

                    // Giữ event chưa hết hạn
                    let firestoreUpcoming = incoming
                        .filter { $0.endTime >= now }
                        .sorted { $0.startTime < $1.startTime }

                    // 2) Lưu danh sách ID cũ (để detect event mới)
                    let oldIds = Set(self.events.map { $0.id })

                    // ❗ FIX: local = Firestore hoàn toàn
                    self.events = firestoreUpcoming

                    // 3) Update local + UI
                    self.saveEvents()
                    self.updateGroupedEvents()

                    // 4) Detect event mới
                    let newIds = Set(firestoreUpcoming.map { $0.id })
                    let addedIds = newIds.subtracting(oldIds)

                    for ev in firestoreUpcoming {
                        if addedIds.contains(ev.id),
                           ev.createdBy != uid,
                           ev.startTime > now,
                           UserDefaults.standard.bool(forKey: "firebasePushEnabled")
                        {
                            NotificationManager.shared.scheduleNotification(for: ev)
                            print("🔔 NEW EVENT LOCAL NOTIFICATION:", ev.title)
                        }
                    }

                    // 5) Listen busySlots cho participants
                    let allUsers = Set(incoming.flatMap { $0.participants })
                    for user in allUsers {
                        self.listenToBusySlots(sharedUserId: user)
                    }
                }
            }
    }

    func clearLocalEvents() {
        // 1️⃣ Remove ALL event listeners
        eventsListener?.remove()
        appointmentsListener?.remove()
        createdAppointmentsListener?.remove()

        eventsListener = nil
        appointmentsListener = nil
        createdAppointmentsListener = nil

        // 2️⃣ Remove ALL busySlots listeners (multi-user)
        for (_, listener) in busySlotListeners {
            listener.remove()
        }
        busySlotListeners.removeAll()

        // 3️⃣ Clear local caches
        self.events = []
        self.pastEvents = []
        self.groupedByDay = [:]
        self.sharedLinks = []

        UserDefaults.standard.removeObject(forKey: "upcomingEvents")
        UserDefaults.standard.removeObject(forKey: "pastEvents")
        UserDefaults.standard.removeObject(forKey: "shared_links")

        print("🧹 CLEAR: listeners + cache")
    }

    /// Gom event mới vào danh sách local, tránh trùng ID và tránh revive pendingDelete
    func merge(_ incoming: [CalendarEvent]) {
        var updated = self.events

        for ev in incoming {

            // ❌ Nếu event này đang pendingDelete → không revive
            if let exist = updated.first(where: { $0.id == ev.id }),
               exist.pendingDelete {
                continue
            }

            if let idx = updated.firstIndex(where: { $0.id == ev.id }) {
                // ✔ Update event đã tồn tại
                updated[idx] = ev
            } else {
                // ✔ Thêm event mới
                updated.append(ev)
            }
        }

        // ✔ Lưu và regroup
        self.events = updated
        self.saveEvents()
        self.updateGroupedEvents()
    }



    // MARK: - Listeners (prevent revival)
    func listenToBusySlots(sharedUserId: String) {
        // Nếu đã có listener cho user này → bỏ listener cũ
        busySlotListeners[sharedUserId]?.remove()

        let listener = db.collection("publicCalendar")
            .document(sharedUserId)
            .addSnapshotListener { snap, err in

                guard let data = snap?.data() else { return }

                let raw = data["busySlots"] as? [[String: Any]] ?? []
                let nowSec = Date().timeIntervalSince1970

                let slots: [CalendarEvent] = raw.compactMap { dict in
                    guard var start = dict["start"] as? Double,
                          var end   = dict["end"]   as? Double else {
                        return nil
                    }

                    // Convert ms → s nếu cần
                    if start > 10_000_000_000 { start /= 1000 }
                    if end   > 10_000_000_000 { end   /= 1000 }

                    // ❌ Bỏ slot đã kết thúc
                    if end < nowSec { return nil }

                    let s = Date(timeIntervalSince1970: start)
                    let e = Date(timeIntervalSince1970: end)

                    // ⭐ PHÂN BIỆT EVENT / MANUAL
                    let source = dict["source"] as? String ?? "event"

                    let colorHex: String = (source == "manual")
                        ? "#FFA500"    // manual → cam
                        : "#FF0000"    // event → đỏ

                    return CalendarEvent(
                        id: dict["id"] as? String ?? UUID().uuidString,
                        title: dict["title"] as? String ?? String(localized: "busy"),
                        date: Calendar.current.startOfDay(for: s),
                        startTime: s,
                        endTime: e,
                        owner: sharedUserId,
                        sharedUser: sharedUserId,
                        createdBy: sharedUserId,
                        participants: [sharedUserId],
                        colorHex: colorHex,
                        pendingDelete: false,
                        origin: .busySlot   // 🔒 GIỮ NGUYÊN, KHÔNG ĐỔI MODEL
                    )
                }

                DispatchQueue.main.async {
                    self.partnerBusySlots[sharedUserId] = slots
                }
            }

        busySlotListeners[sharedUserId] = listener
    }


    // MARK: Sync offDays
    func syncOffDaysToFirebase(offDays: Set<Date>, completion: (() -> Void)? = nil) {
        guard let uid = currentUserId else {
            completion?()
            return
        }

        let timestamps = offDays.map { $0.timeIntervalSince1970 }

        db.collection("publicCalendar").document(uid)
            .setData(["offDays": timestamps], merge: true) { error in
                completion?()   // 🔥 gọi callback sau khi Firebase cập nhật xong
            }
    }

    // MARK: Helpers

    var currentUserId: String? {
        Auth.auth().currentUser?.uid
    }
    func markSharedLinkConnected(uid: String) {

        print("🟡 CALLED markSharedLinkConnected with uid =", uid)
        print("📦 sharedLinks BEFORE:", sharedLinks.map { "\($0.uid)-\($0.status.rawValue)" })

        guard let index = sharedLinks.firstIndex(where: { $0.uid == uid }) else {
            print("❌ NO MATCH SharedLink for uid =", uid)
            return
        }

        sharedLinks[index].status = .connected
        sharedLinks[index].allowedAt = Date()

        print("📦 sharedLinks AFTER:", sharedLinks.map { "\($0.uid)-\($0.status.rawValue)" })

        saveSharedLinks()
        print("💾 saveSharedLinks CALLED")
    }
    func refreshSharedLinksStatus() {
        guard let myUid = Auth.auth().currentUser?.uid else { return }

        let links = sharedLinks
        let group = DispatchGroup()

        for link in links {
            group.enter()

            AccessService.shared.isAllowed(
                ownerUid: link.uid,   // 🔥 SỬA Ở ĐÂY
                otherUid: myUid
            ) { allowed in
                DispatchQueue.main.async {
                    if let index = self.sharedLinks.firstIndex(where: { $0.id == link.id }) {
                        self.sharedLinks[index].status = allowed ? .connected : .pending
                    }
                    group.leave()
                }
            }
        }

        group.notify(queue: .main) {
            self.saveSharedLinks()
        }
    }

    func removePublicCalendarBusySlot(
          for uid: String,
          start: Date,
          end: Date
      ) {
          let db = Firestore.firestore()

          db.collection("publicCalendars")
              .document(uid)
              .collection("busyHours")
              .whereField("startTime", isEqualTo: start)
              .whereField("endTime", isEqualTo: end)
              .getDocuments { snapshot, error in

                  guard let docs = snapshot?.documents else { return }

                  for doc in docs {
                      doc.reference.delete()
                  }
              }
      }

    func syncBusyHoursToFirebase(
        busyIntervals: [(Date, Date)],
        completion: (() -> Void)? = nil
    ) {
        guard let uid = currentUserId else {
            completion?()
            return
        }

        let doc = db.collection("publicCalendar").document(uid)

        doc.getDocument { snap, _ in
            let existing = snap?.data()?["busySlots"] as? [[String: Any]] ?? []

            // ✅ GIỮ busySlot CỦA EVENT (có id trùng event.id)
            let eventSlots = existing.filter {
                $0["source"] as? String == "event"
            }

            // ✅ TẠO busySlot MANUAL MỚI
            let manualSlots: [[String: Any]] = busyIntervals.map {
                [
                    "id": UUID().uuidString,
                    "source": "manual",          // ⭐ BẮT BUỘC
                    "title": String(localized: "busy"),
                    "start": $0.0.timeIntervalSince1970,
                    "end": $0.1.timeIntervalSince1970
                ]
            }

            let merged = eventSlots + manualSlots

            doc.setData(["busySlots": merged], merge: true) { _ in
                completion?()
            }
        }
    }


}
