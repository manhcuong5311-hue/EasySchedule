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
    @EnvironmentObject var uiAccent: UIAccentStore
    @Environment(\.colorScheme) private var colorScheme

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
                    SettingsActionRow(
                        title: String(localized: "logout"),
                        systemName: "rectangle.portrait.and.arrow.right",
                        color: .gray,
                        showsChevron: false
                    )
                }
            }
            .listRowBackground(AppBackground.card(colorScheme))

            // MARK: - Delete Account (destructive → own section, last)
            Section {
                Button(role: .destructive) {
                    showPasswordSheet = true
                } label: {
                    HStack(spacing: 12) {
                        if isDeleting {
                            ProgressView()
                                .frame(width: 30, height: 30)
                            Text(String(localized: "deleting_account"))
                                .foregroundStyle(.secondary)
                        } else {
                            SettingsIconTile(systemName: "trash.fill", color: .red)
                            Text(String(localized: "delete_account"))
                                .foregroundStyle(.red)
                        }
                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                }
                .disabled(isDeleting)

            } footer: {
                Text(SettingsText.plain(String(localized: "delete_account_warning")))
            }
            .listRowBackground(AppBackground.card(colorScheme))


        }
        .scrollContentBackground(.hidden)
        .background(AppBackground.settings(colorScheme).ignoresSafeArea())
        .tint(uiAccent.color)
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
            passwordSheet
        }

    }

    // MARK: - Re-auth sheet

    private var passwordSheet: some View {
        NavigationStack {
            Form {
                Section {
                    SecureField(String(localized: "enter_password_to_delete"), text: $deletePassword)
                        .submitLabel(.done)
                } footer: {
                    if let deleteError = deleteError {
                        Label(deleteError, systemImage: "exclamationmark.circle.fill")
                            .foregroundStyle(.red)
                    }
                }
                .listRowBackground(AppBackground.card(colorScheme))

                Section {
                    Button(role: .destructive) {
                        Task { await reauthenticateAndDelete() }
                    } label: {
                        Text(String(localized: "confirm_delete_account"))
                            .font(.body.weight(.semibold))
                            .frame(maxWidth: .infinity)
                    }
                    .disabled(deletePassword.isEmpty)
                }
                .listRowBackground(AppBackground.card(colorScheme))
            }
            .scrollContentBackground(.hidden)
            .background(AppBackground.settings(colorScheme).ignoresSafeArea())
            .navigationTitle(String(localized: "delete_confirmation_title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized:"cancel")) { showPasswordSheet = false }
                }
            }
        }
        .tint(uiAccent.color)
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
            deleteError = String(localized: "incorrect_password")
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
