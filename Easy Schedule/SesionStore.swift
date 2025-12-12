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
            
            guard let user = user else {
                print("ℹ️ No Firebase user → logged out.")
                self.currentUser = nil
                self.currentUserName = ""
                return
            }
            
            user.getIDTokenResult { result, error in
                if let error = error {
                    print("❌ Invalid token → forcing logout:", error.localizedDescription)
                    self.signOut()
                    return
                }
                
                // ⭐️ TOKEN OK → CHECK EMAIL VERIFICATION
                user.reload { _ in
                    if !user.isEmailVerified {
                        print("⛔ Unverified email → blocking session login")
                        self.signOut()
                        return
                    }
                    
                    print("✅ Verified email → session login allowed:", user.uid)
                    
                    // ⭐️ ONLY RUN THESE ONCE (bạn chạy sai 2 lần ở bản cũ)
                    self.currentUser = user
                    self.saveProfileIfNeeded(user: user)
                    
                    if let cachedName = UserDefaults.standard.string(forKey: self.nameKey) {
                        self.currentUserName = cachedName
                    }
                    
                    self.fetchProfile(uid: user.uid)
                    self.cleanUpPastEventsOnFirebase(for: user.uid)
                }
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
