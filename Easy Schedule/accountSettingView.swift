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
    @State private var showPasswordSheet = false
    @State private var deletePassword = ""
    @State private var deleteError: String?

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
                    showPasswordSheet = true
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
        .sheet(isPresented: $showPasswordSheet) {
            NavigationView {
                Form {
                    SecureField(String(localized: "enter_password_to_delete"), text: $deletePassword)

                    if let deleteError = deleteError {
                        Text(deleteError)
                            .foregroundColor(.red)
                    }

                    Button(role: .destructive) {
                        Task { await reauthenticateAndDelete() }
                    } label: {
                        Text(String(localized: "confirm_delete_account"))
                    }
                    .disabled(deletePassword.isEmpty)
                }
                .navigationTitle(String(localized: "delete_confirmation_title"))
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(String(localized:"cancel")) { showPasswordSheet = false }
                    }
                }
            }
        }

    }

    func reauthenticateAndDelete() async {
        guard let user = Auth.auth().currentUser,
              let email = user.email else {
            deleteError = String(localized: "reauth_failed")
            return
        }

        let credential = EmailAuthProvider.credential(
            withEmail: email,
            password: deletePassword
        )

        do {
            // 1. Re-authenticate
            try await user.reauthenticate(with: credential)

            // 2. Đóng sheet
            showPasswordSheet = false

            // 3. Gọi hàm xoá tài khoản
            await performDeleteAccount()

        } catch {
            deleteError = String(localized: "incorrect_password.")
            print("❌ Re-authenticate failed:", error.localizedDescription)
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
