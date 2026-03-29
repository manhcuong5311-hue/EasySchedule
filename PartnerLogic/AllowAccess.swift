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

            EventManager.shared.addSharedLink(
                for: ownerUid,
                otherUid: otherUid
            )

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

            var enriched: [AllowedUser] = []
            let group = DispatchGroup()

            for user in allowed {
                group.enter()

                self.service.isAllowed(
                    ownerUid: user.uid,
                    otherUid: self.ownerUid
                ) { mutual in

                    var updated = user
                    updated.isMutual = mutual
                    enriched.append(updated)

                    group.leave()
                }
            }

            group.notify(queue: .main) {

                let sorted = enriched.sorted {
                    ($0.name ?? $0.uid).localizedLowercase <
                    ($1.name ?? $1.uid).localizedLowercase
                }

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
    @State private var selectedTab:    AccessTab   = .requests
    @State private var showBlockConfirm             = false
    @State private var userToBlock:    AllowedUser? = nil

    var body: some View {
        VStack(spacing: 0) {
            // ── Tab picker ───────────────────────────────────────────────
            Picker("", selection: $selectedTab) {
                Text(String(localized: "requests_section_title"))
                    .tag(AccessTab.requests)
                Text(String(localized: "allowed_users_section_title"))
                    .tag(AccessTab.allowed)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            // ── Content ─────────────────────────────────────────────────
            if vm.isLoading {
                Spacer()
                ProgressView()
                Spacer()
            } else if selectedTab == .requests {
                requestsView
            } else {
                allowedUsersView
            }
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(String(localized: "manage_access_title"))
        .confirmationDialog(
            String(localized: "remove_access_confirm_title"),
            isPresented: $showBlockConfirm,
            titleVisibility: .visible
        ) {
            Button(String(localized: "remove_access"), role: .destructive) {
                if let user = userToBlock { vm.deny(user.uid); userToBlock = nil }
            }
            Button(String(localized: "cancel"), role: .cancel) { userToBlock = nil }
        } message: {
            if let user = userToBlock {
                Text(String(
                    format: String(localized: "remove_access_confirm_message"),
                    vm.showName ? (user.name ?? user.uid) : user.uid
                ))
            }
        }
        .onAppear { vm.loadAll() }
    }

    // MARK: – Requests tab

    private var requestsView: some View {
        ScrollView {
            VStack(spacing: 12) {
                // Search bar
                searchBar(text: $vm.requestSearch, placeholder: String(localized: "search_by_name"))
                    .padding(.horizontal, 16)

                if vm.filteredRequests.isEmpty {
                    emptyState(
                        icon: "bell.slash",
                        title: String(localized: "no_requests"),
                        hint: "Access requests from others will appear here."
                    )
                    .padding(.top, 40)
                } else {
                    VStack(spacing: 10) {
                        ForEach(vm.filteredRequests) { req in
                            requestCard(req)
                        }
                    }
                    .padding(.horizontal, 16)
                }
            }
            .padding(.top, 8)
            .padding(.bottom, 32)
        }
    }

    private func requestCard(_ req: AccessRequest) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                // Avatar
                ZStack {
                    Circle()
                        .fill(Color.accentColor.opacity(0.12))
                        .frame(width: 42, height: 42)
                    Text(req.name.isEmpty ? "?" : req.name.prefix(1).uppercased())
                        .font(.headline)
                        .foregroundStyle(Color.accentColor)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(req.name.isEmpty ? req.uid : req.name)
                        .font(.system(size: 15, weight: .semibold))
                        .lineLimit(1)

                    if let time = req.requestedAt {
                        HStack(spacing: 4) {
                            Image(systemName: "clock")
                                .font(.caption2)
                            Text(time.formatted(.dateTime.hour().minute().month().day()))
                                .font(.caption)
                        }
                        .foregroundStyle(.secondary)
                    }
                }

                Spacer()
            }

            // Action buttons
            HStack(spacing: 10) {
                Button {
                    vm.deny(req.uid)
                } label: {
                    Text(String(localized: "deny_button"))
                        .font(.subheadline.weight(.medium))
                        .frame(maxWidth: .infinity, minHeight: 36)
                        .background(Color(.tertiarySystemGroupedBackground))
                        .foregroundStyle(.red)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)

                Button {
                    vm.allow(req.uid)
                } label: {
                    Text(String(localized: "allow_button"))
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 36)
                        .background(Color.accentColor)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    // MARK: – Allowed users tab

    private var allowedUsersView: some View {
        ScrollView {
            VStack(spacing: 12) {
                // Search bar
                searchBar(text: $vm.allowedSearch, placeholder: String(localized: "search_by_name"))
                    .padding(.horizontal, 16)

                if vm.filteredAllowedUsers.isEmpty {
                    emptyState(
                        icon: "person.2.slash",
                        title: String(localized: "no_allowed_users"),
                        hint: "Users you've approved will appear here."
                    )
                    .padding(.top, 40)
                } else {
                    VStack(spacing: 10) {
                        ForEach(vm.filteredAllowedUsers) { user in
                            allowedUserCard(user)
                        }
                    }
                    .padding(.horizontal, 16)
                }
            }
            .padding(.top, 8)
            .padding(.bottom, 32)
        }
    }

    private func allowedUserCard(_ user: AllowedUser) -> some View {
        HStack(spacing: 12) {
            // Avatar
            ZStack {
                Circle()
                    .fill(user.isMutual
                        ? Color.green.opacity(0.12)
                        : Color.orange.opacity(0.12))
                    .frame(width: 42, height: 42)
                Text((user.name ?? user.uid).prefix(1).uppercased())
                    .font(.headline)
                    .foregroundStyle(user.isMutual ? .green : .orange)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(vm.showName ? (user.name ?? user.uid) : shortUID(user.uid))
                    .font(.system(size: 15, weight: .medium))
                    .lineLimit(1)

                HStack(spacing: 4) {
                    Circle()
                        .fill(user.isMutual ? Color.green : Color.orange)
                        .frame(width: 6, height: 6)
                    Text(
                        user.isMutual
                        ? String(localized: "access_mutual")
                        : String(localized: "access_one_way_request")
                    )
                        .font(.caption)
                        .foregroundStyle(user.isMutual ? .green : .orange)
                }
            }

            Spacer()
        }
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .contentShape(Rectangle())
        .onTapGesture {
            if !user.isMutual {
                AccessService.shared.createRequest(
                    owner: user.uid,
                    requester: vm.ownerUid,
                    requesterName: user.name
                )
            }
        }
        .contextMenu {
            Button {
                UIPasteboard.general.string = user.uid
            } label: {
                Label(String(localized: "copy_uid"), systemImage: "doc.on.doc")
            }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
                userToBlock = user
                showBlockConfirm = true
            } label: {
                Label(String(localized: "remove_access_button"), systemImage: "trash")
            }
        }
    }

    // MARK: – Shared helpers

    private func searchBar(text: Binding<String>, placeholder: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField(placeholder, text: text)
                .autocorrectionDisabled(true)
                .textInputAutocapitalization(.never)
            if !text.wrappedValue.isEmpty {
                Button { text.wrappedValue = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(Color(.systemGray3))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(10)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func emptyState(icon: String, title: String, hint: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 36))
                .foregroundStyle(Color(.systemGray3))
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(hint)
                .font(.caption)
                .foregroundStyle(Color(.tertiaryLabel))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 32)
    }

    private func shortUID(_ uid: String) -> String {
        guard uid.count > 8 else { return uid }
        return uid.prefix(4) + "…" + uid.suffix(4)
    }
}


struct AllowedUser: Identifiable {
    var id: String { uid }
    let uid: String
    let name: String?
    var isMutual: Bool = false
}


enum AccessTab: String, CaseIterable {
    case requests = "Requests"
    case allowed = "Allowed"
}
