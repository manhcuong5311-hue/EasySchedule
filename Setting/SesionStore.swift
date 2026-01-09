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
    private var didSetupSession = false

    private var authStateListenerHandle: AuthStateDidChangeListenerHandle?
    private let db = Firestore.firestore()
    private let nameKey = "currentUserName"
   

    var currentUserId: String? {
        Auth.auth().currentUser?.uid
    }

    init() {
        listen()
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
                    print("ℹ️ No expired events to clean.")
                    return
                }

                let batch = Firestore.firestore().batch()
                docs.forEach { batch.deleteDocument($0.reference) }

                batch.commit { error in
                    if let error = error {
                        print("❌ batch delete error:", error.localizedDescription)
                    } else {
                        print("🧹 Firebase cleanup: deleted \(docs.count) expired events for user \(uid)")
                    }
                }
            }
    }


    
    // MARK: - Auth Listener
    func listen() {
        authStateListenerHandle =
        Auth.auth().addStateDidChangeListener { _, user in

            DispatchQueue.main.async {
                self.currentUser = user
            }

            guard let user = user else {
                DispatchQueue.main.async {
                    self.currentUserName = ""
                    self.didSetupSession = false
                }
                return
            }

            // ❌ KHÔNG block login vì token / reload
            // ❌ KHÔNG signOut khi offline

            // ✅ Chỉ check email verified KHI ONLINE
            user.reload { error in
                if error == nil {
                    if user.isEmailVerified == false {
                        DispatchQueue.main.async {
                            self.signOut()
                        }
                    }
                }
            }

            guard self.didSetupSession == false else { return }
            self.didSetupSession = true

            self.saveProfileIfNeeded(user: user)
            self.syncTimezoneIfNeeded()
            if let cachedName = UserDefaults.standard.string(forKey: self.nameKey) {
                self.currentUserName = cachedName
            }

            self.fetchProfile(uid: user.uid)
            self.cleanUpPastEventsOnFirebase(for: user.uid)
        }
    }


    // MARK: - Fetch Firestore 1 lần
    func fetchProfile(uid: String) {
        db.collection("users").document(uid).getDocument { snap, _ in
            if let data = snap?.data(),
               let rawName = data["name"] as? String {

                let trimmed = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
                let finalName = trimmed.isEmpty
                    ? String(localized: "no_name")
                    : trimmed

                DispatchQueue.main.async {
                    self.currentUserName = finalName
                    UserDefaults.standard.set(finalName, forKey: self.nameKey)
                    UserNameCache.shared.names[uid] = finalName
                }
            }
        }
    }


    // MARK: - Save Profile Once
    func saveProfileIfNeeded(user: User) {
        let ref = db.collection("users").document(user.uid)

        ref.getDocument { snap, _ in
            if snap?.exists == false {

                let providerName = user.displayName?
                    .trimmingCharacters(in: .whitespacesAndNewlines)

                let finalName = (providerName?.isEmpty == false)
                    ? providerName!
                    : String(localized: "no_name")

                ref.setData([
                    "name": finalName,
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

        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalName = trimmed.isEmpty
            ? String(localized: "no_name")
            : trimmed

        db.collection("users").document(uid)
            .setData([
                "name": finalName,
                "updatedAt": Timestamp(date: Date())
            ], merge: true) { err in

                if let err = err {
                    print("❌ updateUserName error:", err.localizedDescription)
                    completion(false)
                    return
                }

                DispatchQueue.main.async {
                    self.currentUserName = finalName
                    UserDefaults.standard.set(finalName, forKey: self.nameKey)
                    UserNameCache.shared.names[uid] = finalName
                }

                completion(true)
            }
    }


    // MARK: - Sign Out
    func signOut() {
        do {
            didSetupSession = false   // ⭐ RESET Ở ĐÂY

            UserNameCache.shared.clearCache()
            EventManager.shared.clearLocalEvents()
            EventManager.shared.reset()

            try Auth.auth().signOut()

            self.currentUser = nil
            self.currentUserName = ""

        } catch {
            print("❌ Logout error:", error.localizedDescription)
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

            db.collection("users").document(uid).getDocument { snap, _ in
                let raw = snap?.data()?["name"] as? String
                let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines)

                let finalName = (trimmed?.isEmpty == false)
                    ? trimmed!
                    : String(localized: "no_name")

                DispatchQueue.main.async {
                    self.names[uid] = finalName
                    completion(finalName)
                }
            }
        }

        func clearCache() {
            DispatchQueue.main.async {
                self.names.removeAll()
            }
        }
    }
    
    func syncTimezoneIfNeeded() {
        guard let uid = currentUserId else { return }

        let tz = TimeZone.current
        let cachedTzId = UserDefaults.standard.string(forKey: "lastTimezoneId")

        // ❗ Không đổi timezone → không cần sync
        guard cachedTzId != tz.identifier else { return }

        db.collection("users").document(uid)
          .setData([
              "timezoneId": tz.identifier,
              "timezoneOffsetMinutes": tz.secondsFromGMT() / 60,
              "updatedAt": FieldValue.serverTimestamp()
          ], merge: true)

        // Cache lại
        UserDefaults.standard.set(tz.identifier, forKey: "lastTimezoneId")
    }


    
    
}
