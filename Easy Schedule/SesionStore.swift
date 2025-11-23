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

    private var authStateListenerHandle: AuthStateDidChangeListenerHandle?

    init() {
        listen()
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
            try Auth.auth().signOut()
            self.currentUser = nil
            self.currentUserName = ""
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
}
