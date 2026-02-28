//
//  AllowAccess.swift
//  Easy Schedule
//
//  Created by Sam Manh Cuong on 2/12/25.
//
import SwiftUI
import Combine
import FirebaseFirestore
import FirebaseAuth

class AccessService {

    static let shared = AccessService()
    private let db = Firestore.firestore()
    private init() {}

    // ⭐ CREATE REQUEST (B xin phép A)
    func createRequest(owner: String, requester: String, requesterName: String? = nil) {
        db.collection("calendarAccess")
            .document(owner)
            .collection("requests")
            .document(requester)
            .setData([
                "uid": requester,
                "name": requesterName ?? "",
                "requestedAt": FieldValue.serverTimestamp()
            ], merge: true) { error in
                if let error = error {
                    print("❌ Failed to create request:", error.localizedDescription)
                } else {
                    print("📩 Request created for owner \(owner) from \(requester)")
                }
            }
    }

    // ⭐ ALLOW (A cho phép B)
    func allowUser(ownerUid: String,
                   otherUid: String,
                   otherUserName: String?,
                   completion: @escaping (Bool) -> Void) {

        let ownerAllowedRef = db
            .collection("calendarAccess")
            .document(ownerUid)
            .collection("allowed")
            .document(otherUid)

        let requestRef = db
            .collection("calendarAccess")
            .document(ownerUid)
            .collection("requests")
            .document(otherUid)

        var data: [String: Any] = [
            "allowed": true,
            "allowedAt": FieldValue.serverTimestamp()
        ]

        if let name = otherUserName {
            data["name"] = name
        }

        ownerAllowedRef.setData(data) { error in
            if let error = error {
                print("❌ Allow failed:", error.localizedDescription)
                completion(false)
                return
            }

            requestRef.delete()

            print("✅ Allow success (1-way)")

            EventManager.shared.markSharedLinkConnected(uid: otherUid)

            completion(true)
        }
    }


    // ⭐ DENY (A chặn B)
    func denyUser(ownerUid: String, otherUid: String, completion: @escaping (Bool) -> Void) {

        let key = "allow_\(ownerUid)_\(otherUid)"

        db.collection("calendarAccess")
            .document(ownerUid)
            .collection("allowed")
            .document(otherUid)
            .delete { error in

                if let error = error {
                    print("❌ Deny failed:", error.localizedDescription)
                    completion(false)
                } else {

                    // ⭐ CLEAR LOCAL CACHE
                    UserDefaults.standard.removeObject(forKey: key)

                    print("🚫 DENY SUCCESS: \(ownerUid) denied \(otherUid)")
                    completion(true)

                    self.removeRequest(ownerUid: ownerUid, requesterUid: otherUid)
                }
            }
    }

    func clearLocalAccessCache() {

        let defaults = UserDefaults.standard

        for key in defaults.dictionaryRepresentation().keys {
            if key.hasPrefix("allow_") {
                defaults.removeObject(forKey: key)
            }
        }

        defaults.synchronize()

        print("🧹 Cleared local access cache")
    }

    // ⭐ CHECK ALLOW
    func isAllowed(ownerUid: String,
                   otherUid: String,
                   completion: @escaping (Bool) -> Void) {

        let ownerRef = db.collection("calendarAccess")
            .document(ownerUid)
            .collection("allowed")
            .document(otherUid)

        ownerRef.getDocument { snap, _ in
            if snap?.exists == true {
                completion(true)
                return
            }

            // check reverse direction
            let reverseRef = self.db.collection("calendarAccess")
                .document(otherUid)
                .collection("allowed")
                .document(ownerUid)

            reverseRef.getDocument { snap2, _ in
                completion(snap2?.exists == true)
            }
        }
    }



    // ⭐ FETCH ALLOWED LIST
    func fetchAllowedList(ownerUid: String, completion: @escaping ([AllowedUser]) -> Void) {
        db.collection("calendarAccess")
            .document(ownerUid)
            .collection("allowed")
            .getDocuments { snap, _ in

                let list = snap?.documents.map {
                    AllowedUser(
                        uid: $0.documentID,
                        name: $0.data()["name"] as? String
                    )
                } ?? []

                completion(list)
            }
    }


    // ⭐ FETCH REQUESTS (ai đang xin phép)
    func fetchRequestList(ownerUid: String, completion: @escaping ([AccessRequest]) -> Void) {
        db.collection("calendarAccess")
            .document(ownerUid)
            .collection("requests")
            .order(by: "requestedAt", descending: true)
            .getDocuments { snap, _ in
                let list = snap?.documents.map { AccessRequest.from($0) } ?? []
                completion(list)
            }
    }

    // ⭐ REMOVE REQUEST (sau khi Allow hoặc Deny)
    func removeRequest(ownerUid: String, requesterUid: String) {
        db.collection("calendarAccess")
            .document(ownerUid)
            .collection("requests")
            .document(requesterUid)
            .delete()
    }
}

struct AccessRequest: Identifiable {
    var id: String { uid }
    let uid: String
    let name: String
    let requestedAt: Date?

    static func from(_ doc: DocumentSnapshot) -> AccessRequest {
        let data = doc.data() ?? [:]
        return AccessRequest(
            uid: doc.documentID,
            name: data["name"] as? String ?? "",
            requestedAt: (data["requestedAt"] as? Timestamp)?.dateValue()
        )
    }
}


class AllowAccessViewModel: ObservableObject {
    @Published var allowedUsers: [AllowedUser] = []
    @Published var requests: [AccessRequest] = []
    @Published var isLoading = false
    @Published var showName: Bool = true

    // Search fields
    @Published var requestSearch: String = ""
    @Published var allowedSearch: String = ""

    private let service = AccessService.shared
    private var cancellables = Set<AnyCancellable>()

    var ownerUid: String {
        Auth.auth().currentUser?.uid ?? ""
    }

    init() {
        // Optional: debounce search updates to reduce UI churn
        // If you don't want debounce, you can remove this block.
        $requestSearch
            .removeDuplicates()
            .debounce(for: .milliseconds(150), scheduler: RunLoop.main)
            .sink { _ in
                // no-op: just forces UI update via published property
            }
            .store(in: &cancellables)

        $allowedSearch
            .removeDuplicates()
            .debounce(for: .milliseconds(150), scheduler: RunLoop.main)
            .sink { _ in }
            .store(in: &cancellables)
    }

    func loadAll() {
        guard !ownerUid.isEmpty else { return }

        isLoading = true

        // Fetch allowed list and sort alphabetically (by name or uid)
        service.fetchAllowedList(ownerUid: ownerUid) { allowed in
            let sorted = allowed.sorted {
                let a = ($0.name ?? $0.uid).localizedLowercase
                let b = ($1.name ?? $1.uid).localizedLowercase
                return a < b
            }
            DispatchQueue.main.async {
                self.allowedUsers = sorted
            }
        }

        // Fetch requests — KEEP Firestore ordering by requestedAt (descending)
        service.fetchRequestList(ownerUid: ownerUid) { reqs in
            DispatchQueue.main.async {
                self.requests = reqs // requests are already ordered by requestedAt desc in service
                self.isLoading = false
            }
        }
    }

    func allow(_ uid: String) {

        // ===== CASE 1: Có request (user đang xin phép) =====
        if let request = requests.first(where: { $0.uid == uid }) {

            service.allowUser(
                ownerUid: ownerUid,
                otherUid: uid,
                otherUserName: request.name
            ) { success in
                if success {

                    DispatchQueue.main.async {

                        // ⭐ HOOK: update SharedLink (local history)
                        EventManager.shared.markSharedLinkConnected(uid: uid)

                        // ===== GIỮ NGUYÊN HÀNH VI CŨ =====
                        self.loadAll()
                    }
                }
            }

        }
        // ===== CASE 2: Không có request (allow thủ công) =====
        else {

            service.allowUser(
                ownerUid: ownerUid,
                otherUid: uid,
                otherUserName: nil
            ) { success in
                if success {

                    DispatchQueue.main.async {

                        // ⭐ HOOK: update SharedLink (local history)
                        EventManager.shared.markSharedLinkConnected(uid: uid)

                        // ===== GIỮ NGUYÊN HÀNH VI CŨ =====
                        self.loadAll()
                    }
                }
            }
        }
    }


    func deny(_ uid: String) {
        service.denyUser(ownerUid: ownerUid, otherUid: uid) { success in
            if success { self.loadAll() }
        }
    }

    // MARK: - Filtered lists (keeps original order of `requests`)
    var filteredRequests: [AccessRequest] {
        let query = requestSearch.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if query.isEmpty { return requests }
        return requests.filter { req in
            let text = (req.name.isEmpty ? req.uid : req.name).lowercased()
            return text.contains(query)
        }
    }

    var filteredAllowedUsers: [AllowedUser] {
        let query = allowedSearch.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if query.isEmpty { return allowedUsers }
        return allowedUsers.filter { u in
            let text = (u.name ?? u.uid).lowercased()
            return text.contains(query)
        }
    }
}


struct AccessManagementView: View {
    @StateObject private var vm = AllowAccessViewModel()
    @State private var selectedTab: AccessTab = .requests
    @State private var showBlockConfirm = false
    @State private var userToBlock: AllowedUser?

    var body: some View {
        VStack {
            // ⭐ Segmented Picker
            Picker("", selection: $selectedTab) {
                Text(String(localized: "requests_section_title"))
                    .tag(AccessTab.requests)
                Text(String(localized: "allowed_users_section_title"))
                    .tag(AccessTab.allowed)
            }
            .pickerStyle(.segmented)
            .padding()

            // ⭐ Nội dung tùy theo Tab
            List {
                if selectedTab == .requests {
                    requestsSection
                } else {
                    allowedUsersSection
                }
            }
        }
        .navigationTitle(String(localized: "manage_access_title"))
        .confirmationDialog(
            String(localized: "remove_access_confirm_title"),
            isPresented: $showBlockConfirm,
            titleVisibility: .visible
        ) {
            Button(String(localized: "remove_access"), role: .destructive) {
                if let user = userToBlock {
                    vm.deny(user.uid)
                    userToBlock = nil
                }
            }

            Button(String(localized: "cancel"), role: .cancel) {
                userToBlock = nil
            }
        } message: {
            if let user = userToBlock {
                Text(
                    String(
                        format: String(localized: "remove_access_confirm_message"),
                        vm.showName ? (user.name ?? user.uid) : user.uid
                    )
                )
            }
        }
        .onAppear { vm.loadAll() }

        .onAppear { vm.loadAll() }
    }

    // MARK: - Requests Section
    private var requestsSection: some View {
        Section {
            // Search
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField(String(localized: "search_by_name"), text: $vm.requestSearch)
            }
            .padding(.vertical, 6)

            if vm.filteredRequests.isEmpty {
                Text(String(localized: "no_requests"))
                    .foregroundColor(.secondary)
            } else {
                ForEach(vm.filteredRequests) { req in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(req.name.isEmpty ? req.uid : req.name)

                            if let time = req.requestedAt {
                                Text(time.formatted(.dateTime.hour().minute().month().day().year()))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }

                        Spacer()

                        Button(String(localized: "allow_button")) {
                            vm.allow(req.uid)
                        }
                        .buttonStyle(.borderedProminent)

                        Button(String(localized: "deny_button")) {
                            vm.deny(req.uid)
                        }
                        .foregroundColor(.red)
                    }
                    .padding(.vertical, 6)
                }
            }
        }
    }

    // MARK: - Allowed Users Section
    private var allowedUsersSection: some View {
        Section {

            // Search
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField(String(localized: "search_by_name"), text: $vm.allowedSearch)
            }
            .padding(.vertical, 6)

            // Toggle
            Toggle(String(localized:"show_names"), isOn: $vm.showName)

            if vm.filteredAllowedUsers.isEmpty {
                Text(String(localized: "no_allowed_users"))
                    .foregroundColor(.secondary)
            } else {
                ForEach(vm.filteredAllowedUsers) { user in
                    HStack {
                        Text(vm.showName ? (user.name ?? user.uid) : user.uid)
                            .lineLimit(1)

                        Spacer()
                    }
                    .contentShape(Rectangle()) // ⭐ cho swipe + long press toàn row

                    // 👉 HOLD (long press) → COPY UID
                    .contextMenu {
                        Button {
                            UIPasteboard.general.string = user.uid
                        } label: {
                            Label(
                                String(localized: "copy_uid"),
                                systemImage: "doc.on.doc"
                            )
                        }
                    }

                    // 👉 SWIPE LEFT → REMOVE
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            userToBlock = user
                            showBlockConfirm = true
                        } label: {
                            Label(
                                String(localized: "remove_access_button"),
                                systemImage: "trash"
                            )
                        }
                    }
                }

            }
        }
    }
}


struct AllowedUser: Identifiable {
    var id: String { uid }
    let uid: String
    let name: String?
}


enum AccessTab: String, CaseIterable {
    case requests = "Requests"
    case allowed = "Allowed"
}
