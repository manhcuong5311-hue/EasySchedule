//
//  LoginView.swift
//  Easy Schedule
//

import SwiftUI
import FirebaseAuth
import GoogleSignIn
import FirebaseCore

struct LoginView: View {
    @State private var email: String = ""
    @State private var password: String = ""
    @State private var errorMessage: String?
    @State private var isLoggedIn: Bool = false
    @State private var showSignUp: Bool = false
    @State private var emailWarning: String?

    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                
                Text("Login")
                    .font(.largeTitle)
                    .bold()
                
                // Email
                TextField("Email", text: $email)
                    .keyboardType(.emailAddress)
                    .autocapitalization(.none)
                    .padding()
                    .background(Color.gray.opacity(0.2))
                    .cornerRadius(8)

                // Password
                SecureField("Password", text: $password)
                    .padding()
                    .background(Color.gray.opacity(0.2))
                    .cornerRadius(8)

                // Error messages
                if let err = errorMessage {
                    Text(err)
                        .foregroundColor(.red)
                        .multilineTextAlignment(.center)
                }
                
                // Email verify warning (OPTION 3)
                if let warn = emailWarning {
                    Text(warn)
                        .foregroundColor(.yellow)
                        .font(.caption)
                        .multilineTextAlignment(.center)
                }
                
                // Login Button
                Button(action: login) {
                    Text("Login")
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .cornerRadius(8)
                }

                // Sign Up Button → mở SignUpView
                Button(action: { showSignUp = true }) {
                    Text("Sign Up")
                        .foregroundColor(.blue)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.blue, lineWidth: 2)
                        )
                }
                .sheet(isPresented: $showSignUp) {
                    SignUpView()
                }

                // Google Login
                Button(action: signInWithGoogle) {
                    HStack {
                        Image(systemName: "globe")
                        Text("Login with Google")
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.red)
                    .cornerRadius(8)
                }

                Spacer()
            }
            .padding()
            .navigationBarHidden(true)
            .fullScreenCover(isPresented: $isLoggedIn) {
                MainView()
            }
        }
    }
    
    
    // MARK: - EMAIL LOGIN (OPTION 3 LOGIC)
    private func login() {
        errorMessage = nil
        emailWarning = nil
        
        Auth.auth().signIn(withEmail: email, password: password) { result, error in
            
            if let error = error {
                errorMessage = error.localizedDescription
                return
            }
            
            guard let user = result?.user else { return }
            
            // OPTION 3: KHÔNG CHẶN LOGIN, CHỈ CẢNH BÁO
            if !user.isEmailVerified {
                emailWarning = "Email của bạn chưa xác minh — một số tính năng có thể bị hạn chế."
            }
            
            isLoggedIn = true
        }
    }
    
    
    // MARK: - GOOGLE SIGN-IN
    private func signInWithGoogle() {
        guard let clientID = FirebaseApp.app()?.options.clientID else { return }
        
        let config = GIDConfiguration(clientID: clientID)
        GIDSignIn.sharedInstance.configuration = config
        
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let rootVC = scene.windows.first?.rootViewController else { return }
        
        GIDSignIn.sharedInstance.signIn(withPresenting: rootVC) { result, error in
            
            if let error = error {
                self.errorMessage = error.localizedDescription
                return
            }
            
            guard let user = result?.user,
                  let idToken = user.idToken?.tokenString else {
                self.errorMessage = "Google authentication failed"
                return
            }
            
            let credential = GoogleAuthProvider.credential(
                withIDToken: idToken,
                accessToken: user.accessToken.tokenString
            )
            
            Auth.auth().signIn(with: credential) { res, error in
                if let error = error {
                    self.errorMessage = error.localizedDescription
                } else {
                    self.isLoggedIn = true
                }
            }
        }
    }
}


// MARK: - MAIN VIEW
struct MainView: View {
    var body: some View {
        VStack {
            Text("Welcome!")
                .font(.title)
                .padding()
            
            Button("Logout") {
                do { try Auth.auth().signOut() }
                catch { print("❌ Lỗi đăng xuất: \(error)") }
            }
        }
    }
}

#Preview {
    LoginView()
}

struct SignUpView: View {
    @Environment(\.dismiss) var dismiss

    @State private var email = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var errorMessage: String?
    @State private var isLoading = false
    @State private var showSuccessMessage = false

    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                
                Text("Create Account")
                    .font(.largeTitle)
                    .bold()
                
                TextField("Email", text: $email)
                    .keyboardType(.emailAddress)
                    .autocapitalization(.none)
                    .padding()
                    .background(Color.gray.opacity(0.2))
                    .cornerRadius(8)

                SecureField("Password", text: $password)
                    .padding()
                    .background(Color.gray.opacity(0.2))
                    .cornerRadius(8)

                SecureField("Confirm Password", text: $confirmPassword)
                    .padding()
                    .background(Color.gray.opacity(0.2))
                    .cornerRadius(8)
                
                if let err = errorMessage {
                    Text(err)
                        .foregroundColor(.red)
                }
                
                if isLoading {
                    ProgressView("Đang tạo tài khoản...")
                }

                Button(action: validateAndSignUp) {
                    Text("Sign Up")
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .cornerRadius(8)
                }

                Spacer()
            }
            .padding()
            .alert("Tạo tài khoản thành công!", isPresented: $showSuccessMessage) {
                Button("OK") { dismiss() }
            } message: {
                Text("Vui lòng kiểm tra email để xác thực trước khi đăng nhập.")
            }
        }
    }
    
    private func validateAndSignUp() {
        errorMessage = nil
        
        if !email.contains("@") {
            errorMessage = "Email không hợp lệ."
            return
        }
        
        if password.count < 6 {
            errorMessage = "Mật khẩu phải ít nhất 6 ký tự."
            return
        }
        
        if password != confirmPassword {
            errorMessage = "Mật khẩu xác nhận không khớp."
            return
        }
        
        createAccount()
    }
    
    private func createAccount() {
        isLoading = true
        
        Auth.auth().createUser(withEmail: email, password: password) { result, error in
            isLoading = false
            
            if let error = error {
                errorMessage = error.localizedDescription
                return
            }
            
            result?.user.sendEmailVerification { err in
                if let err = err {
                    errorMessage = err.localizedDescription
                } else {
                    showSuccessMessage = true
                }
            }
        }
    }
}
