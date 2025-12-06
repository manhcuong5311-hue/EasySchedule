//
//  accountSettingView.swift
//  Easy Schedule
//
//  Created by Sam Manh Cuong on 6/12/25.
//

import SwiftUI
import FirebaseAuth
import FirebaseFunctions

struct AccountSettingsView: View {

    @EnvironmentObject var session: SessionStore

    @State private var showLogoutConfirm = false
    @State private var showDeleteConfirm = false
    @State private var isDeleting = false

    var body: some View {
        Form {

            // MARK: - Logout
            Section {
                Button {
                    showLogoutConfirm = true
                } label: {
                    Label(String(localized: "logout"), systemImage: "rectangle.portrait.and.arrow.right")
                }
                .foregroundColor(.primary)
            }

            // MARK: - Delete Account
            Section {
                Button(role: .destructive) {
                    showDeleteConfirm = true
                } label: {
                    if isDeleting {
                        HStack {
                            ProgressView()
                            Text(String(localized: "deleting_account"))
                        }
                    } else {
                        Label(String(localized: "delete_account"), systemImage: "trash")
                    }
                }
                .disabled(isDeleting)

            } footer: {
                Text(String(localized: "delete_account_warning"))
                    .foregroundColor(.secondary)
            }


        }
        .navigationTitle(String(localized: "account_management"))
        .navigationBarTitleDisplayMode(.inline)

        // LOGOUT ALERT
        .alert(String(localized: "logout_confirm"), isPresented: $showLogoutConfirm) {
            Button(String(localized: "cancel"), role: .cancel) {}
            Button(String(localized: "logout"), role: .destructive) {
                performLogout()
            }
        } message: {
            Text(String(localized: "logout_message"))
        }

        // DELETE ACCOUNT ALERT
        .alert(String(localized: "delete_account_confirm"), isPresented: $showDeleteConfirm) {
            Button(String(localized: "cancel"), role: .cancel) {}
            Button(String(localized: "delete_account"), role: .destructive) {
                Task { await performDeleteAccount() }
            }
        } message: {
            Text(String(localized: "delete_account_warning"))
        }
    }

    // MARK: - Actions

    func performLogout() {
        do {
            try Auth.auth().signOut()
            session.currentUser = nil
        } catch {
            print("❌ Logout failed: \(error.localizedDescription)")
        }
    }

    func performDeleteAccount() async {
        isDeleting = true

        do {
            // 1. Gọi Cloud Function để xóa dữ liệu & auth user
            let functions = Functions.functions()
            _ = try await functions.httpsCallable("deleteAccount").call()

            // 2. Logout local
            session.signOut()

            print("✅ Account deleted + logged out")

        } catch {
            print("❌ Delete account failed:", error.localizedDescription)
        }

        isDeleting = false
    }

}
