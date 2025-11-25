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
}

struct CalendarEvent: Identifiable, Hashable, Codable {
    var id: String = UUID().uuidString
    var title: String
    var owner: String
    var date: Date
    var startTime: Date
    var endTime: Date
    var colorHex: String = "#007AFF"
    var pendingDelete: Bool = false

    // ⭐ THÊM DÒNG NÀY
    var origin: EventOrigin = .myEvent
}



final class EventManager: ObservableObject {
    static let shared = EventManager()
    @EnvironmentObject var session: SessionStore

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

    private let db = Firestore.firestore()

    // MARK: - INIT
    private init() {
        loadEvents()
        loadSharedLinks()
        cleanUpPastEvents()
        updateGroupedEvents()
        listenToEvents()
        retryPendingDeletes()
        syncBusySlotsToFirebase()
        if let uid = currentUserId {
            listenToMyCreatedAppointments(createdBy: uid)
        }

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

    private func saveSharedLinks() {
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

    // MARK: - PAST EVENTS CLEAN
    func cleanUpPastEvents() {
        isProcessing = true    // ⭐ lock

        let now = Date()
        var upcoming: [CalendarEvent] = []
        var expired: [CalendarEvent] = []

        for e in events {
            if e.endTime < now { expired.append(e) }
            else { upcoming.append(e) }
        }

        self.events = upcoming
        self.pastEvents.append(contentsOf: expired)

        isProcessing = false   // ⭐ unlock
        saveEvents()
        updateGroupedEvents()
    }


    // MARK: - OFF DAYS
    func fetchOffDays(for userId: String, completion: @escaping (Set<Date>) -> Void) {
        db.collection("publicCalendar")
            .document(userId)
            .getDocument { snap, error in
                guard let data = snap?.data() else {
                    completion([])
                    return
                }

                let timestamps = data["offDays"] as? [Double] ?? []
                let dates = timestamps.map { Date(timeIntervalSince1970: $0) }
                completion(Set(dates))
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
    
        // ❗ CHỐNG TRÙNG GIỜ (tuỳ theo toggle)
        if !allowDuplicateEvents {
            let overlap = events.contains { ev in
                Calendar.current.isDate(ev.date, inSameDayAs: date) &&
                ev.startTime < endTime &&
                startTime < ev.endTime
            }

            if overlap {

                    self.alertMessage = "Khung giờ này đã có lịch rồi!"
                    self.showAlert = true
               
                return false
            }
        }
        
        let isPremium = PremiumManager.shared.isPremiumUser

        // FREE USER LIMITS
        if !isPremium {

            // ❌ 1) hạn 7 ngày
            let now = Date()
            if let maxDate = Calendar.current.date(byAdding: .day, value: 7, to: now),
               date > maxDate {
                print("🚫 FREE USER: Không được tạo lịch quá 7 ngày")
                return false
            }

            // ❌ 2) max 4 events / day
            let eventsSameDay = events.filter { Calendar.current.isDate($0.date, inSameDayAs: date) }
            if eventsSameDay.count >= 4 {
                print("🚫 FREE USER: Quá 4 lịch/ngày")
                return false
            }
        }
       
        // ❗ CHỐNG TRÙNG GIỜ (tuỳ theo toggle)
     


        // PASSES → TẠO LỊCH
        let newEvent = CalendarEvent(
            id: UUID().uuidString,
            title: title,
            owner: ownerName,        // ⭐ Tự động gán tên user
            date: date,
            startTime: startTime,
            endTime: endTime,
            colorHex: colorHex,
            pendingDelete: false
        )


        // Local
        DispatchQueue.main.async {
            self.events.append(newEvent)
            self.saveEvents()
        }

        // Remote
        _ = currentUserId ?? ""
        let data: [String: Any] = [
            "title": newEvent.title,
            "owner": ownerName,
            "sharedUser": currentUserId ?? "",
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
            if let docId = ref?.documentID {
                DispatchQueue.main.async {
                    if let i = self.events.firstIndex(where: { $0.id == newEvent.id }) {
                        self.events[i].id = docId
                    }
                }
                self.syncBusySlotsToFirebase()
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

        // Update Firestore (không đụng owner/sharedUser)
        if !event.id.isEmpty {
            db.collection("events").document(event.id).updateData([
                "title": newTitle,
                "date": Timestamp(date: newDate),
                "startTime": Timestamp(date: newStart),
                "endTime": Timestamp(date: newEnd),
                "colorHex": newColorHex
            ])
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
        removeBusySlotFromPublicCalendar(event: event)

        // 5️⃣ Sync busySlots mới
        syncBusySlotsToFirebase()
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
                        completion: @escaping ([CalendarEvent], Bool) -> Void) {

        fetchPremiumStatus(for: userId) { isPremium in

            self.db.collection("publicCalendar").document(userId)
                .getDocument { snapshot, error in

                    guard let data = snapshot?.data(), error == nil else {
                        completion([], isPremium)
                        return
                    }

                    // ưu tiên publicCalendar nếu có
                    let premiumFlag = data["isPremium"] as? Bool ?? isPremium

                    let rawSlots = data["busySlots"] as? [[String: Any]] ?? []

                    let slots = rawSlots.compactMap { dict -> CalendarEvent? in
                        guard let start = dict["start"] as? TimeInterval,
                              let end = dict["end"] as? TimeInterval else { return nil }

                        
                        return CalendarEvent(
                            id: dict["id"] as? String ?? UUID().uuidString,
                            title: dict["title"] as? String ?? "Bận",
                            owner: userId,
                            date: Date(timeIntervalSince1970: start),
                            startTime: Date(timeIntervalSince1970: start),
                            endTime: Date(timeIntervalSince1970: end)
                        )
                    }

                    completion(slots, premiumFlag)
                }
        }
    }





    // MARK: - Remove busy slot
    private func removeBusySlotFromPublicCalendar(event: CalendarEvent) {
        guard let uid = currentUserId else { return }

        let doc = db.collection("publicCalendar").document(uid)
        doc.getDocument { snap, err in
            guard let data = snap?.data() else { return }

            var slots = data["busySlots"] as? [[String: Any]] ?? []

            slots.removeAll {
                ($0["id"] as? String) == event.id
            }

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
        
        // 1️⃣ Kiểm tra trùng giờ
        fetchBusySlots(for: sharedUserId) { busySlots, ownerIsPremium in
            let overlap = busySlots.contains { $0.startTime < end && $0.endTime > start }
            if overlap {
                DispatchQueue.main.async { self.isAdding = false }
                completion(false, "Giờ này đã bận!")
                return
            }

            // ⭐ PREMIUM CHECK – đúng chân lý
            if !ownerIsPremium {
                let now = Date()
                if let maxDate = Calendar.current.date(byAdding: .day, value: 7, to: now),
                   start > maxDate {

                    DispatchQueue.main.async { self.isAdding = false }
                    completion(false,
                               "Chủ lịch chưa Premium — bạn chỉ được đặt lịch trong 7 ngày tới.")
                    return
                }
            }


            // 2️⃣ Kiểm tra đăng nhập
            guard let uid = Auth.auth().currentUser?.uid else {
                DispatchQueue.main.async { self.isAdding = false }
                completion(false, "Bạn cần đăng nhập.")
                return
            }
            
            // 3️⃣ Dữ liệu appointment
            let appointmentData: [String: Any] = [
                "owner": sharedUserId,     // CHỦ lịch A
                "sharedUser": uid,         // KHÁCH B
                "title": title,
                "start": start.timeIntervalSince1970,
                "end": end.timeIntervalSince1970
            ]
            
            // 4️⃣ Ghi vào APPOINTMENTS
            self.db.collection("appointments").addDocument(data: appointmentData) { error in
                
                if let error = error {
                    DispatchQueue.main.async { self.isAdding = false }
                    completion(false, "Lỗi tạo lịch: \(error.localizedDescription)")
                    return
                }
                
                // 5️⃣ Ghi vào EVENTS để chủ lịch A có thể XOÁ
                let eventData: [String: Any] = [
                    "title": title,
                    "owner": sharedUserId,            // A
                    "sharedUser": uid,                // B
                    "createdBy": createdBy, 
                    "date": Timestamp(date: start),
                    "startTime": Timestamp(date: start),
                    "endTime": Timestamp(date: end),
                    "colorHex": "#007AFF"
                ]
                
                self.db.collection("events").addDocument(data: eventData) { err in
                    DispatchQueue.main.async { self.isAdding = false }
                    
                    if let err = err {
                        completion(false, "Tạo event thất bại: \(err.localizedDescription)")
                    } else {
                        completion(true, nil)
                    }
                }
            }
        }
    }

    func listenToEvents() {
        guard let uid = currentUserId else { return }

        db.collection("events")
            .whereField("owner", isEqualTo: uid)
            .addSnapshotListener { snap, err in
                guard let docs = snap?.documents else { return }

                let cloudEvents = docs.compactMap { CalendarEvent.from($0) }

                DispatchQueue.main.async {

                    // 1️⃣ Bỏ qua event đã pendingDelete
                    let filtered = cloudEvents.filter { cloudEv in
                        !self.events.contains(where: { $0.pendingDelete && $0.id == cloudEv.id })
                    }

                    // 2️⃣ Tạo bản copy local
                    var merged = self.events

                    for ev in filtered {
                        if let idx = merged.firstIndex(where: { $0.id == ev.id }) {
                            // 3️⃣ Update event đã tồn tại
                            merged[idx] = ev
                        } else {
                            // 4️⃣ Thêm mới nếu chưa có
                            merged.append(ev)
                        }
                    }

                    // 5️⃣ Cập nhật lại danh sách
                    self.events = merged
                    self.saveEvents()
                    self.updateGroupedEvents()
                }
            }
    }

    func listenToMyCreatedAppointments(createdBy uid: String) {
        db.collection("appointments")
            .whereField("createdBy", isEqualTo: uid)
            .addSnapshotListener { snap, err in
                guard let docs = snap?.documents else { return }

                let incoming = docs.compactMap { CalendarEvent.from($0) }

                DispatchQueue.main.async {
                    for ev in incoming {
                        // Không override local pending delete
                        if let exist = self.events.first(where: { $0.id == ev.id }),
                           exist.pendingDelete { continue }

                        if let idx = self.events.firstIndex(where: { $0.id == ev.id }) {
                            self.events[idx] = ev
                        } else {
                            self.events.append(ev)
                        }
                    }

                    self.saveEvents()
                    self.updateGroupedEvents()
                }
            }
    }

    // MARK: - Listeners (prevent revival)
    func listenToAppointments(forSharedUser sharedUserId: String) {
        db.collection("appointments")
            .whereField("sharedUser", isEqualTo: sharedUserId)
            .addSnapshotListener { snap, err in
                guard let docs = snap?.documents else { return }

                let arrivals = docs.compactMap { doc -> CalendarEvent? in
                    let data = doc.data()
                    guard let start = data["start"] as? TimeInterval,
                          let end = data["end"] as? TimeInterval else { return nil }
                    return CalendarEvent(
                        id: doc.documentID,
                        title: data["title"] as? String ?? "Lịch web",
                        owner: data["owner"] as? String ?? "khách",
                        date: Date(timeIntervalSince1970: start),
                        startTime: Date(timeIntervalSince1970: start),
                        endTime: Date(timeIntervalSince1970: end)
                    )
                }

                DispatchQueue.main.async {
                    for ev in arrivals {
                        if let exist = self.events.first(where: { $0.id == ev.id }),
                           exist.pendingDelete {
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

    func listenToBusySlots(sharedUserId: String) {
        db.collection("publicCalendar").document(sharedUserId)
            .addSnapshotListener { snap, err in
                guard let data = snap?.data() else { return }

                let raw = data["busySlots"] as? [[String: Any]] ?? []

                let slots = raw.compactMap { dict -> CalendarEvent? in
                    guard let start = dict["start"] as? TimeInterval,
                          let end = dict["end"] as? TimeInterval else { return nil }
                    let id = dict["id"] as? String ?? "\(start)-\(end)-local"
                    let owner = dict["owner"] as? String ?? sharedUserId
                    return CalendarEvent(
                        id: id,
                        title: dict["title"] as? String ?? "Bận",
                        owner: owner,
                        date: Date(timeIntervalSince1970: start),
                        startTime: Date(timeIntervalSince1970: start),
                        endTime: Date(timeIntervalSince1970: end)
                    )
                }

                DispatchQueue.main.async {
                    for ev in slots {
                        if let exist = self.events.first(where: { $0.id == ev.id }),
                           exist.pendingDelete {
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

    // MARK: Sync busySlots
    func syncBusySlotsToFirebase() {
        guard let uid = currentUserId else { return }

        let slots = events.filter { !$0.pendingDelete }.map { e in
            [
                "id": e.id,
                "title": e.title,
                "owner": e.owner,
                "start": e.startTime.timeIntervalSince1970,
                "end": e.endTime.timeIntervalSince1970
            ]
        }

        let premium = PremiumManager.shared.isPremiumUser

        db.collection("publicCalendar").document(uid)
            .setData([
                "busySlots": slots,
                "isPremium": premium
            ], merge: true)
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

    @StateObject private var languageManager = LanguageManager.shared
    
    @State private var showPastEvents = false
    @AppStorage("isPremiumUser") private var isPremiumUser: Bool = false
    
    var body: some View {
        
        TabView {
            
            NavigationStack {
                EventListView(showPastEvents: $showPastEvents)
            }
            .tabItem {
                Label("Danh sách sự kiện", systemImage: "list.bullet.rectangle")
            }
            
            NavigationStack {
                CustomizableCalendarView()
            }
            .tabItem {
                Label("Lịch của tôi", systemImage: "calendar")
            }
            
            NavigationStack {
                PartnerCalendarTabView()
            }
            .tabItem {
                Label("Đối tác", systemImage: "person.2.fill")
            }
            
            NavigationStack {
                SettingsView()
            }
            .tabItem {
                Label("Cài đặt", systemImage: "gearshape")
            }
        }
        .environmentObject(languageManager)
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
                Text("Lịch hiện tại").tag(false)
                Text("Lịch đã qua").tag(true)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            
            // Ô tìm kiếm chỉ hiện khi xem "lịch đã qua"
            if showPastEvents {
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.gray)
                    TextField("Tìm theo tên hoặc người tạo...", text: $searchText)
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
        .navigationTitle(showPastEvents ? "Lịch đã qua" : "Lịch hiện tại")
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

        .alert("Xoá sự kiện này?", isPresented: $showDeleteAlert) {
            Button("Xoá", role: .destructive) {
                if let event = eventToDelete {
                    eventManager.deleteEvent(event)
                }
                eventToDelete = nil
            }
            Button("Huỷ", role: .cancel) {
                eventToDelete = nil
            }
        } message: {
            Text("Bạn có chắc muốn xoá sự kiện “\(eventToDelete?.title ?? "")”?")
        }
    }
    private func formattedMonth(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "vi_VN")
        f.dateFormat = "MMMM yyyy" // ví dụ: "Tháng 11 2025"
        return f.string(from: date).capitalized
    }
    
    // MARK: - Lịch hiện tại
    // MARK: - Lịch hiện tại (gộp theo Tháng → Tuần → Ngày)
    // MARK: - Lịch hiện tại (TỐI ƯU HIỆU NĂNG)
    private var upcomingEventsList: some View {
        // ✅ 1. Tạo formatter dùng chung (không tạo mới mỗi lần)
        let monthFormatter: DateFormatter = {
            let f = DateFormatter()
            f.locale = Locale(identifier: "vi_VN")
            f.dateFormat = "MMMM yyyy"
            return f
        }()
        
        let dateFormatter: DateFormatter = {
            let f = DateFormatter()
            f.locale = Locale(identifier: "vi_VN")
            f.dateStyle = .medium
            return f
        }()
        
        let timeFormatter: DateFormatter = {
            let f = DateFormatter()
            f.locale = Locale(identifier: "vi_VN")
            f.timeStyle = .short
            return f
        }()
        
        // ✅ 2. Tính trước dữ liệu nhóm, tránh lặp trong body
        // Thực hiện 1 lần khi body chạy (SwiftUI sẽ diff tự động)
        let groupedByMonth = rememberGroupedByMonth(events: eventManager.events)
        let sortedMonths = groupedByMonth.keys.sorted()
        
        return List {
            if eventManager.events.isEmpty {
                Text("Chưa có lịch nào sắp tới.")
                    .foregroundColor(.secondary)
            } else {
                // ✅ 3. Vòng lặp hiển thị tháng
                ForEach(sortedMonths, id: \.self) { monthDate in
                    let monthEvents = groupedByMonth[monthDate] ?? []
                    Section(header:
                                HStack {
                        Text(monthFormatter.string(from: monthDate).capitalized)
                            .font(.headline)
                        Spacer()
                        Text("\(monthEvents.count) lịch")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    ) {
                        // ✅ 4. Gom theo tuần
                        let groupedByWeek = rememberGroupedByWeek(events: monthEvents)
                        let sortedWeeks = groupedByWeek.keys.sorted()
                        
                        ForEach(sortedWeeks, id: \.self) { week in
                            let weekEvents = groupedByWeek[week] ?? []
                            Section(header:
                                        Text("Tuần \(week)")
                                .font(.subheadline.bold())
                                .foregroundColor(.secondary)
                            ) {
                                // ✅ 5. Gom theo ngày
                                let groupedByDay = rememberGroupedByDay(events: weekEvents)
                                let sortedDays = groupedByDay.keys.sorted()
                                
                                ForEach(sortedDays, id: \.self) { day in
                                    let dayEvents = groupedByDay[day] ?? []
                                    Section(header:
                                                Text(dateFormatter.string(from: day))
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

                                                    Text(event.owner)
                                                        .font(.subheadline)
                                                        .foregroundColor(.secondary)

                                                    Text("\(timeFormatter.string(from: event.startTime)) - \(timeFormatter.string(from: event.endTime))")
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
                                                    Label("Xoá", systemImage: "trash")
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
                Text(searchText.isEmpty ? "Chưa có lịch nào đã qua." : "Không tìm thấy kết quả phù hợp.")
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
                        Text("\(monthEvents.count) lịch")
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
                                    Text("Tuần \(week)")
                                        .font(.body)
                                    Spacer()
                                    Text("\(weekEvents.count) lịch")
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
    struct PastEventsByDateView: View {
        @EnvironmentObject var eventManager: EventManager
        let date: Date
        @Environment(\.dismiss) private var dismiss
        
        var body: some View {
            NavigationStack {
                List {
                    ForEach(eventsForDate) { event in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(event.title).font(.headline)
                            Text(event.owner)
                                .font(.subheadline)
                                .foregroundColor(.secondary)

                            Text("\(formattedTime(event.startTime)) - \(formattedTime(event.endTime))")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                }
                .navigationTitle(formattedDate(date))
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Đóng") { dismiss() }
                    }
                }
            }
        }
        
        private var eventsForDate: [CalendarEvent] {
            eventManager.pastEvents.filter { Calendar.current.isDate($0.date, inSameDayAs: date) }
                .sorted { $0.startTime < $1.startTime }
        }
        
        private func formattedDate(_ date: Date) -> String {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "vi_VN")
            formatter.dateFormat = "'Ngày' d, 'tháng' M, yyyy"
            return formatter.string(from: date)
        }
        
        private func formattedTime(_ date: Date) -> String {
            let f = DateFormatter()
            f.locale = Locale(identifier: "vi_VN")
            f.timeStyle = .short
            return f.string(from: date)
        }
    }
    // MARK: - Hàng hiển thị sự kiện
    private func eventRow(_ event: CalendarEvent) -> some View {
        VStack(alignment: .leading) {
            Text(event.title).font(.headline)
            Text("\(event.owner) • \(formattedDate(event.date))")
                .font(.subheadline)
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
        let f = DateFormatter()
        f.locale = Locale(identifier: "vi_VN")
        f.dateStyle = .medium
        return f.string(from: date)
    }
    
    private func formattedTime(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "vi_VN")
        f.timeStyle = .short
        return f.string(from: date)
    }
}
private func originLabel(for event: CalendarEvent) -> String {
    switch event.origin {
    case .myEvent:
        return "📘 Lịch của tôi"
    case .createdForMe:
        return "🟢 Người khác tạo cho tôi"
    case .iCreatedForOther:
        return "🟠 Tôi tạo cho người khác"
    }
}

struct PastEventsByWeekView: View {
    @EnvironmentObject var eventManager: EventManager
    let week: (year: Int, week: Int)
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(eventsThisWeek) { event in
                    VStack(alignment: .leading) {
                        Text(event.title).font(.headline)
                        Text(formatted(event.startTime))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .navigationTitle("Tuần \(week.week) - \(week.year)")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Đóng") { dismiss() }
                }
            }
        }
    }

    private var eventsThisWeek: [CalendarEvent] {
        eventManager.pastEvents.filter {
            Calendar.current.component(.weekOfYear, from: $0.date) == week.week &&
            Calendar.current.component(.yearForWeekOfYear, from: $0.date) == week.year
        }
        .sorted(by: { $0.startTime < $1.startTime })
    }

    private func formatted(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "vi_VN")
        f.dateFormat = "HH:mm dd/MM/yyyy"
        return f.string(from: d)
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
    
    // ✅ thêm biến quản lý ngày nghỉ
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
        cal.firstWeekday = 2 // 2 = Monday bắt đầu tuần
        return cal
    }
    
    private func showDeleteConfirmation(for event: CalendarEvent) {
        eventToDelete = event
        showDeleteAlert = true
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                
                // MARK: - Calendar grid
        CalendarGridView(
        selectedDate: $selectedDate,
        eventsByDay: eventManager.groupedByDay,
        offDays: offDays,
        isOwner: true
    )
        .padding(.top, 8)
                
        // MARK: - Toggle cho phép trùng lịch
    Toggle("Cho phép trùng lịch", isOn: Binding(
        get: { eventManager.allowDuplicateEvents },
        set: { eventManager.allowDuplicateEvents = $0 }
    ))
        .padding(.horizontal)
        .padding(.bottom, 4)
                
        Divider()
                
                // MARK: - Nút chia sẻ
                Button {
                    eventManager.syncBusySlotsToFirebase() // cập nhật Firebase trước khi share
                    
                    // Lấy UID hiện tại từ Firebase Auth
                    if let uid = Auth.auth().currentUser?.uid {
                        // Tạo URL chia sẻ
                        if let url = URL(string: "https://easyschedule-ce98a.web.app/calendar/\(uid)") {
                            shareLink = url
                            showShareSheet = true
                            
                        } else {
                            print("❌ Tạo URL thất bại")
                        }
                    } else {
                        print("❌ Chưa đăng nhập, không thể tạo link")
                    }
                } label: {
                    HStack {
                        Image(systemName: "square.and.arrow.up")
                        Text("Chia sẻ lịch").bold()
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
                        // ✅ Nút đặt / huỷ ngày nghỉ
                Button {
                    toggleOffDay(for: date)
                    eventManager.syncOffDaysToFirebase(offDays: offDays)
                } label: {

            HStack {
                Image(systemName: isOffDay(date) ? "xmark.circle" :"bed.double.fill")
                Text(isOffDay(date) ? "Mở lại ngày này" : "Đặt ngày nghỉ")
                    .bold()
    }
                .frame(maxWidth: .infinity)
                .padding()
                .background(isOffDay(date) ? Color.green.opacity(0.2) : Color.gray.opacity(0.2))
                    .cornerRadius(10)
    }
                .padding(.horizontal)
                        
                if isOffDay(date) {
                Text("Ngày này đang được đặt là *ngày nghỉ*.")
                    .foregroundColor(.red)
                    .font(.subheadline)
                    } else if eventManager.events(for: date).isEmpty {
                        Text("Không có sự kiện nào trong ngày này.")
                        .foregroundColor(.secondary)
                        .padding(.vertical, 12)
                        } else {
                List {
                    ForEach(eventManager.events(for: date)) { event in
                    HStack(alignment: .top, spacing: 8) {
                        // Circle màu sự kiện
                        Circle()
                            .fill(Color(hex: event.colorHex.isEmpty ? "#FF0000" : event.colorHex))
                                .frame(width: 12, height: 12)
                                        
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                                Text(event.title)
                                .font(.headline)
                        Spacer()
                    Button {
                            showDeleteConfirmation(for: event)
                        } label: {
                            Image(systemName: "trash")
                                .foregroundColor(.red)
                                .padding(8)
      }                                .buttonStyle(.plain)
    }

                Text("\(formattedTime(event.startTime)) - \(formattedTime(event.endTime))")
                        .font(.caption)
                       .foregroundColor(.secondary)
    }
}
                        .padding(.vertical, 4)
}
                        .onDelete { indexSet in
                    for index in indexSet {
                 let event = eventManager.events(for: date)[index]
                                        eventManager.deleteEvent(event)
        }
    }
}
                .listStyle(.inset)
                .frame(maxHeight: 300)
        }
    }
        } else {
            Text("Chọn một ngày để xem sự kiện.")
                .foregroundColor(.secondary)
                .padding(.vertical, 12)
            }
            }
            .navigationTitle("Lịch của tôi")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showAddSheet = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Thêm lịch")
                }
            }
            .sheet(isPresented: $showAddSheet) {
                AddEventView(prefillDate: selectedDate, offDays: offDays)
                    .environmentObject(eventManager)
            }
            .alert("Xoá sự kiện này?", isPresented: $showDeleteAlert) {
                Button("Xoá", role: .destructive) {
                    if let event = eventToDelete {
                        eventManager.deleteEvent(event)
                    }
                    eventToDelete = nil
                }
                Button("Huỷ", role: .cancel) {
                    eventToDelete = nil
                }
            } message: {
                Text("Bạn có chắc muốn xoá sự kiện “\(eventToDelete?.title ?? "")”?")
            }
            .padding(.horizontal)
            .onAppear {
                loadOffDaysFromLocal()
            }

        }
    }
    
    // MARK: - Toggle ngày nghỉ
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
    
    
    // MARK: - Format giờ
    private func formattedTime(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "vi_VN")
        f.timeStyle = .short
        return f.string(from: date)
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
    @State private var owner: String = ""
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

    
    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("Thông tin")) {
                    TextField("Tiêu đề", text: $title)
                    TextField("Người tạo", text: $owner)
                }
                Section(header: Text("Ngày & giờ")) {
                    DatePicker("Ngày", selection: $date, displayedComponents: .date)
                    NavigationLink {
                        TimeSlotPickerGridView(selectedDate: date) { slot in
                            selectedSlot = slot
                            // quan trọng: gộp ngày đã chọn (date) với thời gian từ slot
                            startTime = combine(date: date, time: slot.startTime)
                            endTime   = combine(date: date, time: slot.endTime)
                        }
                    } label: {
                        HStack {
                            Image(systemName: "clock.fill")
                                .foregroundColor(.blue)
                            VStack(alignment: .leading) {
                                Text("Chọn khung giờ")
                                    .font(.headline)
                                if let slot = selectedSlot {
                                    Text("\(slot.startTime.formatted(date: .omitted, time: .shortened)) - \(slot.endTime.formatted(date: .omitted, time: .shortened))")
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                } else {
                                    Text("Chưa chọn")
                                        .font(.subheadline)
                                        .foregroundColor(.gray)
                                }
                            }
                        }
                    }
                    DatePicker("Bắt đầu", selection: $startTime, displayedComponents: .hourAndMinute)
                    DatePicker("Kết thúc", selection: $endTime, displayedComponents: .hourAndMinute)
                }
                Section(header: Text("Màu sự kiện")) {
                    ColorPicker("Chọn màu", selection: $selectedColor, supportsOpacity: false)
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

            .navigationTitle("Thêm lịch")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Lưu") {

                        let calendar = Calendar.current
                        let now = Date()

                        // 1️⃣ Kiểm tra ngày nghỉ
                        if offDays.contains(where: { calendar.isDate($0, inSameDayAs: date) }) {
                            offDayMessage = "Ngày \(formattedDate(date)) là ngày nghỉ, bạn không thể đặt lịch vào ngày này."
                            showOffDayAlert = true
                            return
                        }

                        // 2️⃣ PREMIUM CHECK — GIỚI HẠN NGÀY
                        if !isPremiumUser {
                            if let maxDate = calendar.date(byAdding: .day, value: 7, to: now),
                               date > maxDate {

                                alertMessage = "❗Bạn chỉ được tạo lịch trong vòng 7 ngày tới.Nâng cấp Premium để mở khoá không giới hạn."
                                showAlert = true
                                return
                            }

                            // 3️⃣ PREMIUM CHECK — GIỚI HẠN SỐ LỊCH / NGÀY
                            let sameDayEvents = eventManager.events.filter {
                                calendar.isDate($0.date, inSameDayAs: date)
                            }
                            if sameDayEvents.count >= 4 {
                                alertMessage = "🚫 Bạn chỉ được tạo tối đa 4 lịch / ngày.Nâng cấp Premium để tạo không giới hạn."
                                showAlert = true
                                return
                            }
                        }

                        // 4️⃣ Validate form
                        guard !title.trimmingCharacters(in: .whitespaces).isEmpty else {
                            alertMessage = "Tên sự kiện không được để trống."
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
                    Button("Huỷ") { dismiss() }
                }
            }
            // ✅ THÊM MỚI — popup cảnh báo
            // OFFDAY popup
            .alert("Không thể đặt lịch", isPresented: $showOffDayAlert) {
                Button("Đóng", role: .cancel) { }
            } message: {
                Text(offDayMessage)
            }

            // PREMIUM popup
            .alert(alertMessage, isPresented: $showAlert) {
                Button("OK", role: .cancel) {}
            }
            .alert(isPresented: $eventManager.showAlert) {
                Alert(title: Text("Không thể tạo lịch"),
                      message: Text(eventManager.alertMessage),
                      dismissButton: .default(Text("OK")))
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
    
    // ✅ THÊM MỚI — định dạng ngày hiển thị trong popup
    private func formattedDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "vi_VN")
        f.dateStyle = .medium
        return f.string(from: date)
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

                        Circle()
                            .frame(width: 6, height: 6)
                            .foregroundColor(
                                (eventsByDay[calendar.startOfDay(for: date)]?.isEmpty == false)
                                ? Color(hex: eventsByDay[calendar.startOfDay(for: date)]!.first!.colorHex)
                                : .clear
                            )

                    }
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        let key = calendar.startOfDay(for: date)

                        if isOwner {
                            // Chủ A → luôn được chọn ngày, dù là offDay
                            selectedDate = date
                        } else {
                            // Khách B → xem nhưng không thể chọn ngày nghỉ
                            if offDays.contains(key) {
                                showOffDayAlert = true
                            } else {
                                selectedDate = date
                            }
                        }
                    }

                }

            }
            .padding(.horizontal)
        }
        // ✅ Alert riêng cho CalendarGridView (ngày nghỉ)
        .alert("Không thể đặt lịch", isPresented: $showOffDayAlert) {
            Button("Đóng", role: .cancel) {}
        } message: {
            Text("Ngày này là ngày nghỉ, bạn không thể đặt lịch vào ngày này.")
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
        let f = DateFormatter()
        f.locale = Locale(identifier: "vi_VN")
        f.dateFormat = "LLLL yyyy"
        return f.string(from: date).capitalized
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
                    Text(event.title).font(.headline)
                    Text("\(formattedTime(event.startTime)) - \(formattedTime(event.endTime))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                .padding(.vertical, 4)
            }
            .navigationTitle("Ngày \(formattedDate(date))")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Đóng") { dismiss() }
                }
            }
        }
    }
    func formattedTime(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f.string(from: date)
    }

    private func formattedDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "vi_VN")
        f.dateStyle = .medium
        return f.string(from: date)
    }
}

import FirebaseStorage
import Firebase
struct AddOrEditEventView: View {
    enum Mode {
        case add
        case edit(CalendarEvent)
    }
    
    @State private var alertMessage = ""
    @State private var showAlert = false
    @State private var showLimitAlert = false
    @AppStorage("isPremiumUser") private var isPremiumUser: Bool = false
    @EnvironmentObject var eventManager: EventManager

    private func showAlertLimit(title: String, message: String) {
        alertMessage = message
        showLimitAlert = true
    }
    private func saveEventToFirestore(_ event: CalendarEvent) {
        let db = Firestore.firestore()

        let data: [String: Any] = [
            "title": event.title,
            "owner": event.owner,
            "date": Timestamp(date: event.date),
            "startTime": Timestamp(date: event.startTime),
            "endTime": Timestamp(date: event.endTime)
        ]
        
        db.collection("events").addDocument(data: data) { error in
            if let error = error {
                print("❌ Firestore add error:", error.localizedDescription)
            } else {
                print("✅ Firestore add success")
            }
        }
    }

    
    @Environment(\.dismiss) private var dismiss
    let mode: Mode
    var selectedDate: Date
    var allowOverlap: Bool
    @Binding var existingEvents: [CalendarEvent]
    
    @State private var title = ""
    @State private var owner = ""
    @State private var date = Date()
    @State private var startTime = Date()
    @State private var endTime = Date().addingTimeInterval(3600)
    struct AlertMessage: Identifiable {
        let id = UUID()
        let title: String
        let message: String
    }

    @State private var activeAlert: AlertMessage? = nil

    var body: some View {
        NavigationStack {
            Form {
                Section("Thông tin sự kiện") {
                    TextField("Tên sự kiện", text: $title)
                    TextField("Người tạo / tham gia", text: $owner)
                    DatePicker("Ngày", selection: $date, displayedComponents: .date)
                    DatePicker("Giờ bắt đầu", selection: $startTime, displayedComponents: .hourAndMinute)
                    DatePicker("Giờ kết thúc", selection: $endTime, displayedComponents: .hourAndMinute)
                }
                
                if case .edit(let event) = mode {
                    Section {
                        Button(role: .destructive) {
                            deleteEvent(event)
                        } label: {
                            Label("Xoá lịch này", systemImage: "trash")
                        }
                    }
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Huỷ") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Lưu") { handleSave() }
                }
            }
            // ✅ Alert chung cho mọi lỗi
            .alert(alertMessage, isPresented: $showAlert) {
                Button("OK", role: .cancel) {}
            }
            // ✅ Alert giới hạn premium
            .alert(alertMessage, isPresented: $showLimitAlert) {
                Button("OK", role: .cancel) {}
            }
            .onAppear {
                // Khởi tạo form
                date = selectedDate
                if case .edit(let event) = mode {
                    title = event.title
                    owner = event.owner
                    date = event.date
                    startTime = event.startTime
                    endTime = event.endTime
                } else {
                    let now = Date()
                    if Calendar.current.isDate(selectedDate, inSameDayAs: now) {
                        startTime = now
                    } else {
                        var comps = Calendar.current.dateComponents([.year, .month, .day], from: selectedDate)
                        comps.hour = 9
                        comps.minute = 0
                        startTime = Calendar.current.date(from: comps) ?? now
                    }
                    endTime = Calendar.current.date(byAdding: .hour, value: 1, to: startTime) ?? startTime.addingTimeInterval(3600)
                }
            }
            .alert(item: $activeAlert) { alert in
                Alert(title: Text(alert.title),
                      message: Text(alert.message),
                      dismissButton: .default(Text("OK")))
            }

        }
    }
    
    // Merge date + time
    private func combine(date day: Date, time: Date) -> Date {
        let cal = Calendar.current
        let d = cal.dateComponents([.year, .month, .day], from: day)
        let t = cal.dateComponents([.hour, .minute, .second], from: time)
        var comps = DateComponents()
        comps.year = d.year; comps.month = d.month; comps.day = d.day
        comps.hour = t.hour ?? 0; comps.minute = t.minute ?? 0; comps.second = t.second ?? 0
        return cal.date(from: comps) ?? day
    }
    
    private func handleSave() {
        let startDT = combine(date: date, time: startTime)
        let endDT = combine(date: date, time: endTime)
        let now = Date()
        
       

      
        // 2️⃣ Tạo sự kiện mới
        let newEvent = CalendarEvent(
            title: title,
            owner: owner,
            date: Calendar.current.startOfDay(for: date),
            startTime: startDT,
            endTime: endDT
        )
        
        let calendar = Calendar.current
        
        // 3️⃣ Kiểm tra giới hạn user chưa premium
        // Kiểm tra trùng slot
        if !allowOverlap {
            let overlap = existingEvents.contains { ev in
                calendar.isDate(ev.date, inSameDayAs: newEvent.date) &&
                ((startDT >= ev.startTime && startDT < ev.endTime) ||
                 (endDT > ev.startTime && endDT <= ev.endTime) ||
                 (startDT <= ev.startTime && endDT >= ev.endTime))
            }
            if overlap {
                activeAlert = AlertMessage(title: "Trùng lịch", message: "Khung giờ này đã có lịch khác.")
                return
            }
        }

        // Kiểm tra giới hạn Premium
        if !isPremiumUser {
            if let maxDate = calendar.date(byAdding: .day, value: 7, to: now),
               newEvent.date > maxDate {
                activeAlert = AlertMessage(title: "Vượt giới hạn ngày", message: "Chỉ được thêm lịch trong 7 ngày tới.")
                return
            }

            let sameDayEvents = existingEvents.filter {
                calendar.isDate($0.date, inSameDayAs: newEvent.date)
            }
            if sameDayEvents.count >= 4 {
                activeAlert = AlertMessage(title: "Vượt giới hạn", message: "Chỉ được thêm tối đa 4 lịch/ngày.")
                return
            }
        }

        
        // 5️⃣ Lưu sự kiện
        switch mode {
        case .add:
            saveEventToFirestore(newEvent)
            existingEvents.append(newEvent)

        case .edit(let old):
            if let idx = existingEvents.firstIndex(where: { $0.id == old.id }) {
                existingEvents[idx] = newEvent
            }
        }
        
        // 6️⃣ Gửi thông báo nếu bật
        if NotificationManager.shared.notificationsEnabled {
            NotificationManager.shared.scheduleNotification(
                title: "📅 \(title)",
                message: "Sắp đến giờ cho lịch: \(title) của \(owner)",
                date: startDT
            )
        }
        
        DispatchQueue.main.async { dismiss() }
    }
    
    private func deleteEvent(_ event: CalendarEvent) {
        existingEvents.removeAll { $0.id == event.id }
        DispatchQueue.main.async { dismiss() }
    }
    
}
