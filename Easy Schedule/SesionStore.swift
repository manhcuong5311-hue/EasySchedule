//
//  SessionStore.swift
//  Easy Schedule
//

import SwiftUI
import Combine
import FirebaseAuth
import FirebaseFirestore

class SessionStore: ObservableObject {
    @Published var currentUser: User?
    @Published var currentUserName: String = ""

    private var authStateListenerHandle: AuthStateDidChangeListenerHandle?
    private let db = Firestore.firestore()
    private let nameKey = "currentUserName"

    var currentUserId: String? {
        Auth.auth().currentUser?.uid
    }

    init() {
        listen()
    }
    // Cleanup busySlots: only keep slots whose end > now
    func cleanupBusySlots(for uid: String) {
        let docRef = Firestore.firestore().collection("publicCalendar").document(uid)
        let now = Date().timeIntervalSince1970 * 1000 // milliseconds

        docRef.getDocument { snap, err in
            if let err = err {
                print("❌ cleanupBusySlots: getDocument error:", err.localizedDescription)
                return
            }
            guard let data = snap?.data() else {
                // no document -> nothing to clean
                return
            }

            // busySlots could be stored as array of dicts or array of timestamps — handle common cases
            guard let rawSlots = data["busySlots"] as? [Any], !rawSlots.isEmpty else {
                return
            }

            // Helper to read `end` as Double (ms since epoch)
            func endValue(from any: Any) -> Double {
                if let d = any as? Double { return d }
                if let i = any as? Int { return Double(i) }
                if let i64 = any as? Int64 { return Double(i64) }
                if let ts = any as? Timestamp { return ts.dateValue().timeIntervalSince1970 * 1000 }
                if let dict = any as? [String: Any] {
                    if let d = dict["end"] as? Double { return d }
                    if let i = dict["end"] as? Int { return Double(i) }
                    if let i64 = dict["end"] as? Int64 { return Double(i64) }
                    if let ts = dict["end"] as? Timestamp { return ts.dateValue().timeIntervalSince1970 * 1000 }
                }
                return 0
            }

            // Build array of slots as originally stored (preserve structure)
            var originalSlots = rawSlots
            var filteredSlots: [Any] = []

            for slot in rawSlots {
                // slot might be a dict with "start"/"end", or it might be an array/number — handle dict case primarily
                if let dict = slot as? [String: Any] {
                    let end = endValue(from: dict)
                    if end > now {
                        filteredSlots.append(dict)
                    }
                } else if let value = slot as? Any {
                    let end = endValue(from: value)
                    if end > now {
                        filteredSlots.append(value)
                    }
                }
            }

            // If nothing changed, avoid a write
            if filteredSlots.count == originalSlots.count {
                return
            }

            // Perform update (only write when there is a change)
            docRef.updateData(["busySlots": filteredSlots]) { err in
                if let err = err {
                    print("❌ cleanupBusySlots: updateData error:", err.localizedDescription)
                } else {
                    print("✅ cleanupBusySlots: removed \(originalSlots.count - filteredSlots.count) expired slots for \(uid)")
                }
            }
        }
    }
    func cleanUpPastEventsOnFirebase(for uid: String) {
        let now = Date()

        Firestore.firestore().collection("events")
            .whereField("owner", isEqualTo: uid)
            .whereField("endTime", isLessThan: now)  // XOÁ NGAY khi hết hạn
            .limit(to: 50)
            .getDocuments { snapshot, error in
            
                if let error = error {
                    print("❌ cleanUpPastEventsOnFirebase error:", error.localizedDescription)
                    return
                }

                guard let docs = snapshot?.documents, !docs.isEmpty else {
                    print("ℹ️ Không có event hết hạn để xoá.")
                    return
                }

                let batch = Firestore.firestore().batch()
                docs.forEach { batch.deleteDocument($0.reference) }

                batch.commit { error in
                    if let error = error {
                        print("❌ batch delete error:", error.localizedDescription)
                    } else {
                        print("🧹 Firebase cleanup: đã xoá \(docs.count) event hết hạn cho user \(uid)")
                    }
                }
            }
    }


    
    // MARK: - Auth Listener
    func listen() {
        authStateListenerHandle = Auth.auth().addStateDidChangeListener { auth, user in
            self.currentUser = user

            if let user = user {
                self.saveProfileIfNeeded(user: user)

                // 1️⃣ Load từ local cache trước
                if let cachedName = UserDefaults.standard.string(forKey: self.nameKey) {
                    self.currentUserName = cachedName
                }

                // 2️⃣ Sync 1 lần từ Firestore
                self.fetchProfile(uid: user.uid)

                // ⭐ 3️⃣ Cleanup busySlots cũ – tránh phình dữ liệu
                self.cleanupBusySlots(for: user.uid)
                self.cleanUpPastEventsOnFirebase(for: user.uid)

            } else {
                self.currentUserName = ""
            }
        }
    }


    // MARK: - Fetch Firestore 1 lần
    func fetchProfile(uid: String) {
        db.collection("users").document(uid).getDocument { snap, err in
            if let data = snap?.data(),
               let name = data["name"] as? String {

                DispatchQueue.main.async {
                    self.currentUserName = name

                    // Cache
                    UserDefaults.standard.set(name, forKey: self.nameKey)
                    UserNameCache.shared.names[uid] = name
                }
            }
        }
    }

    // MARK: - Save Profile Once
    func saveProfileIfNeeded(user: User) {
        let ref = db.collection("users").document(user.uid)

        ref.getDocument { snap, _ in
            if snap?.exists == false {
                ref.setData([
                    "name": user.displayName ?? String(localized: "no_name"),
                    "email": user.email ?? "",
                    "createdAt": FieldValue.serverTimestamp()
                ], merge: true)
            }
        }
    }

    // MARK: - Update name
    func updateUserName(_ newName: String, completion: @escaping (Bool) -> Void) {
        guard let uid = currentUserId else {
            completion(false)
            return
        }

        db.collection("users").document(uid)
            .setData(["name": newName,
                      "updatedAt": Timestamp(date: Date())],
                     merge: true) { err in

                if let err = err {
                    print("❌ updateUserName error:", err.localizedDescription)
                    completion(false)
                    return
                }

                DispatchQueue.main.async {
                    self.currentUserName = newName

                    // Cache
                    UserDefaults.standard.set(newName, forKey: self.nameKey)
                    UserNameCache.shared.names[uid] = newName
                }

                completion(true)
            }
    }

    // MARK: - Sign Out
    func signOut() {
        do {
            UserNameCache.shared.clearCache()
            EventManager.shared.clearLocalEvents()
            EventManager.shared.reset()

            try Auth.auth().signOut()

            self.currentUser = nil
            self.currentUserName = ""

        } catch {
            print("❌ Logout error:", error)
        }
    }

    deinit {
        if let handle = authStateListenerHandle {
            Auth.auth().removeStateDidChangeListener(handle)
        }
    }

    // MARK: - Username Cache Class
    class UserNameCache: ObservableObject {
        static let shared = UserNameCache()
        @Published var names: [String: String] = [:]

        private let db = Firestore.firestore()

        func getName(for uid: String, completion: @escaping (String) -> Void) {
            if let cached = names[uid] {
                completion(cached)
                return
            }

            db.collection("users").document(uid).getDocument { snap, err in
                let name = snap?.data()?["name"] as? String ?? uid

                DispatchQueue.main.async {
                    self.names[uid] = name
                    completion(name)
                }
            }
        }

        func clearCache() {
            DispatchQueue.main.async {
                self.names.removeAll()
            }
        }
    }
}
