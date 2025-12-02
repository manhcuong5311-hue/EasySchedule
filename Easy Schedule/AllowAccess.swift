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
            ]) { error in
                if let error = error {
                    print("❌ Failed to create request:", error.localizedDescription)
                } else {
                    print("📩 Request created for owner \(owner) from \(requester)")
                }
            }
    }

    // ⭐ ALLOW (A cho phép B)
    func allowUser(ownerUid: String, otherUid: String, completion: @escaping (Bool) -> Void) {
        db.collection("calendarAccess")
            .document(ownerUid)
            .collection("allowed")
            .document(otherUid)
            .setData([
                "allowed": true,
                "allowedAt": FieldValue.serverTimestamp()
            ]) { error in
                if let error = error {
                    print("❌ Allow failed:", error.localizedDescription)
                    completion(false)
                } else {
                    print("✅ ALLOW SUCCESS: \(ownerUid) allowed \(otherUid)")
                    completion(true)

                    // ⭐ XOÁ REQUEST khi Allow
                    self.removeRequest(ownerUid: ownerUid, requesterUid: otherUid)
                }
            }
    }

    // ⭐ DENY (A chặn B)
    func denyUser(ownerUid: String, otherUid: String, completion: @escaping (Bool) -> Void) {
        db.collection("calendarAccess")
            .document(ownerUid)
            .collection("allowed")
            .document(otherUid)
            .delete { error in
                if let error = error {
                    print("❌ Deny failed:", error.localizedDescription)
                    completion(false)
                } else {
                    print("🚫 DENY SUCCESS: \(ownerUid) denied \(otherUid)")
                    completion(true)

                    // ⭐ XOÁ REQUEST nếu tồn tại
                    self.removeRequest(ownerUid: ownerUid, requesterUid: otherUid)
                }
            }
    }

    // ⭐ CHECK ALLOW
    func isAllowed(ownerUid: String, otherUid: String, completion: @escaping (Bool) -> Void) {
        db.collection("calendarAccess")
            .document(ownerUid)
            .collection("allowed")
            .document(otherUid)
            .getDocument { snap, _ in
                completion(snap?.exists ?? false)
            }
    }

    // ⭐ FETCH ALLOWED LIST
    func fetchAllowedList(ownerUid: String, completion: @escaping ([String]) -> Void) {
        db.collection("calendarAccess")
            .document(ownerUid)
            .collection("allowed")
            .getDocuments { snap, _ in
                let list = snap?.documents.map { $0.documentID } ?? []
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
    @Published var allowedUsers: [String] = []
    @Published var requests: [AccessRequest] = []
    @Published var isLoading = false

    private let service = AccessService.shared

    var ownerUid: String {
        Auth.auth().currentUser?.uid ?? ""
    }

    func loadAll() {
        guard !ownerUid.isEmpty else { return }

        isLoading = true

        service.fetchAllowedList(ownerUid: ownerUid) { allowed in
            DispatchQueue.main.async {
                self.allowedUsers = allowed
            }
        }

        service.fetchRequestList(ownerUid: ownerUid) { reqs in
            DispatchQueue.main.async {
                self.requests = reqs
                self.isLoading = false
            }
        }
    }

    func allow(_ uid: String) {
        service.allowUser(ownerUid: ownerUid, otherUid: uid) { success in
            if success { self.loadAll() }
        }
    }

    func deny(_ uid: String) {
        service.denyUser(ownerUid: ownerUid, otherUid: uid) { success in
            if success { self.loadAll() }
        }
    }
}






struct AccessManagementView: View {
    @StateObject private var vm = AllowAccessViewModel()

    var body: some View {
        List {

            // ⭐ REQUESTS – Ai đang xin phép
            Section(String(localized: "requests_section_title")) {
                if vm.requests.isEmpty {
                    Text(String(localized: "no_requests"))
                        .foregroundColor(.secondary)
                } else {
                    ForEach(vm.requests) { req in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(req.name.isEmpty ? req.uid : req.name)
                                if let time = req.requestedAt {
                                    Text(time.formatted())
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
                    }
                }
            }

            // ⭐ ALLOWED USERS
            Section(String(localized: "allowed_users_section_title")) {
                if vm.allowedUsers.isEmpty {
                    Text(String(localized: "no_allowed_users"))
                        .foregroundColor(.secondary)
                } else {
                    ForEach(vm.allowedUsers, id: \.self) { uid in
                        HStack {
                            Text(uid)
                            Spacer()
                            Button(String(localized: "block")) {
                                vm.deny(uid)
                            }
                            .foregroundColor(.red)
                        }
                    }
                }
            }
        }
        .navigationTitle(String(localized: "manage_access_title"))
        .onAppear { vm.loadAll() }
    }
}
