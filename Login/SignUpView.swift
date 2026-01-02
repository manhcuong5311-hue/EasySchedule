//
//  SignUpView.swift
//  Easy Schedule
//
//  Created by Sam Manh Cuong on 2/1/26.
//


import SwiftUI
import FirebaseAuth

struct SignUpView: View {
    @Environment(\.dismiss) var dismiss

    @State private var email = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var errorMessage: String?
    @State private var isLoading = false
    @State private var success = false

    var body: some View {
        VStack(spacing: 20) {
            Text(String(localized: "create_account"))
                .font(.largeTitle)
                .bold()

            TextField(String(localized: "email_placeholder"), text: $email)
                .keyboardType(.emailAddress)
                .autocapitalization(.none)
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(10)

            SecureField(String(localized: "password_placeholder"), text: $password)
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(10)

            SecureField(String(localized: "confirm_password_placeholder"), text: $confirmPassword)
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(10)

            if let error = errorMessage {
                Text(error)
                    .foregroundColor(.red)
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
            Button(String(localized:"ok")) { dismiss() }
        } message: {
            Text(String(localized: "account_created_message"))
        }
        .navigationBarTitleDisplayMode(.inline)
    }

    private func signUp() {
        errorMessage = nil
        
        if !email.contains("@") {
            errorMessage = String(localized: "invalid_email_error")
            return
        }
        if password.count < 6 {
            errorMessage = String(localized: "password_short_error")
            return
        }
        if password != confirmPassword {
            errorMessage = String(localized: "password_not_match_error")
            return
        }

        isLoading = true

        Auth.auth().createUser(withEmail: email, password: password) { result, error in
            isLoading = false

            if let error = error {
                errorMessage = error.localizedDescription
                return
            }

            result?.user.sendEmailVerification { _ in }
            success = true
        }
    }
}

