import SwiftUI
import FirebaseAuth
import GoogleSignIn
import FirebaseCore
import AuthenticationServices
import CryptoKit

struct LoginView: View {

    // MARK: - State
    @State private var email = ""
    @State private var password = ""
    @State private var errorMessage: String?
    @State private var isLoggedIn = false
    @State private var currentNonce: String?
    @State private var showVerifyAlert = false
    @State private var isLoading = false

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {

                    Spacer(minLength: 40)

                    // TITLE
                    Text(String(localized: "login_title"))
                        .font(.largeTitle.bold())
                        .padding(.bottom, 20)

                    // EMAIL
                    TextField(
                        String(localized: "email_placeholder"),
                        text: $email
                    )
                    .keyboardType(.emailAddress)
                    .autocapitalization(.none)
                    .textInputAutocapitalization(.never)
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(14)

                    // PASSWORD
                    SecureField(
                        String(localized: "password_placeholder"),
                        text: $password
                    )
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(14)

                    // ERROR
                    if let error = errorMessage {
                        Text(error)
                            .foregroundColor(.red)
                            .multilineTextAlignment(.center)
                    }

                    // LOGIN
                    Button(action: login) {
                        if isLoading {
                            ProgressView()
                                .tint(.white)
                                .frame(maxWidth: .infinity)
                                .padding()
                        } else {
                            Text(String(localized: "login"))
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding()
                        }
                    }
                    .background(Color.blue)
                    .cornerRadius(16)
                    .disabled(isLoading)


                    // FORGOT PASSWORD
                    Button(action: resetPassword) {
                        Text(String(localized: "forgot_password"))
                            .foregroundColor(.blue)
                            .font(.footnote)
                    }

                    // SIGN UP
                    NavigationLink(destination: SignUpView()) {
                        Text(String(localized: "signup_title"))
                            .foregroundColor(.blue)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .overlay(
                                RoundedRectangle(cornerRadius: 16)
                                    .stroke(Color.blue, lineWidth: 2)
                            )
                    }

                    // GOOGLE
                    Button(action: signInWithGoogle) {
                        HStack(spacing: 8) {
                            Image(systemName: "globe")
                            Text(String(localized: "login_google"))
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.red)
                        .cornerRadius(16)
                    }

                    // APPLE
                    SignInWithAppleButton(
                        .signIn,
                        onRequest: configureAppleRequest,
                        onCompletion: handleAppleCompletion
                    )
                    .frame(height: 52)
                    .cornerRadius(16)

                    Spacer(minLength: 40)
                }
                .padding(.horizontal, 20)
            }
            .background(Color(.systemGroupedBackground))
            .navigationBarHidden(true)
            .fullScreenCover(isPresented: $isLoggedIn) {
                MainView()
            }
            .alert(
                String(localized: "email_not_verified_title"),
                isPresented: $showVerifyAlert
            ) {
                Button(String(localized: "ok"), role: .cancel) {}
            } message: {
                Text(String(localized: "email_not_verified_message"))
            }
            .alert(
                String(localized: "login_failed_title"),
                isPresented: .constant(errorMessage != nil)
            ) {
                Button(String(localized: "ok")) {
                    errorMessage = nil
                }
            } message: {
                Text(errorMessage ?? "")
            }



        }
        .navigationViewStyle(.stack)
    }



    // MARK: - EMAIL LOGIN
    private func login() {
        errorMessage = nil
        isLoading = true

        Auth.auth().signIn(withEmail: email, password: password) { _, error in
            if let error = error {
                DispatchQueue.main.async {
                    self.errorMessage = authErrorMessage(error)
                    self.isLoading = false
                }
                return
            }

            guard let user = Auth.auth().currentUser else {
                DispatchQueue.main.async {
                    self.isLoading = false
                }
                return
            }

            user.reload { _ in
                DispatchQueue.main.async {
                    self.isLoading = false

                    if !user.isEmailVerified {
                        self.showVerifyAlert = true
                        try? Auth.auth().signOut()
                        return
                    }

                    self.isLoggedIn = true
                }
            }
        }
    }

    private func resetPassword() {
        if email.isEmpty {
            errorMessage = String(localized: "enter_email_first")
            return
        }

        Auth.auth().sendPasswordReset(withEmail: email) { error in
            if let error = error {
                errorMessage = authErrorMessage(error)
                return
            }
            errorMessage = String(localized: "password_reset_sent")
        }
    }


    // MARK: - GOOGLE LOGIN
    private func signInWithGoogle() {
        guard let clientID = FirebaseApp.app()?.options.clientID else { return }
        let config = GIDConfiguration(clientID: clientID)
        GIDSignIn.sharedInstance.configuration = config
        
        // FIX CHO IPAD + IOS 15+
        guard
            let windowScene = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .first,
            let rootVC = windowScene
                .windows
                .first(where: { $0.isKeyWindow })?
                .rootViewController
        else {
            self.errorMessage = String(localized: "unable_to_find_root_view_controller")
            return
        }

        GIDSignIn.sharedInstance.signIn(withPresenting: rootVC) { result, error in
            
            if let error = error {
                self.errorMessage = authErrorMessage(error)
                return
            }
            
            guard
                let user = result?.user,
                let idToken = user.idToken?.tokenString
            else {
                self.errorMessage = String(localized: "error_google_failed")
                return
            }
            
            let credential = GoogleAuthProvider.credential(
                withIDToken: idToken,
                accessToken: user.accessToken.tokenString
            )
            
            Auth.auth().signIn(with: credential) { _, error in
                if let error = error {
                    self.errorMessage = authErrorMessage(error)
                } else {
                    self.isLoggedIn = true
                }
            }
        }
    }

    // MARK: - APPLE LOGIN
    private func configureAppleRequest(_ request: ASAuthorizationAppleIDRequest) {
        let nonce = randomNonceString()
        currentNonce = nonce
        request.requestedScopes = [.email, .fullName]
        request.nonce = sha256(nonce)
    }

    private func handleAppleCompletion(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .success(let auth):
            signInWithApple(auth)
        case .failure(let error):
            errorMessage = error.localizedDescription
        }
    }

    private func signInWithApple(_ authResults: ASAuthorization) {
        guard let credential = authResults.credential as? ASAuthorizationAppleIDCredential else {
            errorMessage = String(localized: "error_apple_failed")
            return
        }

        guard let nonce = currentNonce else {
            errorMessage = String(localized: "error_invalid_state_no_nonce")
            return
        }

        guard let tokenData = credential.identityToken,
              let tokenString = String(data: tokenData, encoding: .utf8) else {
            errorMessage = String(localized: "error_unable_fetch_identity_token")
            return
        }

        let firebaseCredential = OAuthProvider.appleCredential(
            withIDToken: tokenString,
            rawNonce: nonce,
            fullName: credential.fullName
        )

        Auth.auth().signIn(with: firebaseCredential) { _, error in
            if let error = error {
                self.errorMessage = authErrorMessage(error)
                return
            }
            self.isLoggedIn = true
        }
    }

    // MARK: - Nonce Utilities
    func sha256(_ input: String) -> String {
        let hashed = SHA256.hash(data: Data(input.utf8))
        return hashed.map { String(format: "%02x", $0) }.joined()
    }

    func randomNonceString(length: Int = 32) -> String {
        let charset = "0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz"
        return String((0..<length).compactMap { _ in charset.randomElement() })
    }
    private func authErrorMessage(_ error: Error) -> String {
        let nsError = error as NSError
        guard let code = AuthErrorCode(rawValue: nsError.code) else {
            return String(localized: "login_failed_generic")
        }

        switch code {
        case .wrongPassword:
            return String(localized: "error_wrong_password")

        case .userNotFound:
            return String(localized: "error_user_not_found")

        case .invalidEmail:
            return String(localized: "error_invalid_email")

        case .userDisabled:
            return String(localized: "error_user_disabled")

        case .invalidCredential, .credentialAlreadyInUse:
            return String(localized: "error_invalid_credentials")

        default:
            return String(localized: "login_failed_generic")
        }
    }

}


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


struct MainView: View {
    var body: some View {
        VStack(spacing: 20) {
            Text(String(localized: "welcome"))
                .font(.largeTitle)
                .bold()

            Button(String(localized:"logout")) {
                do {
                    try Auth.auth().signOut()
                }
                catch {
                    print(String(localized: "log_logout_error"), error.localizedDescription)
                }
            }
            .foregroundColor(.red)

            Spacer()
        }
        .padding()
    }
}
