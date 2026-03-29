//
//  SignUpView.swift
//  Easy Schedule
//

import SwiftUI
import FirebaseAuth
import FirebaseFirestore

struct SignUpView: View {
    @Environment(\.dismiss) var dismiss

    @State private var name            = ""
    @State private var email           = ""
    @State private var password        = ""
    @State private var confirmPassword = ""
    @State private var errorMessage:   String?
    @State private var isLoading       = false
    @State private var success         = false

    var body: some View {
        VStack(spacing: 20) {
            Text(String(localized: "create_account"))
                .font(.largeTitle)
                .bold()

            // ── Name (required) ──────────────────────────────────────
            VStack(alignment: .leading, spacing: 4) {
                TextField(String(localized: "name_placeholder"), text: $name)
                    .textContentType(.name)
                    .autocapitalization(.words)
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(10)

                Text("This is how partners will see you in the app.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
            }

            // ── Email ────────────────────────────────────────────────
            TextField(String(localized: "email_placeholder"), text: $email)
                .keyboardType(.emailAddress)
                .autocapitalization(.none)
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(10)

            // ── Password ─────────────────────────────────────────────
            SecureField(String(localized: "password_placeholder"), text: $password)
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(10)

            SecureField(String(localized: "confirm_password_placeholder"), text: $confirmPassword)
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(10)

            if let error = errorMessage {
                Text(error).foregroundColor(.red)
            }

            if isLoading {
                ProgressView(String(localized: "creating_account"))
            }

            Button(action: signUp) {
                Text(String(localized: "sign_up_button"))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .cornerRadius(12)
            }

            Spacer()
        }
        .padding()
        .alert(String(localized: "account_created_title"), isPresented: $success) {
            Button(String(localized: "ok")) { dismiss() }
        } message: {
            Text(String(localized: "account_created_message"))
        }
        .navigationBarTitleDisplayMode(.inline)
    }

    private func signUp() {
        errorMessage = nil

        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            errorMessage = String(localized: "name_required_error")
            return
        }
        guard email.contains("@") else {
            errorMessage = String(localized: "invalid_email_error")
            return
        }
        guard password.count >= 6 else {
            errorMessage = String(localized: "password_short_error")
            return
        }
        guard password == confirmPassword else {
            errorMessage = String(localized: "password_not_match_error")
            return
        }

        isLoading = true

        Auth.auth().createUser(withEmail: email, password: password) { result, error in
            if let error = error {
                DispatchQueue.main.async {
                    self.isLoading    = false
                    self.errorMessage = error.localizedDescription
                }
                return
            }

            guard let user = result?.user else {
                DispatchQueue.main.async {
                    self.isLoading    = false
                    self.errorMessage = String(localized: "create_event_failed")
                }
                return
            }

            // Update Firebase Auth display name
            let changeRequest = user.createProfileChangeRequest()
            changeRequest.displayName = trimmedName
            changeRequest.commitChanges { _ in }

            // Write name to Firestore immediately so partners can resolve it
            Firestore.firestore()
                .collection("users")
                .document(user.uid)
                .setData([
                    "name":      trimmedName,
                    "email":     user.email ?? "",
                    "createdAt": FieldValue.serverTimestamp()
                ], merge: true)

            // Send verification email
            user.sendEmailVerification { _ in }

            DispatchQueue.main.async {
                self.isLoading = false
                self.success   = true
            }
        }
    }
}
