//
//  LoginView.swift
//  Easy Schedule
//
//  Created by Sam Manh Cuong on 12/11/25.
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
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                
                Text(String(localized: "login"))
                    .font(.largeTitle)
                    .bold()
                
                TextField("Email", text: $email)
                    .keyboardType(.emailAddress)
                    .autocapitalization(.none)
                    .padding()
                    .background(Color.gray.opacity(0.2))
                    .cornerRadius(8)
                
                SecureField(String(localized: "password"), text: $password)
                    .padding()
                    .background(Color.gray.opacity(0.2))
                    .cornerRadius(8)
                
                if let error = errorMessage {
                    Text(error)
                        .foregroundColor(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                
                Button(action: { login() }) {
                    Text(String(localized: "login"))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .cornerRadius(8)
                }

                
                Button(action: { signUp() }) {
                    Text(String(localized: "signup"))
                        .foregroundColor(.blue)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.blue, lineWidth: 2)
                        )
                }

                
                // 🔹 Nút đăng nhập bằng Google
                Button(action: { signInWithGoogle() }) {
                    HStack {
                        Image(systemName: "globe")
                        Text(String(localized: "login_with_google"))
                            .fontWeight(.semibold)
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
    
    // MARK: - Functions
    
    private func login() {
        errorMessage = nil
        Auth.auth().signIn(withEmail: email, password: password) { result, error in
            if let error = error {
                errorMessage = error.localizedDescription
            } else {
                print("✅ Người dùng đã đăng nhập: \(result?.user.uid ?? "")")
                isLoggedIn = true
            }
        }
    }
    
    private func signUp() {
        errorMessage = nil
        Auth.auth().createUser(withEmail: email, password: password) { result, error in
            if let error = error {
                errorMessage = error.localizedDescription
            } else {
                print("✅ Đã tạo tài khoản mới: \(result?.user.uid ?? "")")
                isLoggedIn = true
            }
        }
    }
    
    // MARK: - Google Sign-In
    private func signInWithGoogle() {
        guard let clientID = FirebaseApp.app()?.options.clientID else { return }
        
        // Cấu hình Google
        let config = GIDConfiguration(clientID: clientID)
        GIDSignIn.sharedInstance.configuration = config
        
        // Lấy rootViewController để hiển thị màn hình Google
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let rootVC = windowScene.windows.first?.rootViewController else {
            print("❌ No root view controller")
            return
        }
        
        // Bắt đầu đăng nhập
        GIDSignIn.sharedInstance.signIn(withPresenting: rootVC) { result, error in
            if let error = error {
                self.errorMessage = error.localizedDescription
                return
            }
            
            guard
                let user = result?.user,
                let idToken = user.idToken?.tokenString
            else {
                self.errorMessage = String(localized: "google_login_failed")
                return
            }
            
            let credential = GoogleAuthProvider.credential(
                withIDToken: idToken,
                accessToken: user.accessToken.tokenString
            )
            
            Auth.auth().signIn(with: credential) { result, error in
                if let error = error {
                    self.errorMessage = error.localizedDescription
                    return
                }
                print("✅ Đăng nhập bằng Google thành công: \(result?.user.email ?? "")")
                self.isLoggedIn = true
            }
        }
    }
}

// MARK: - MainView
struct MainView: View {
    var body: some View {
        VStack {
            Text(String(localized: "welcome_logged_in"))
                .font(.title)
                .padding()
            Button(String(localized: "logout")) {
                do {
                    try Auth.auth().signOut()
                } catch {
                    print("❌ Lỗi đăng xuất: \(error)")
                }
            }
        }
    }
}

struct LoginView_Previews: PreviewProvider {
    static var previews: some View {
        LoginView()
    }
}
