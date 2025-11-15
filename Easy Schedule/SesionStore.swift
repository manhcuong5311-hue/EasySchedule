//
//  SesionStore.swift
//  Easy Schedule
//
//  Created by Sam Manh Cuong on 12/11/25.
//

import SwiftUI
import FirebaseAuth
import Combine
class SessionStore: ObservableObject {
    @Published var currentUser: User?

    init() {
        listen()
    }

    private var authStateHandle: AuthStateDidChangeListenerHandle?

    func listen() {
        authStateHandle = Auth.auth().addStateDidChangeListener { _, user in
            self.currentUser = user
        }
    }
    deinit {
        if let handle = authStateHandle {
            Auth.auth().removeStateDidChangeListener(handle)
        }
    }


    func signOut() {
        do {
            try Auth.auth().signOut()
            self.currentUser = nil
        } catch {
            print("❌ Logout error: \(error)")
        }
    }
}
