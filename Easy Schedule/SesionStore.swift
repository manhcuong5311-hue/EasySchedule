//
//  SessionStore.swift
//  Easy Schedule
//

import SwiftUI
import Combine               // ← MUST have this
import FirebaseAuth
import FirebaseFirestore

class SessionStore: ObservableObject {
    @Published var currentUser: User?
    @Published var currentUserName: String = ""
    var currentUserId: String? {
        Auth.auth().currentUser?.uid
    }

    private var authStateListenerHandle: AuthStateDidChangeListenerHandle?
    
    init() {
        listen()
    }
    func handleLoginSuccess() {
        EventManager.shared.clearLocalEvents()   // reset mọi listener cũ
        EventManager.shared.reloadForCurrentUser()  // load đúng UID mới
    }
    
    
    // MARK: - Listen Auth State
    func listen() {
        authStateListenerHandle = Auth.auth().addStateDidChangeListener { auth, user in
            self.currentUser = user
            
            if let user = user {
                self.saveProfileIfNeeded(user: user)
                self.fetchProfile(uid: user.uid)   // ⭐ ĐỔI DÒNG NÀY
            } else {
                self.currentUserName = ""
            }
        }
    }
    
    func fetchProfile(uid: String) {
        Firestore.firestore().collection("users").document(uid).getDocument { snap, err in
            if let data = snap?.data(),
               let name = data["name"] as? String {
                DispatchQueue.main.async {
                    self.currentUserName = name
                }
            }
        }
    }
    // MARK: - Save Profile (only first login)
    func saveProfileIfNeeded(user: User) {
        let ref = Firestore.firestore().collection("users").document(user.uid)
        
        ref.getDocument { snap, _ in
            if snap?.exists == false {
                ref.setData([
                    "name": user.displayName ?? "Không tên",
                    "email": user.email ?? "",
                    "createdAt": FieldValue.serverTimestamp()
                ], merge: true)
            }
        }
    }
    
    // MARK: - Load User Name
    func loadUserName(uid: String) {
        Firestore.firestore().collection("users")
            .document(uid)
            .getDocument { snap, err in
                if let name = snap?.data()?["name"] as? String {
                    DispatchQueue.main.async {
                        self.currentUserName = name
                        print("⭐ Loaded name:", name)
                    }
                }
            }
    }
    
    
    // MARK: - Sign Out
    func signOut() {
        do {
            UserNameCache.shared.clearCache()
            // 1️⃣ Clear event local để tránh user B thấy lịch user A
            EventManager.shared.clearLocalEvents()
            EventManager.shared.reset()
            // 2️⃣ Logout Firebase
            try Auth.auth().signOut()
            
            // 3️⃣ Clear session
            self.currentUser = nil
            self.currentUserName = ""
            
            print("🔄 Đăng xuất thành công — đã xoá cache lịch trước.")
        } catch {
            print("❌ Logout error:", error)
        }
    }
    
    
    // MARK: - Deinit
    deinit {
        if let handle = authStateListenerHandle {
            Auth.auth().removeStateDidChangeListener(handle)
        }
    }
    func updateUserName(_ newName: String, completion: @escaping (Bool) -> Void) {
        guard let uid = currentUserId else {
            completion(false)
            return
        }

        let data: [String: Any] = [
            "name": newName,
            "updatedAt": Timestamp(date: Date())
        ]

        Firestore.firestore().collection("users").document(uid).updateData(data) { err in
            if let err = err {
                print("❌ updateUserName error: \(err.localizedDescription)")
                completion(false)
                return
            }

            DispatchQueue.main.async {
                self.currentUserName = newName

                // ⭐ Cập nhật cache ngay
                UserNameCache.shared.names[uid] = newName
            }

            completion(true)
        }
    }

 
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
                    self.names[uid] = name   // ⭐ Lưu cache
                    completion(name)          // ⭐ Gọi sau khi lưu
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

