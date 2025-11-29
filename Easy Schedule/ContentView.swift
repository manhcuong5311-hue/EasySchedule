//
//  ContentView.swift
//  Easy schedule
//
//  Created by Sam Manh Cuong on 11/11/25.
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

    // MARK: - UI fields
    var colorHex: String = "#007AFF"
    var pendingDelete: Bool = false
    var origin: EventOrigin = .myEvent
}



final class EventManager: ObservableObject {
    static let shared = EventManager()
    @EnvironmentObject var session: SessionStore
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

    private var eventsListener: ListenerRegistration?
    private var appointmentsListener: ListenerRegistration?
    private var createdAppointmentsListener: ListenerRegistration?
    private var busySlotsListener: ListenerRegistration?
    // --- Persisted user name cache key
    private let kUserNamesKey = "es_userNames_cache_v1"

    // persisted + in-memory cache
    @Published var userNames: [String: String] = [:] {
        didSet {
            if let data = try? JSONEncoder().encode(userNames) {
                UserDefaults.standard.set(data, forKey: kUserNamesKey)
            }
        }
    }

    // ⭐ PREMIUM FLAG
    private var isPremiumUser: Bool {
        PremiumManager.shared.isPremiumUser
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
        // Huỷ realtime listeners nếu có
        eventsListener?.remove()
        eventsListener = nil

        appointmentsListener?.remove()
        appointmentsListener = nil

        createdAppointmentsListener?.remove()
        createdAppointmentsListener = nil

        busySlotsListener?.remove()
        busySlotsListener = nil

        // Dọn dữ liệu local
        DispatchQueue.main.async {
            self.events.removeAll()
            self.pastEvents.removeAll()
            self.groupedByDay.removeAll()
            self.sharedLinks.removeAll()
            self.saveEvents()
            self.saveSharedLinks()
        }

        print("🧹 EventManager RESET hoàn tất.")
    }

    func reloadForCurrentUser() {
        clearLocalEvents()
        guard let uid = currentUserId else { return }
        print("🔄 Reloading events for user:", uid)
        listenToEvents()
        listenToBusySlots(sharedUserId: uid)
        cleanUpPastEvents()
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
            slots.removeAll { ($0["id"] as? String) == event.id }

            let newSlot: [String: Any] = [
                "id": event.id,
                "title": event.title,
                "owner": event.owner,
                "start": event.startTime.timeIntervalSince1970,
                "end": event.endTime.timeIntervalSince1970
            ]

            slots.append(newSlot)

            docRef.setData(["busySlots": slots], merge: true)
        }
    }

    func syncBusySlots(for event: CalendarEvent) {
        for uid in event.participants {
            self.addBusySlot(for: uid, event: event)
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

        // ❗ CHỐNG TRÙNG GIỜ
        if !allowDuplicateEvents {
            let overlap = events.contains { ev in
                Calendar.current.isDate(ev.date, inSameDayAs: date) &&
                ev.startTime < endTime &&
                startTime < ev.endTime
            }

            if overlap {
                self.alertMessage = String(localized: "time_slot_taken!")
                self.showAlert = true
                return false
            }
        }

        // FREE USER LIMIT
        let isPremium = PremiumManager.shared.isPremiumUser

        if !isPremium {
            let now = Date()
            if let maxDate = Calendar.current.date(byAdding: .day, value: 7, to: now),
               date > maxDate {
                print("🚫 FREE USER: Không được tạo lịch quá 7 ngày")
                return false
            }

            let eventsSameDay = events.filter {
                Calendar.current.isDate($0.date, inSameDayAs: date)
            }
            if eventsSameDay.count >= 4 {
                print("🚫 FREE USER: Quá 4 lịch/ngày")
                return false
            }
        }

        // ⭐ TẠO EVENT LOCAL (owner = UID)
        let newEvent = CalendarEvent(
            id: UUID().uuidString,
            title: title,
            date: date,
            startTime: startTime,
            endTime: endTime,
            owner: uid,                    // ⭐ OWNER = UID (rất quan trọng)
            sharedUser: uid,
            createdBy: uid,
            participants: [uid],           // ⭐ Người tạo event là participant đầu tiên
            colorHex: colorHex,
            pendingDelete: false,
            origin: .myEvent
        )

        // LƯU LOCAL
        DispatchQueue.main.async {
            self.events.append(newEvent)
            self.saveEvents()
        }

        // ⭐ ĐẨY FIRESTORE (owner = UID)
        let data: [String: Any] = [
            "title": newEvent.title,
            "owner": uid,
            "sharedUser": uid,
            "createdBy": uid,
            "participants": [uid],
            "date": Timestamp(date: newEvent.date),
            "startTime": Timestamp(date: newEvent.startTime),
            "endTime": Timestamp(date: newEvent.endTime),
            "colorHex": newEvent.colorHex
        ]

        var ref: DocumentReference?
        ref = db.collection("events").addDocument(data: data) { err in
            if let err = err {
                print("❌ Firestore add error:", err.localizedDescription)
                return
            }

            guard let docId = ref?.documentID else { return }

            DispatchQueue.main.async {
                // cập nhật ID Firebase vào local
                if let i = self.events.firstIndex(where: { $0.id == newEvent.id }) {
                    self.events[i].id = docId

                    // ⭐ Cập nhật busySlot cho TẤT CẢ participants
                    let finalEvent = self.events[i]
                    self.syncBusySlots(for: finalEvent)

                }
            }
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
                self.addBusySlot(for: event.owner, event: updatedEvent)
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
    func fetchBusySlots(for userId: String,
                        forceRefresh: Bool = false,
                        completion: @escaping ([CalendarEvent], Bool) -> Void) {

        // 1️⃣ Nếu không force và đã có cache → trả về ngay
        if !forceRefresh,
           let cachedSlots = partnerBusySlotCache[userId],
           let cachedPremium = partnerPremiumCache[userId] {
            completion(cachedSlots, cachedPremium)
            return
        }

        // 2️⃣ Nếu chưa có cache → gọi Firestore
        fetchPremiumStatus(for: userId) { isPremium in
            self.db.collection("publicCalendar")
                .document(userId)
                .getDocument { snapshot, error in

                    guard let data = snapshot?.data(), error == nil else {
                        completion([], isPremium)
                        return
                    }

                    let premiumFlag = data["isPremium"] as? Bool ?? isPremium
                    let rawSlots = data["busySlots"] as? [[String: Any]] ?? []

                    let now = Date()

                    let slots = rawSlots.compactMap { dict -> CalendarEvent? in
                        guard let start = dict["start"] as? TimeInterval,
                              let end   = dict["end"]   as? TimeInterval else { return nil }

                        let s = Date(timeIntervalSince1970: start)
                        let e = Date(timeIntervalSince1970: end)

                        // ⭐ LỌC BUSY SLOT HẾT HẠN (chỉ thêm dòng này)
                        if e < now { return nil }

                        return CalendarEvent(
                            id: dict["id"] as? String ?? UUID().uuidString,
                            title: dict["title"] as? String ?? "Bận",
                            date: Calendar.current.startOfDay(for: s),
                            startTime: s,
                            endTime: e,
                            owner: userId,
                            sharedUser: userId,
                            createdBy: userId,
                            participants: [userId],
                            colorHex: "#FF0000",
                            pendingDelete: false,
                            origin: .busySlot
                        )
                    }

                    // 3️⃣ LƯU CACHE
                    DispatchQueue.main.async {
                        self.partnerBusySlotCache[userId] = slots
                        self.partnerPremiumCache[userId] = premiumFlag
                        self.partnerBusySlots[userId] = slots   // UI cache
                    }

                    completion(slots, premiumFlag)
                }
        }
    }





    // MARK: - Remove busy slot
    private func removeBusySlotFromPublicCalendar(event: CalendarEvent) {
        let uid = event.owner   // SỬA ĐÚNG

        let doc = db.collection("publicCalendar").document(uid)
        doc.getDocument { snap, err in
            var slots = snap?.data()?["busySlots"] as? [[String: Any]] ?? []
            slots.removeAll { ($0["id"] as? String) == event.id }
            doc.setData(["busySlots": slots], merge: true)
        }
    }

    // MARK: - Add Appointment (khách đặt lịch cho người share UID)
    func addAppointment(forSharedUser sharedUserId: String,
                        title: String,
                        start: Date,
                        end: Date,
                        createdBy: String,
                        completion: @escaping (Bool, String?) -> Void) {

        self.isAdding = true

        // 1️⃣ Kiểm tra trùng giờ (chỉ kiểm tra của chủ lịch A)
        fetchBusySlots(for: sharedUserId) { busySlots, ownerIsPremium in
            let overlap = busySlots.contains { $0.startTime < end && $0.endTime > start }
            if overlap {
                DispatchQueue.main.async { self.isAdding = false }
                completion(false, String(localized: "This_time_slot_is_already_booked!"))
                return
            }

            // 2️⃣ PREMIUM CHECK cho A
            if !ownerIsPremium {
                let now = Date()
                if let maxDate = Calendar.current.date(byAdding: .day, value: 7, to: now),
                   start > maxDate {

                    DispatchQueue.main.async { self.isAdding = false }
                    completion(false, String(localized: "You_can_only_book_within_the_next_7days."))
                    return
                }
            }

            // 3️⃣ Kiểm tra đăng nhập (người tạo lịch là B)
            guard let uid = Auth.auth().currentUser?.uid else {
                DispatchQueue.main.async { self.isAdding = false }
                completion(false,String(localized: "You_need_to_log_in."))
                return
            }

            // 4️⃣ DỮ LIỆU TẠO EVENT
            let eventData: [String: Any] = [
                "title": title,
                "owner": sharedUserId,
                "sharedUser": uid,
                "createdBy": createdBy,
                "participants": Array(Set([sharedUserId, uid])),  // ⭐ siêu quan trọng
                "date": Timestamp(date: start),
                "startTime": Timestamp(date: start),
                "endTime": Timestamp(date: end),
                "colorHex": "#007AFF"
            ]

            // 5️⃣ GHI EVENT VÀO FIRESTORE
            var ref: DocumentReference?
            ref = self.db.collection("events").addDocument(data: eventData) { err in
                DispatchQueue.main.async { self.isAdding = false }

                // ❌ Lỗi tạo event
                if let err = err {
                    completion(false, "Failed_to_create_event: \(err.localizedDescription)")
                    return
                }

                guard let docId = ref?.documentID else {
                    completion(false, "Missing document ID")
                    return
                }

                // 6️⃣ Lấy lại event đầy đủ từ Firestore
                self.db.collection("events").document(docId).getDocument { snap, err in
                    guard let snap = snap,
                          let newEvent = CalendarEvent.from(snap) else {
                        completion(false, "Failed to load created event")
                        return
                    }

                    // ⭐⭐⭐ CẬP NHẬT BUSYSLOT CHO TẤT CẢ PARTICIPANTS (A & B)
                    self.syncBusySlots(for: newEvent)

                    // Xóa cache để load lại dữ liệu
                    self.partnerBusySlotCache.removeValue(forKey: sharedUserId)
                    self.partnerBusySlotCache.removeValue(forKey: uid)

                    completion(true, nil)

                    DispatchQueue.main.async {
                        self.alertMessage = String(localized: "Booking_created_successfully!")
                        self.showAlert = true
                    }
                }
            }
        }
    }

    func updatePublicCalendarBusySlot(for userId: String, start: Date, end: Date) {
        let doc = db.collection("publicCalendar").document(userId)

        doc.getDocument { snap, err in
            var existing = snap?.data()?["busySlots"] as? [[String: Any]] ?? []

            let newSlot: [String: Any] = [
                "id": UUID().uuidString,
                "title": "Bận",
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

                    // 1) Parse events từ Firestore
                    let incoming = snapshot.documents.compactMap { CalendarEvent.from($0) }

                    let now = Date()

                    // 2) Tách upcoming từ Firestore
                    let firestoreUpcoming = incoming
                        .filter { $0.endTime >= now }
                        .sorted { $0.startTime < $1.startTime }

                    // 3) Giữ pastEvents LOCAL — không đụng
                    // 4) KẾT HỢP upcoming:
                    // 👉 upcoming = (localUpcoming không nằm trong Firestore) + firestoreUpcoming
                    let localUpcoming = self.events.filter { localEv in
                        // giữ những event local mà Firestore không trả về
                        !firestoreUpcoming.contains(where: { $0.id == localEv.id })
                    }

                    // Ghép lại: local còn sót + data firebase mới
                    self.events = (localUpcoming + firestoreUpcoming)
                        .sorted { $0.startTime < $1.startTime }

                    // 5) Lưu local
                    self.saveEvents()

                    // 6) Update UI
                    self.updateGroupedEvents()
                    self.syncBusySlotsOfUser(uid)
                }
            }
    }





    // Thêm vào EventManager (bên trong class)
    func clearLocalEvents() {
        // 1️⃣ Hủy Firestore listeners
        eventsListener?.remove()
        appointmentsListener?.remove()
        createdAppointmentsListener?.remove()
        busySlotsListener?.remove()

        eventsListener = nil
        appointmentsListener = nil
        createdAppointmentsListener = nil
        busySlotsListener = nil

        // 2️⃣ Xóa dữ liệu local
        self.events = []
        self.pastEvents = []
        self.groupedByDay = [:]
        self.sharedLinks = []

        UserDefaults.standard.removeObject(forKey: "upcomingEvents")
        UserDefaults.standard.removeObject(forKey: "pastEvents")
        UserDefaults.standard.removeObject(forKey: "shared_links")

        print("🧹 Đã clear cache + remove mọi Firebase listeners")
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
        busySlotsListener = db.collection("publicCalendar")
            .document(sharedUserId)
            .addSnapshotListener { snap, err in
                guard let data = snap?.data() else { return }

                let raw = data["busySlots"] as? [[String: Any]] ?? []
                let now = Date()

                let slots = raw.compactMap { dict -> CalendarEvent? in
                    guard let start = dict["start"] as? TimeInterval,
                          let end   = dict["end"]   as? TimeInterval else { return nil }

                    let s = Date(timeIntervalSince1970: start)
                    let e = Date(timeIntervalSince1970: end)

                    // ⭐ ⭐ LỌC BUSY SLOT HẾT HẠN – thêm dòng này
                    if e < now { return nil }

                    let id = dict["id"] as? String ?? "\(start)-\(end)-busy"

                    return CalendarEvent(
                        id: id,
                        title: dict["title"] as? String ?? "Bận",
                        date: Calendar.current.startOfDay(for: s),
                        startTime: s,
                        endTime: e,
                        owner: sharedUserId,
                        sharedUser: sharedUserId,
                        createdBy: sharedUserId,
                        participants: [sharedUserId],
                        colorHex: "#FF0000",
                        pendingDelete: false,
                        origin: .busySlot
                    )
                }

                DispatchQueue.main.async {
                    for ev in slots {

                        // Không revive event pendingDelete
                        if self.events.first(where: { $0.id == ev.id && $0.pendingDelete }) != nil {
                            continue
                        }

                        if let idx = self.events.firstIndex(where: { $0.id == ev.id }) {
                            self.events[idx] = ev
                        } else {
                            self.events.append(ev)
                        }
                    }
                }
            }
    }


    func syncBusySlotsOfUser(_ userId: String) {

        db.collection("events")
            .whereField("owner", isEqualTo: userId)
            .getDocuments { snap, err in
                if let err = err {
                    print("❌ syncBusySlotsOfUser error: \(err)")
                    return
                }

                let now = Date()

                // ⭐ CHỈ LẤY EVENT CÒN HIỆU LỰC
                let events = snap?.documents
                    .compactMap { CalendarEvent.from($0) }
                    .filter { $0.endTime >= now } ?? []

                // ⭐ CHUYỂN EVENT -> busySlots
                let busySlotsData = events.map { ev in
                    return [
                        "id": ev.id,
                        "title": ev.title,
                        "start": ev.startTime.timeIntervalSince1970,
                        "end": ev.endTime.timeIntervalSince1970,
                        "owner": ev.owner
                    ]
                }

                // ⭐ GHI ĐÈ BUSYSLOTS — XOÁ SLOT CŨ TỰ ĐỘNG
                self.db.collection("publicCalendar")
                    .document(userId)
                    .setData([
                        "busySlots": busySlotsData
                    ], merge: true)
            }
    }



    // MARK: Sync offDays
    func syncOffDaysToFirebase(offDays: Set<Date>) {
        guard let uid = currentUserId else { return }

        let timestamps = offDays.map { $0.timeIntervalSince1970 }

        db.collection("publicCalendar").document(uid)
            .setData(["offDays": timestamps], merge: true)
    }

    // MARK: Helpers

    var currentUserId: String? {
        Auth.auth().currentUser?.uid
    }
}


extension Array {
    func partitioned(by condition: (Element) -> Bool) -> (matches: [Element], nonMatches: [Element]) {
        var matches = [Element]()
        var nonMatches = [Element]()
        for element in self {
            if condition(element) { matches.append(element) } else { nonMatches.append(element) }
        }
        return (matches, nonMatches)
    }
}

// MARK: - ContentView
struct ContentView: View {
    
    @EnvironmentObject var eventManager: EventManager
    @State private var showPastEvents = false
    @AppStorage("isPremiumUser") private var isPremiumUser: Bool = false
    
    var body: some View {
        
        TabView {
            
            NavigationStack {
                EventListView(showPastEvents: $showPastEvents)
            }
            .tabItem {
                Label(String(localized: "event_list"), systemImage: "list.bullet.rectangle")
            }
            
            NavigationStack {
                CustomizableCalendarView()
            }
            .tabItem {
                Label(String(localized: "my_calendar"), systemImage: "calendar")
            }
            
            NavigationStack {
                PartnerCalendarTabView()
            }
            .tabItem {
                Label(String(localized: "partners"), systemImage: "person.2.fill")
            }
            
            NavigationStack {
                SettingsView()
            }
            .tabItem {
                Label(String(localized: "settings"), systemImage: "gearshape")
            }
        }
        .onAppear {
            NotificationManager.shared.requestPermission()

            // ⭐⭐ THÊM DÒNG NÀY ⭐⭐
            eventManager.cleanUpPastEvents()
        }
    }
}


private func rememberGroupedByMonth(events: [CalendarEvent]) -> [Date: [CalendarEvent]] {
    Dictionary(grouping: events) { event in
        let comps = Calendar.current.dateComponents([.year, .month], from: event.date)
        return Calendar.current.date(from: comps)!
    }
}

private func rememberGroupedByWeek(events: [CalendarEvent]) -> [Int: [CalendarEvent]] {
    Dictionary(grouping: events) { event in
        Calendar.current.component(.weekOfMonth, from: event.date)
    }
}

private func rememberGroupedByDay(events: [CalendarEvent]) -> [Date: [CalendarEvent]] {
    Dictionary(grouping: events) { event in
        Calendar.current.startOfDay(for: event.date)
    }
}


struct EventListView: View {
    @EnvironmentObject var eventManager: EventManager
    @Binding var showPastEvents: Bool
    @State private var selectedWeek: (year: Int, week: Int)? = nil
    @State private var selectedDate: Date? = nil  // dùng để mở chi tiết ngày
    @State private var searchText: String = ""    // dùng để tìm kiếm
    @State private var showDeleteAlert = false
    @State private var eventToDelete: CalendarEvent? = nil
    var body: some View {
        VStack {
            // Nút chuyển giữa 2 chế độ
            Picker("", selection: $showPastEvents) {
                Text(String(localized: "current_events")).tag(false)
                    Text(String(localized: "past_events")).tag(true)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            
            // Ô tìm kiếm chỉ hiện khi xem "lịch đã qua"
            if showPastEvents {
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.gray)
                    TextField(String(localized: "search_placeholder"), text: $searchText)
                        .textFieldStyle(PlainTextFieldStyle())
                }
                .padding(10)
                .background(Color(.systemGray6))
                .cornerRadius(12)
                .padding(.horizontal)
            }
            
            if showPastEvents {
                pastEventsGroupedView
            } else {
                upcomingEventsList
            }
        }
        .navigationTitle(
            showPastEvents
            ? String(localized: "past_events")
            : String(localized: "current_events")
        )

        .onAppear {
            eventManager.cleanUpPastEvents()
                 // ⭐ thêm dòng này
        }

        // Sheet mở danh sách sự kiện trong ngày
        // Thay đoạn này:
        
        
        // ➜ Bằng đoạn này:
        .sheet(isPresented: Binding(
            get: { selectedWeek != nil },
            set: { if !$0 { selectedWeek = nil } }
        )) {
            if let week = selectedWeek {
                PastEventsByWeekView(week: week)
                    .environmentObject(eventManager)
            }
        }

        .alert(String(localized: "delete_event_title"), isPresented: $showDeleteAlert) {
            
            // NÚT DELETE
            Button(String(localized: "delete"), role: .destructive) {
                if let event = eventToDelete {
                    eventManager.deleteEvent(event)
                }
                eventToDelete = nil
            }

            // NÚT CANCEL
            Button(String(localized: "cancel"), role: .cancel) {
                eventToDelete = nil
            }

        } message: {
            let eventTitle = eventToDelete?.title ?? ""
            let prefix = String(localized: "delete_event_confirm_prefix")

            Text("\(prefix) “\(eventTitle)”?")
        }
    }
    private func formattedMonth(_ date: Date) -> String {
        date.formatted(.dateTime.month(.wide).year())
    }

    
    
    // MARK: - Lịch hiện tại (gộp theo Tháng → Tuần → Ngày)
   
    private var upcomingEventsList: some View {
        // ✅ 1. Tạo formatter dùng chung (không tạo mới mỗi lần)
        func formattedMonth(_ date: Date) -> String {
            date.formatted(.dateTime.month(.wide).year())
        }

        
        func formattedMediumDate(_ date: Date) -> String {
            date.formatted(date: .numeric, time: .omitted)
        }

        
        func formattedTime(_ date: Date) -> String {
            date.formatted(date: .omitted, time: .shortened)
        }

        
        // ✅ 2. Tính trước dữ liệu nhóm, tránh lặp trong body
        // Thực hiện 1 lần khi body chạy (SwiftUI sẽ diff tự động)
        let groupedByMonth = rememberGroupedByMonth(events: eventManager.events)
        let sortedMonths = groupedByMonth.keys.sorted()
        
        return List {
            if eventManager.events.isEmpty {
                Text(String(localized: "no_upcoming_events"))
                    .foregroundColor(.secondary)
            } else {
                // ✅ 3. Vòng lặp hiển thị tháng
                ForEach(sortedMonths, id: \.self) { monthDate in
                    let monthEvents = groupedByMonth[monthDate] ?? []
                    Section(header:
                                HStack {
                        Text(formattedMonth(monthDate))
                            .font(.headline)
                        Spacer()
                        let template = String(localized: "number_of_events_month")
                        Text(template.replacingOccurrences(of: "{count}", with: "\(monthEvents.count)"))

                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    ) {
                        // ✅ 4. Gom theo tuần
                        let groupedByWeek = rememberGroupedByWeek(events: monthEvents)
                        let sortedWeeks = groupedByWeek.keys.sorted()
                        
                        ForEach(sortedWeeks, id: \.self) { week in
                            let weekEvents = groupedByWeek[week] ?? []
                            let weekPrefix = String(localized: "week_prefix")

                            Section(header:
                                Text("\(weekPrefix) \(week)")
                                    .font(.subheadline.bold())
                                    .foregroundColor(.secondary)
                            )
 {
                                // ✅ 5. Gom theo ngày
                                let groupedByDay = rememberGroupedByDay(events: weekEvents)
                                let sortedDays = groupedByDay.keys.sorted()
                                
                                ForEach(sortedDays, id: \.self) { day in
                                    let dayEvents = groupedByDay[day] ?? []
                                    Section(header:
                                                Text(formattedDayHeader(day))
                                        .fontWeight(.bold)
                                            
                                    ) {
                                        ForEach(dayEvents.sorted { $0.startTime < $1.startTime }) { event in
                                            HStack(alignment: .top, spacing: 8) {
                                                Circle()
                                                    .fill(Color(hex: event.colorHex.isEmpty ? "#FF0000" : event.colorHex))
                                                    .frame(width: 12, height: 12)
                                                VStack(alignment: .leading, spacing: 4) {
                                                    Text(event.title)
                                                        .font(.headline)

                                                    // ⭐ Label phân loại lịch theo origin
                                                    Text(originLabel(for: event))
                                                        .font(.caption)
                                                        .foregroundColor(.blue)

                                                    // 🔵 Hiển thị tên người dùng thay cho UID
                                                    if event.origin == .iCreatedForOther {
                                                        HStack(spacing: 4) {
                                                            UserNameView(uid: event.createdBy)   // A
                                                            Text("→")
                                                            UserNameView(uid: event.owner)       // B  <<<< CHỈNH ĐÚNG CHỖ NÀY
                                                        }
                                                        .font(.subheadline)
                                                        .foregroundColor(.secondary)
                                                    } else {
                                                        UserNameView(uid: event.createdBy)
                                                            .font(.subheadline)
                                                            .foregroundColor(.secondary)
                                                    }




                                                    Text("\(formattedTime(event.startTime)) - \(formattedTime(event.endTime))")
                                                        .font(.caption)
                                                        .foregroundColor(.secondary)
                                                }
                                                Spacer()
                                            }

                                            .padding(.vertical, 4)
                                            .contentShape(Rectangle())
                                            .swipeActions {
                                                Button(role: .destructive) {
                                                    showDeleteConfirmation(for: event)
                                                } label: {
                                                    Label(String(localized: "delete"), systemImage: "trash")

                                                }
                                            }
                                     .padding(.vertical, 4)
                                        }
                                        .onDelete(perform: deleteUpcomingEvent)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        
    }
    private func formattedDayHeader(_ date: Date) -> String {
        date.formatted(.dateTime.weekday(.wide).day())
    }


    private func showDeleteConfirmation(for event: CalendarEvent) {
        eventToDelete = event
        showDeleteAlert = true
    }
    
    // MARK: - Lịch đã qua (gộp theo tháng + tuần + tìm kiếm)
    private var pastEventsGroupedView: some View {
        // Lọc theo từ khóa tìm kiếm (title hoặc owner)
        let filteredEvents = eventManager.pastEvents.filter { event in
            searchText.isEmpty ||
            event.title.localizedCaseInsensitiveContains(searchText) ||
            event.owner.localizedCaseInsensitiveContains(searchText)
        }
        
        // Nhóm theo tháng (dựa trên năm + tháng)
        let groupedByMonth = Dictionary(grouping: filteredEvents) { event -> Date in
            let comps = Calendar.current.dateComponents([.year, .month], from: event.date)
            return Calendar.current.date(from: comps)!
        }
        // Sắp xếp tháng mới nhất lên trên
        let sortedMonths = groupedByMonth.keys.sorted(by: >)
        
        return List {
            if filteredEvents.isEmpty {
                Text(
                    searchText.isEmpty
                    ? String(localized: "no_past_events")
                    : String(localized: "no_results_found")
                )

                    .foregroundColor(.secondary)
            } else {
                ForEach(sortedMonths, id: \.self) { monthDate in
                    let monthEvents = groupedByMonth[monthDate] ?? []
                    
                    // Hiển thị tháng
                    Section(header:
                                HStack {
                        Text(formattedMonth(monthDate))
                            .font(.headline)
                        Spacer()
                        let template = String(localized: "number_of_events_month")
                        Text(template.replacingOccurrences(of: "{count}", with: "\(monthEvents.count)"))

                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    ) {
                        // Nhóm trong tháng đó theo tuần
                        let groupedByWeek = Dictionary(grouping: monthEvents) { event -> Int in
                            Calendar.current.component(.weekOfMonth, from: event.date)
                        }
                        let sortedWeeks = groupedByWeek.keys.sorted()
                        
                        ForEach(sortedWeeks, id: \.self) { week in
                            let weekEvents = groupedByWeek[week] ?? []
                            
                            Button {
                                // Gộp tuần này để mở danh sách chi tiết
                                let comps = Calendar.current.dateComponents([.yearForWeekOfYear, .weekOfYear], from: weekEvents.first!.date)
                                selectedWeek = (comps.yearForWeekOfYear!, comps.weekOfYear!)

                            } label: {
                                HStack {
                                    let sampleDate = weekEvents.first!.date
                                    let week = Calendar.current.component(.weekOfMonth, from: sampleDate)

                                    let weekPrefix = String(localized: "week_prefix")
                                    let monthName = sampleDate.formatted(.dateTime.month(.wide))

                                    Text("\(weekPrefix) \(week) \(monthName)")
                                        .font(.body)

                                    Spacer()

                                    let template = String(localized: "number_of_events_week")
                                    Text(template.replacingOccurrences(of: "{count}",
                                                                       with: "\(weekEvents.count)"))
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }


                                .padding(.vertical, 4)
                            }
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }
   
    // MARK: - Hàng hiển thị sự kiện
    private func eventRow(_ event: CalendarEvent) -> some View {
        VStack(alignment: .leading, spacing: 4) {

            // ⭐ Tiêu đề
            Text(event.title)
                .font(.headline)

            // ⭐ Hàng thông tin người tạo + ngày
            HStack(spacing: 4) {

                if event.origin == .iCreatedForOther {
                    HStack(spacing: 4) {
                        UserNameView(uid: event.createdBy)   // A
                        Text("→")
                        UserNameView(uid: event.owner)       // B  <<<< CHỈNH ĐÚNG CHỖ NÀY
                    }
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                } else {
                    UserNameView(uid: event.createdBy)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }




                Text("•")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                Text(formattedDate(event.date))
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            // ⭐ Thời gian
            Text("\(formattedTime(event.startTime)) - \(formattedTime(event.endTime))")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
    }

    // MARK: - Xoá sự kiện hiện tại
    private func deleteUpcomingEvent(at offsets: IndexSet) {
        eventManager.events.remove(atOffsets: offsets)
    }
    
    // MARK: - Helper định dạng
    private func formattedDate(_ date: Date) -> String {
        date.formatted(.dateTime.day().month().year())
    }

    
    func formattedTime(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }

}
private func originLabel(for event: CalendarEvent) -> String {
    switch event.origin {
    case .myEvent:
        return String(localized: "origin_my_event")
    case .createdForMe:
        return String(localized: "origin_created_for_me")
    case .iCreatedForOther:
        return String(localized: "origin_i_created_for_other")
    case .busySlot:
        return String(localized: "origin_busy")
    }
}


struct UserNameView: View {
    @EnvironmentObject var eventManager: EventManager
    let uid: String
    @State private var name: String = ""
    
    var body: some View {
        Text(name.isEmpty ? uid : name)
            .onAppear {
                eventManager.name(for: uid) { fetched in
                    self.name = fetched
                }
            }
    }
}


struct PastEventsByWeekView: View {
    @EnvironmentObject var eventManager: EventManager
    let week: (year: Int, week: Int)
    @Environment(\.dismiss) private var dismiss

    @State private var showConfirmClear = false   // 🔥 popup Clear All

    var body: some View {
        NavigationStack {
            List {
                ForEach(eventsThisWeek) { event in
                    VStack(alignment: .leading, spacing: 4) {

                        // ⭐ Tiêu đề sự kiện
                        Text(event.title)
                            .font(.headline)

                        // ⭐ Hiển thị tên người dùng
                        if event.origin == .iCreatedForOther {
                            HStack(spacing: 4) {
                                UserNameView(uid: event.createdBy)
                                Text("→")
                                UserNameView(uid: event.owner)
                            }
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        } else {
                            UserNameView(uid: event.createdBy)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }

                        // ⭐ Thời gian
                        Text(formatted(event.startTime))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 4)
                }
                .onDelete(perform: deleteAt)     // 🔥 Swipe xoá từng item
            }
            .navigationTitle(weekOfMonthTitle)
            .toolbar {

                // 🔥 Nút Clear All (nổi bật)
                ToolbarItem(placement: .navigationBarLeading) {
                    if !eventsThisWeek.isEmpty {
                        Button(role: .destructive) {
                            showConfirmClear = true
                        } label: {
                            Text(String(localized: "clear_all"))
                        }
                    }
                }

                // 🔥 Close
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(String(localized: "close")) { dismiss() }
                }
            }

            // 🔥 Popup xác nhận xoá tất cả
            .alert(
                String(localized: "are_you_sure_you_want_to_delete_all_events_for_this_week"),
                isPresented: $showConfirmClear
            ) {
                Button(String(localized: "delete_all"), role: .destructive) {
                    clearAll()
                }
                Button(String(localized: "cancel"), role: .cancel) {}
            }
        }
    }

    // MARK: - Swipe delete
    private func deleteAt(at offsets: IndexSet) {
        let arr = eventsThisWeek
        for index in offsets {
            let item = arr[index]

            if let realIndex = eventManager.pastEvents.firstIndex(where: { $0.id == item.id }) {
                eventManager.pastEvents.remove(at: realIndex)
            }
        }
        eventManager.savePastEvents()
    }

    // MARK: - Clear All
    private func clearAll() {
        eventManager.pastEvents.removeAll {
            Calendar.current.component(.weekOfYear, from: $0.date) == week.week &&
            Calendar.current.component(.yearForWeekOfYear, from: $0.date) == week.year
        }
        eventManager.savePastEvents()
    }

    // MARK: - Lọc events trong tuần này
    private var eventsThisWeek: [CalendarEvent] {
        eventManager.pastEvents.filter {
            Calendar.current.component(.weekOfYear, from: $0.date) == week.week &&
            Calendar.current.component(.yearForWeekOfYear, from: $0.date) == week.year
        }
        .sorted(by: { $0.startTime < $1.startTime })
    }

    // MARK: - Format time
    private func formatted(_ date: Date) -> String {
        date.formatted(.dateTime
            .hour(.twoDigits(amPM: .abbreviated))
            .minute(.twoDigits)
            .day()
            .month()
            .year()
        )
    }

    // MARK: - Title cho Navigation Bar
    private var weekOfMonthTitle: String {
        guard let sample = eventsThisWeek.first else { return "" }

        let calendar = Calendar.current
        let weekOfMonth = calendar.component(.weekOfMonth, from: sample.date)

        let weekPrefix = String(localized: "week_prefix")
        let monthName = sample.date.formatted(.dateTime.month(.wide))

        return "\(weekPrefix) \(weekOfMonth) \(monthName)"
    }
}




struct CustomizableCalendarView: View {
    @EnvironmentObject var eventManager: EventManager
    @State private var selectedDate: Date? = nil
    @State private var showAddSheet: Bool = false
    @State private var showDeleteAlert = false
    @State private var eventToDelete: CalendarEvent? = nil
    @State private var showShareSheet = false
    @State private var shareLink: URL? = nil

    @State private var offDays: Set<Date> = [] {
        didSet { saveOffDaysToLocal() }
    }

    private func saveOffDaysToLocal() {
        let timestamps = offDays.map { $0.timeIntervalSince1970 }
        UserDefaults.standard.set(timestamps, forKey: "offDays")
    }

    private func loadOffDaysFromLocal() {
        let timestamps = UserDefaults.standard.array(forKey: "offDays") as? [Double] ?? []
        let dates = timestamps.map { Date(timeIntervalSince1970: $0) }
        self.offDays = Set(dates)
    }

    private var calendar: Calendar {
        var cal = Calendar.current
        cal.firstWeekday = 2
        return cal
    }

    private func showDeleteConfirmation(for event: CalendarEvent) {
        eventToDelete = event
        showDeleteAlert = true
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {

                    // MARK: - Calendar grid
                    CalendarGridView(
                        selectedDate: $selectedDate,
                        eventsByDay: eventManager.groupedByDay,
                        offDays: offDays,
                        isOwner: true
                    )
                    .padding(.top, 8)
                    .frame(maxWidth: .infinity)
                    .simultaneousGesture(TapGesture()) // ⭐ FIX TAP BỊ CHẶN

                    // MARK: - Toggle trùng lịch
                    Toggle(String(localized: "allow_conflict"), isOn: Binding(
                        get: { eventManager.allowDuplicateEvents },
                        set: { eventManager.allowDuplicateEvents = $0 }
                    ))
                    .padding(.horizontal)
                    .padding(.bottom, 4)

                    Divider()

                    // MARK: - Chia sẻ lịch
                    Button {
                       

                        if let uid = Auth.auth().currentUser?.uid,
                           let url = URL(string: "https://easyschedule-ce98a.web.app/calendar/\(uid)") {
                            shareLink = url
                            showShareSheet = true
                        }
                    } label: {
                        HStack {
                            Image(systemName: "square.and.arrow.up")
                            Text(String(localized: "share_calendar")).bold()
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue.opacity(0.2))
                        .cornerRadius(10)
                    }
                    .padding(.horizontal)
                    .sheet(isPresented: $showShareSheet) {
                        if let link = shareLink {
                            ActivityView(activityItems: [link])
                        }
                    }

                    // MARK: - Ngày được chọn
                    if let date = selectedDate {
                        VStack(spacing: 10) {

                            // Button ngày nghỉ
                            Button {
                                toggleOffDay(for: date)
                                eventManager.syncOffDaysToFirebase(offDays: offDays)
                            } label: {
                                HStack {
                                    Image(systemName: isOffDay(date) ? "xmark.circle" : "bed.double.fill")
                                    Text(
                                        isOffDay(date)
                                        ? String(localized: "reopen_day")
                                        : String(localized: "set_day_off")
                                    ).bold()

                                }
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(isOffDay(date) ? Color.green.opacity(0.2) : Color.gray.opacity(0.2))
                                .cornerRadius(10)
                            }
                            .padding(.horizontal)

                            if isOffDay(date) {
                                Text(String(localized: "day_off_message"))
                                    .foregroundColor(.red)
                                    .font(.subheadline)

                            } else if eventManager.events(for: date).isEmpty {
                                Text(String(localized: "no_events_today"))
                                    .foregroundColor(.secondary)
                                    .padding(.vertical, 12)

                            } else {
                                // ⭐ Thay List bằng VStack để không lỗi ScrollView
                                VStack(spacing: 10) {
                                    ForEach(eventManager.events(for: date).sorted { $0.startTime < $1.startTime }) { event in

                                        HStack(alignment: .top, spacing: 8) {

                                            // màu
                                            Circle()
                                                .fill(Color(hex: event.colorHex.isEmpty ? "#FF0000" : event.colorHex))
                                                .frame(width: 12, height: 12)

                                            VStack(alignment: .leading, spacing: 4) {

                                                // ⭐ 1. Tiêu đề
                                                Text(event.title)
                                                    .font(.headline)

                                                // ⭐ 2. origin label (y như Tab1)
                                                Text(originLabel(for: event))
                                                    .font(.caption)
                                                    .foregroundColor(.blue)

                                                // ⭐ 3. Người tạo
                                                // 🔵 Hiển thị tên người dùng thay cho UID
                                                if event.origin == .iCreatedForOther {
                                                    HStack(spacing: 4) {
                                                        UserNameView(uid: event.createdBy)   // A
                                                        Text("→")
                                                        UserNameView(uid: event.owner)       // B  <<<< CHỈNH ĐÚNG CHỖ NÀY
                                                    }
                                                    .font(.subheadline)
                                                    .foregroundColor(.secondary)
                                                } else {
                                                    UserNameView(uid: event.createdBy)
                                                        .font(.subheadline)
                                                        .foregroundColor(.secondary)
                                                }



                                                // ⭐ 4. Time
                                                Text("\(formattedTime(event.startTime)) - \(formattedTime(event.endTime))")
                                                    .font(.caption)
                                                    .foregroundColor(.secondary)
                                            }

                                            Spacer()

                                            // ⭐ Nút xoá giống list upcoming
                                            Button {
                                                showDeleteConfirmation(for: event)
                                            } label: {
                                                Image(systemName: "trash")
                                                    .foregroundColor(.red)
                                                    .padding(8)
                                            }
                                            .buttonStyle(.plain)
                                        }

                                        .padding(.vertical, 4)
                                        .padding(.horizontal, 8)
                                        .background(Color(.secondarySystemGroupedBackground))
                                        .cornerRadius(10)
                                    }
                                }

                            }
                        }
                    } else {
                        Text(String(localized: "select_day_to_view"))
                            .foregroundColor(.secondary)
                            .padding(.vertical, 12)
                    }

                    Spacer(minLength: 40)
                }
            }
            .navigationTitle(String(localized: "my_calendar"))
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { showAddSheet = true } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showAddSheet) {
                AddEventView(prefillDate: selectedDate, offDays: offDays)
                    .environmentObject(eventManager)
            }
            .alert(String(localized: "delete_event_title"), isPresented: $showDeleteAlert) {
                Button(String(localized: "cancel"), role: .destructive) {
                    if let event = eventToDelete {
                        eventManager.deleteEvent(event)
                    }
                    eventToDelete = nil
                }
                Button("Huỷ", role: .cancel) {
                    eventToDelete = nil
                }
            } message: {
                let prefix = String(localized: "delete_event_prefix")
                let title = eventToDelete?.title ?? ""

                Text("\(prefix) “\(title)”?")

            }
            .onAppear { loadOffDaysFromLocal() }
        }
    }

    // MARK: - SUPPORT
    private func toggleOffDay(for date: Date) {
        let key = calendar.startOfDay(for: date)
        if offDays.contains(key) {
            offDays.remove(key)
        } else {
            offDays.insert(key)
        }
    }

    private func isOffDay(_ date: Date) -> Bool {
        offDays.contains(calendar.startOfDay(for: date))
    }

    func formattedTime(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }

}


struct ActivityView: UIViewControllerRepresentable {
    let activityItems: [Any]
    let applicationActivities: [UIActivity]? = nil
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: applicationActivities)
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}


struct AddEventView: View {
    
    @EnvironmentObject var eventManager: EventManager
    @Environment(\.dismiss) private var dismiss
    @State private var selectedColor: Color = .blue // ✅ màu mặc định
    // Pre-fill date if user selected a date in calendar
    let prefillDate: Date?
    let offDays: Set<Date>        // ✅ THÊM MỚI — danh sách ngày nghỉ truyền từ ngoài vào
    @State private var selectedDate: Date = Date()
    @State private var selectedSlot: TimeSlot?
    @State private var title: String = ""
    @State private var date: Date = Date()
    @State private var startTime: Date = Date()
    @State private var endTime: Date = Date().addingTimeInterval(1800) // default +1h
    // ✅ THÊM MỚI — biến trạng thái popup
    @State private var showOffDayAlert = false
    @State private var offDayMessage = ""
    @AppStorage("isPremiumUser") private var isPremiumUser: Bool = false
    @State private var alertMessage: String = ""
    @State private var showAlert: Bool = false
    @EnvironmentObject var session: SessionStore
    @State private var dragStartHour: Int? = nil
    @State private var dragCurrentHour: Int? = nil
    @State private var showBusyInfo = false
    @State private var busyInfoEvent: CalendarEvent? = nil
    
    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text(String(localized: "info_section"))) {
                    TextField(String(localized: "title_placeholder"), text: $title)
                }

                Section(header: Text(String(localized: "date_time_section"))) {
                    DatePicker(
                        String(localized: "date_label"),
                        selection: $date,
                        displayedComponents: .date
                    )

                    Section(String(localized: "select_time_section")) {
                        let hours = Array(0..<24)
                        let eventsToday = eventManager.events(for: date)

                        // Kiểm tra ngày nghỉ
                        let isOffDay = offDays.contains {
                            Calendar.current.isDate($0, inSameDayAs: date)
                        }


                        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 10) {

                            ForEach(hours, id: \.self) { hour in

                                let slotStart = Calendar.current.date(bySettingHour: hour, minute: 0, second: 0, of: date)!
                                let slotEnd   = slotStart.addingTimeInterval(3600)

                                // Check giờ bận
                                let busyEvent = eventsToday.first {
                                    $0.startTime < slotEnd && $0.endTime > slotStart
                                }
                                let isBusy = (busyEvent != nil) || isOffDay

                                // Check giờ được chọn
                                let selectedHour = Calendar.current.component(.hour, from: startTime)
                                let isSelected = (hour == selectedHour) && !isBusy

                                // Màu nền
                                let bgColor: Color = {
                                    if isBusy { return .red.opacity(0.75) }
                                    if isSelected { return .blue.opacity(0.7) }
                                    return .gray.opacity(0.15)
                                }()

                                Text(String(format: "%02d:00", hour))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 10)
                                    .background(bgColor)
                                    .foregroundColor(isBusy ? .white : .primary)
                                    .cornerRadius(8)
                                    .contentShape(Rectangle())

                                    // TAP để chọn giờ
                                    .onTapGesture {
                                        if !isBusy {
                                            startTime = slotStart
                                            endTime = slotStart.addingTimeInterval(1800) // mặc định 30p
                                        }
                                    }

                                    // LONG PRESS để xem giờ bận
                                    .onLongPressGesture(minimumDuration: 0.4) {
                                        if let ev = busyEvent {
                                            busyInfoEvent = ev
                                            showBusyInfo = true
                                        }
                                    }
                            }
                        }
                        .padding(.vertical, 6)
                    }

                    DatePicker( String(localized: "start_label"), selection: $startTime, displayedComponents: .hourAndMinute)
                    DatePicker( String(localized: "end_label"), selection: $endTime, displayedComponents: .hourAndMinute)
                }
                Section(header: Text(String(localized: "event_color_section"))) {
 
                    ColorPicker(String(localized: "pick_color"), selection: $selectedColor, supportsOpacity: false)
                }
               

            }
            .onAppear {
                if let d = prefillDate {
                    date = d
                    selectedDate = d                  // <- QUAN TRỌNG: đồng bộ
                    // set startTime/endTime to that day same hour as current
                    let comps = Calendar.current.dateComponents([.year, .month, .day], from: d)
                    if let dayStart = Calendar.current.date(from: comps) {
                        // keep times (only change date portion)
                        startTime = combine(date: dayStart, time: startTime)
                        endTime = combine(date: dayStart, time: endTime)
                    }
                }
            }

            .navigationTitle(String(localized: "add_event_title"))

            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "save")) {

                        let calendar = Calendar.current
                        let now = Date()

                        // 1️⃣ Kiểm tra ngày nghỉ
                        if offDays.contains(where: { calendar.isDate($0, inSameDayAs: date) }) {
                            let prefix = String(localized: "off_day_prefix")   // "Ngày"
                            offDayMessage = "\(prefix) \(formattedDate(date)) là ngày nghỉ, bạn không thể đặt lịch vào ngày này."
                            showOffDayAlert = true
                            return
                        }

                        // 2️⃣ PREMIUM CHECK — GIỚI HẠN NGÀY
                        if !isPremiumUser {
                            if let maxDate = calendar.date(byAdding: .day, value: 7, to: now),
                               date > maxDate {
                                alertMessage = String(localized: "limit_7_days")
                                showAlert = true
                                return
                            }

                            // 3️⃣ PREMIUM CHECK — GIỚI HẠN SỐ LỊCH / NGÀY
                            let sameDayEvents = eventManager.events.filter {
                                calendar.isDate($0.date, inSameDayAs: date)
                            }
                            if sameDayEvents.count >= 2 {
                                alertMessage = String(localized: "limit_2_events_per_day")
                                showAlert = true
                                return
                            }
                        }

                        // 4️⃣ Validate form
                        guard !title.trimmingCharacters(in: .whitespaces).isEmpty else {
                            alertMessage = String(localized: "empty_title")
                            showAlert = true
                            return
                        }

                        // 5️⃣ Đảm bảo start < end
                        let s = combine(date: date, time: startTime)
                        var e = combine(date: date, time: endTime)
                        if e <= s { e = s.addingTimeInterval(1800) } // auto +30p

                        // 6️⃣ Tạo event
                        let success = eventManager.addEvent(
                            title: title,
                            ownerName: session.currentUserName,
                            date: date,
                            startTime: s,
                            endTime: e,
                            colorHex: selectedColor.toHex() ?? "#007AFF"
                        )



                        if !success {
                           
                            return            // ❗ Quan trọng: KHÔNG ĐÓNG VIEW
                        }

                        dismiss()

                    }

                }
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "cancel")) { dismiss() }
                }
            }
            // ✅ THÊM MỚI — popup cảnh báo
            // OFFDAY popup
            .alert(String(localized: "cannot_book"), isPresented: $showOffDayAlert) {
                Button(String(localized: "close"), role: .cancel) { }
            } message: {
                Text(offDayMessage)
            }

            // PREMIUM popup
            .alert(alertMessage, isPresented: $showAlert) {
                Button("OK", role: .cancel) {}
            }
        }
    }
    
    // Helper: combine date portion of `date` with time portion of `time`
    private func combine(date: Date, time: Date) -> Date {
        let cal = Calendar.current
        let dComp = cal.dateComponents([.year, .month, .day], from: date)
        let tComp = cal.dateComponents([.hour, .minute, .second], from: time)
        var comps = DateComponents()
        comps.year = dComp.year
        comps.month = dComp.month
        comps.day = dComp.day
        comps.hour = tComp.hour
        comps.minute = tComp.minute
        comps.second = tComp.second ?? 0
        return cal.date(from: comps) ?? date
    }
  
    func formattedTime(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }


    // ✅ THÊM MỚI — định dạng ngày hiển thị trong popup
    private func formattedDate(_ date: Date) -> String {
        date.formatted(.dateTime.day().month().year())
    }

    
}



struct CalendarGridView: View {
    @Binding var selectedDate: Date?
    let eventsByDay: [Date: [CalendarEvent]]
    @EnvironmentObject var eventManager: EventManager

    private let calendar = Calendar.current
    private let columns = Array(repeating: GridItem(.flexible()), count: 7)
    let offDays: Set<Date>
    let isOwner: Bool
    // Alert trạng thái chung, riêng cho CalendarGridView
    @State private var showOffDayAlert = false
    
    var body: some View {
        VStack(spacing: 8) {
            // MARK: - Header tháng
            HStack {
                Button(action: { changeMonth(by: -1) }) {
                    Image(systemName: "chevron.left")
                }
                Spacer()
                Text(formattedMonth(currentMonth))
                    .font(.headline)
                Spacer()
                Button(action: { changeMonth(by: 1) }) {
                    Image(systemName: "chevron.right")
                }
            }
            .padding(.horizontal)
            
            // MARK: - Tên thứ trong tuần
            HStack {
                let symbols = Array(calendar.veryShortStandaloneWeekdaySymbols[1...6]) + [calendar.veryShortStandaloneWeekdaySymbols[0]]
                ForEach(symbols, id: \.self) { symbol in
                    Text(symbol)
                        .font(.caption)
                        .frame(maxWidth: .infinity)
                        .foregroundColor(.secondary)
                }
            }
            
            // MARK: - Lưới ngày
            LazyVGrid(columns: columns, spacing: 12) {
                let allDays = daysInMonth(for: currentMonth)
                    .map { calendar.startOfDay(for: $0) }

                if let firstDay = allDays.first {
                    let weekday = calendar.component(.weekday, from: firstDay)
                    let emptySlots = weekday - calendar.firstWeekday
                    if emptySlots > 0 {
                        ForEach(0..<emptySlots, id: \.self) { idx in
                            Text("")
                                .id("empty_\(currentMonth)_\(idx)") // ép ID duy nhất
                        }
                    }
                }
                
                // Hiển thị các ngày trong tháng
                ForEach(allDays.indices, id: \.self) { index in
                    let date = allDays[index]

                    let day = calendar.component(.day, from: date)
                    let isSelected = selectedDate.map { calendar.isDate($0, inSameDayAs: date) } ?? false
                    let isToday = calendar.isDateInToday(date)
                    let isOffDay = offDays.contains(where: { calendar.isDate($0, inSameDayAs: date) })

                    VStack(spacing: 4) {
                        Text("\(day)")
                            .font(.body)
                            .frame(width: 36, height: 36)
                            .background(
                                Circle().fill(
                                    isSelected ? Color.accentColor :
                                        (isOffDay ? Color.gray.opacity(0.4) :
                                            (isToday ? Color.green.opacity(0.3) : Color.clear)
                                        )
                                )
                            )
                            .foregroundColor(isSelected ? .white : .primary)

                        let key = calendar.startOfDay(for: date)
                        let events = eventsByDay[key] ?? []

                        VStack(spacing: 2) {
                            // Dot màu theo sự kiện đầu tiên
                            Circle()
                                .frame(width: 6, height: 6)
                                .foregroundColor(events.isEmpty ? .clear : Color(hex: events.first!.colorHex))

                            // Số lượng sự kiện
                            if events.count > 1 {
                                Text("\(events.count)")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }


                    }
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        let key = calendar.startOfDay(for: date)

                        if !isOwner, offDays.contains(key) {
                            showOffDayAlert = true
                        } else {
                            selectedDate = date
                        }

                    }

                }

            }
            .padding(.horizontal)
        }
        // ✅ Alert riêng cho CalendarGridView (ngày nghỉ)
        .alert(String(localized: "cannot_book"), isPresented: $showOffDayAlert) {
            Button(String(localized: "close"), role: .cancel) {}
        } message: {
            Text(String(localized: "day_off_message_full"))
        }
    }
    
    // MARK: - Month navigation
    @State private var currentMonth: Date = Date()
    private func changeMonth(by value: Int) {
        if let newMonth = calendar.date(byAdding: .month, value: value, to: currentMonth) {
            currentMonth = newMonth
        }
    }
    
    // MARK: - Ngày trong tháng
    private func daysInMonth(for date: Date) -> [Date] {
        guard let monthInterval = calendar.dateInterval(of: .month, for: date) else { return [] }
        var days: [Date] = []
        var current = monthInterval.start
        while current < monthInterval.end {
            days.append(current)
            current = calendar.date(byAdding: .day, value: 1, to: current)!
        }
        return days
    }
    
    // MARK: - Định dạng tháng
    private func formattedMonth(_ date: Date) -> String {
        date.formatted(.dateTime.month(.wide).year())
    }

}


struct DayEventsSheetView: View {
    @EnvironmentObject var eventManager: EventManager
    let date: Date
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            List(eventManager.events(for: date)) { event in
                VStack(alignment: .leading, spacing: 4) {
                    
                    // ⭐ Tiêu đề sự kiện
                    Text(event.title)
                        .font(.headline)
                    
                    // ⭐ Thêm hiển thị tên người tạo / người được tạo
                    if event.origin == .iCreatedForOther {
                        // A tạo cho B
                        HStack(spacing: 4) {
                            UserNameView(uid: event.createdBy)   // A
                            Text("→")
                            UserNameView(uid: event.owner)       // B
                        }
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        
                    } else {
                        // Tự tạo hoặc người khác tạo cho tôi
                        UserNameView(uid: event.createdBy)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    
                    // ⭐ Thời gian sự kiện
                    Text("\(formattedTime(event.startTime)) - \(formattedTime(event.endTime))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 4)
            }
            .navigationTitle("\(String(localized: "day_prefix")) \(formattedDate(date))")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(String(localized: "close")) { dismiss() }
                }
            }
        }
    }
    
    func formattedTime(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }


    private func formattedDate(_ date: Date) -> String {
        date.formatted(.dateTime.day().month().year())
    }

}

