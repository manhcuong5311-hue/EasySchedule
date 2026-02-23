import SwiftUI
import FirebaseAuth
import GoogleSignIn
import FirebaseCore
import AuthenticationServices
import CryptoKit



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
    @State private var showErrorAlert = false
    @State private var showEmailLogin = false
    
    @Environment(\.colorScheme) var colorScheme
    @State private var logoScale: CGFloat = 0.95
    
    @State private var taglineIndex = 0
    
    private let taglines = [
        String(localized: "plan.tagline.1"),
        String(localized: "plan.tagline.2"),
        String(localized: "plan.tagline.3")
    ]
    
    
    private func startTaglineAnimation() {
        Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { _ in
            withAnimation {
                taglineIndex = (taglineIndex + 1) % taglines.count
            }
        }
    }
    
    
    var body: some View {
        NavigationStack {
            ZStack {
                
                // 🌈 BACKGROUND CHUYỂN ĐỘNG
                AnimatedBackground()
                
                VStack(spacing: 28) {
                    
                    Spacer(minLength: 40)
                    
                    // Title
                    VStack(spacing: 10) {
                        
                        Text(String(localized: "auth.welcome_to"))
                            .font(.title3)
                            .foregroundStyle(.secondary)
                        
                        Text("Easy Schedule")
                            .font(.system(size: 36, weight: .bold))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [.blue, .cyan],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                        
                        Text(taglines[taglineIndex])
                            .font(.headline)
                            .foregroundStyle(.secondary)
                            .id(taglineIndex)
                            .transition(.opacity.combined(with: .move(edge: .bottom)))
                            .animation(.spring(response: 0.5, dampingFraction: 0.8), value: taglineIndex)
                            .onAppear {
                                startTaglineAnimation()
                            }
                    }
                    
                    // Ring + icon
                    ZStack {
                        CheckRingView()
                            .frame(width: 240, height: 240)
                        
                        Image("1")
                            .resizable()
                              .scaledToFit()
                              .frame(width: 90, height: 90)
                              .scaleEffect(logoScale)
                              .onAppear {
                                  withAnimation(
                                    .easeInOut(duration: 2)
                                    .repeatForever(autoreverses: true)
                                  ) {
                                      logoScale = 1.05
                                  }
                              }
                    }
                    .padding(.vertical, 16)
                    
                    Spacer()
                    
                    // Buttons (GIỮ NGUYÊN)
                    authButtons
                    
                    // Legal
                    Text(String(localized: "auth.agreement_text"))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                    
                    Spacer(minLength: 24)
                }
                .padding()
            }
            .navigationBarHidden(true)
        }
        .sheet(isPresented: $showEmailLogin) {
            EmailLoginSheet(
                email: $email,
                password: $password,
                isLoading: $isLoading,
                errorMessage: $errorMessage,
                loginAction: login,
                resetPasswordAction: resetPassword
            )
        }
        
    }
    
    
    
    private var authButtons: some View {
        VStack(spacing: 16) {
            
            // 🍎 Sign in with Apple
            SignInWithAppleButton(
                .signIn,
                onRequest: configureAppleRequest,
                onCompletion: handleAppleCompletion
            )
            .signInWithAppleButtonStyle(
                colorScheme == .dark ? .white : .black
            )
            .frame(height: 54)
            .clipShape(RoundedRectangle(cornerRadius: 18))
            
            // 🔵 Google
            Button(action: signInWithGoogle) {
                HStack(spacing: 12) {
                    Image("google_icon")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 20, height: 20)
                    
                    Text(String(localized: "auth.continue_google"))
                        .font(.system(size: 16, weight: .semibold))
                }
                .frame(maxWidth: .infinity, minHeight: 54)
                .background(Color(.systemBackground))
                .overlay(
                    RoundedRectangle(cornerRadius: 18)
                        .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                )
            }
            .foregroundStyle(.primary)
            
            // ✉️ Email
            Button {
                showEmailLogin = true
            } label: {
                Text(String(localized: "auth.continue_email"))
                
                    .font(.system(size: 16, weight: .semibold))
                    .frame(maxWidth: .infinity, minHeight: 54)
                    .overlay(
                        RoundedRectangle(cornerRadius: 18)
                            .stroke(Color.blue, lineWidth: 1.5)
                    )
            }
        }
    }
    
    // MARK: - EMAIL LOGIN
    private func login() {
        errorMessage = nil
        
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPassword = password.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // ✅ Validate trước khi gọi Firebase
        guard !trimmedEmail.isEmpty else {
            errorMessage = String(localized: "email_required")
            return
        }
        
        guard !trimmedPassword.isEmpty else {
            errorMessage = String(localized: "password_required")
            return
        }
        
        isLoading = true
        
        Auth.auth().signIn(withEmail: trimmedEmail, password: trimmedPassword) { _, error in
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
            
            // ✅ FIX Ở ĐÂY
            _ = [
                credential.fullName?.givenName,
                credential.fullName?.familyName
            ]
                .compactMap { $0 }
                .joined(separator: " ")
            
           
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


struct MainView: View {
    @Binding var isLoggedIn: Bool
    
    var body: some View {
        VStack(spacing: 20) {
            Text(String(localized: "welcome"))
                .font(.largeTitle)
                .bold()
            
            Button(String(localized: "logout")) {
                do {
                    try Auth.auth().signOut()
                    isLoggedIn = false   // ⭐ QUAN TRỌNG
                } catch {
                    print("Logout error:", error.localizedDescription)
                }
            }
            .foregroundColor(.red)
            
            Spacer()
        }
        .padding()
    }
}



struct EmailLoginSheet: View {
    
    @Binding var email: String
    @Binding var password: String
    @Binding var isLoading: Bool
    @Binding var errorMessage: String?
    
    let loginAction: () -> Void
    let resetPasswordAction: () -> Void
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                
                Text(String(localized: "auth.signin_email"))
                    .font(.title2.bold())
                
                TextField(String(localized: "auth.email"), text: $email)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .padding()
                    .background(.ultraThinMaterial)
                    .cornerRadius(14)
                
                SecureField(String(localized: "auth.password"), text: $password)
                    .padding()
                    .background(.ultraThinMaterial)
                    .cornerRadius(14)
                
                if let error = errorMessage {
                    Text(error)
                        .foregroundStyle(.red)
                        .font(.caption)
                }
                
                Button(String(localized: "auth.login"), action: loginAction)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(Color.blue)
                    .foregroundStyle(.white)
                    .cornerRadius(16)
                    .disabled(isLoading)
                
                Button(String(localized: "auth.forgot_password")) {
                    resetPasswordAction()
                }
                .font(.footnote)
                .foregroundStyle(.blue)
                
                Spacer()
            }
            .padding()
        }
    }
}

struct CheckRingView: View {
    
    @State private var rotation: Double = 0
    @State private var scale: CGFloat = 0.9
    
    var body: some View {
        ZStack {
            
            // Outer rotating ring
            Circle()
                .trim(from: 0.1, to: 0.9)
                .stroke(
                    LinearGradient(
                        colors: [.blue, .cyan],
                        startPoint: .leading,
                        endPoint: .trailing
                    ),
                    style: StrokeStyle(lineWidth: 14, lineCap: .round)
                )
                .frame(width: 220, height: 220)
                .rotationEffect(.degrees(rotation))
            
            // Inner subtle ring
            Circle()
                .stroke(Color.white.opacity(0.2), lineWidth: 1)
                .frame(width: 170, height: 170)
            
        }
        .onAppear {
            withAnimation(
                .linear(duration: 14)
                .repeatForever(autoreverses: false)
            ) {
                rotation = 360
            }
            
            withAnimation(
                .easeInOut(duration: 1.8)
                .repeatForever(autoreverses: true)
            ) {
                scale = 1.05
            }
        }
    }
}

struct AnimatedBackground: View {
    
    @State private var animate = false
    
    var body: some View {
        LinearGradient(
            colors: [
                Color.blue.opacity(0.3),
                Color.indigo.opacity(0.25),
                Color.cyan.opacity(0.25)
            ],
            startPoint: animate ? .topLeading : .bottomTrailing,
            endPoint: animate ? .bottomTrailing : .topLeading
        )
        .ignoresSafeArea()
        .onAppear {
            withAnimation(
                .easeInOut(duration: 10)
                .repeatForever(autoreverses: true)
            ) {
                animate.toggle()
            }
        }
    }
}













