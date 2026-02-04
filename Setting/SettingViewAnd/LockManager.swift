//
//  LockManager.swift
//  Easy Schedule
//
//  Created by Sam Manh Cuong on 4/2/26.
//
import SwiftUI
import Combine
import LocalAuthentication

// MARK: - Security View

struct SecuritySettingsView: View {
    // MARK: - AppStorage để lưu trạng thái
    @AppStorage("useBiometricAuth") private var useBiometricAuth = false
    @AppStorage("autoLockEnabled") private var autoLockEnabled = false
    @Environment(\.scenePhase) private var scenePhase

    // MARK: - State
    @State private var showAuthError = false
    @ObservedObject private var lockManager = LockManager.shared
    
    var body: some View {
        ZStack {
            Form {
                Section(String(localized: "security_account")) {
                    // Face ID / Touch ID Toggle
                    Toggle(String(localized: "security_biometric"), isOn: Binding(
                        get: { useBiometricAuth },
                        set: { newValue in
                            if newValue {
                                authenticateUser()
                            } else {
                                useBiometricAuth = false
                            }
                        }
                    ))
                    .alert(String(localized: "security_biometric_fail"), isPresented: $showAuthError) {
                        Button(String(localized:"ok"), role: .cancel) {}
                    }
                    
                    // Auto Lock Toggle
                    Toggle(String(localized: "security_auto_lock"), isOn: $autoLockEnabled)
                }
            }
            .navigationTitle(String(localized: "security_nav"))
            .onTapGesture {
                lockManager.userDidInteract()
            }
            
            // Overlay màn hình khóa nếu bị khóa
            if lockManager.isLocked {
                LockScreenView()
            }
        }
        .onAppear {
            lockManager.startTimer()
        }
        .onChange(of: scenePhase) { oldPhase, newPhase in
            if newPhase != .active {
                lockManager.lock()
            }
        }


    }
    
    // MARK: - Face ID / Touch ID xác thực
    private func authenticateUser() {
        guard !lockManager.isAuthenticating else { return }
        lockManager.isAuthenticating = true

        let context = LAContext()
        var error: NSError?

        if context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) {
            let reason = String(localized: "security_reason")
            context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics,
                                   localizedReason: reason) { success, _ in
                DispatchQueue.main.async {
                    self.lockManager.isAuthenticating = false

                    if success {
                        self.useBiometricAuth = true
                    } else {
                        self.useBiometricAuth = false
                        self.showAuthError = true
                    }
                }
            }
        } else {
            lockManager.isAuthenticating = false
            showAuthError = true
        }
    }

}


// MARK: - Lock Manager
class LockManager: ObservableObject {
    static let shared = LockManager()
    @Published var isAuthenticating = false

    @Published var isLocked = false
    private var lastInteractionTime = Date()
    private var timer: Timer?
    
    private init() { }
    
    private var isTimerRunning = false

    func startTimer() {
        guard !isTimerRunning else { return }
        isTimerRunning = true

        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { _ in
            self.checkForInactivity()
        }
    }
    func stopTimer() {
        timer?.invalidate()
        timer = nil
        isTimerRunning = false
    }

    
    func userDidInteract() {
        lastInteractionTime = Date()
    }
    
    private func checkForInactivity() {
        let timeout: TimeInterval = 60 // thời gian tự động khóa (giây)
        if Date().timeIntervalSince(lastInteractionTime) > timeout,
           UserDefaults.standard.bool(forKey: "autoLockEnabled") {
            DispatchQueue.main.async {
                self.lock()
            }
        }
    }
    
    func lock() {
        guard !isAuthenticating else { return }

        if UserDefaults.standard.bool(forKey: "useBiometricAuth") {
            isLocked = true
        }
    }

    
    func unlock() {
        guard !isAuthenticating else { return }
        guard UIApplication.shared.applicationState == .active else { return }

        isAuthenticating = true

        let context = LAContext()
        let reason = String(localized: "unlock_reason")

        context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics,
                               localizedReason: reason) { success, _ in
            DispatchQueue.main.async {
                self.isAuthenticating = false

                if success {
                    self.isLocked = false
                    self.lastInteractionTime = Date()
                }
            }
        }
    }


}




