//
//  SETTING.swift
//  Easy schedule
//
//  Created by Sam Manh Cuong on 11/11/25.
//
import SwiftUI
import UserNotifications
import Combine
import FirebaseCore
import FirebaseAuth
import GoogleSignIn
import LocalAuthentication
import UIKit
import FirebaseFirestore
import FirebaseFunctions
import FirebaseMessaging

struct PushPreferenceManager {

    static func enablePush() {
        guard let uid = Auth.auth().currentUser?.uid else { return }

        Messaging.messaging().token { token, _ in
            guard let token else { return }

            Firestore.firestore()
                .collection("users")
                .document(uid)
                .setData([
                    "notificationTokens": FieldValue.arrayUnion([token])
                ], merge: true)
        }
    }

    static func disablePush() {
        guard let uid = Auth.auth().currentUser?.uid else { return }

        Messaging.messaging().token { token, _ in
            guard let token else { return }

            Firestore.firestore()
                .collection("users")
                .document(uid)
                .updateData([
                    "notificationTokens": FieldValue.arrayRemove([token])
                ])
        }
    }
}

final class NotificationManager: ObservableObject {
    static let shared = NotificationManager()
    @Published var notificationsEnabled = false
    @Published var leadTime: Int = 15 // phút trước khi nhắc
 
    func requestPermission(completion: @escaping (Bool) -> Void) {
        UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in

                DispatchQueue.main.async {
                    self.notificationsEnabled = granted
                    UserDefaults.standard.set(granted, forKey: "notificationsEnabled")
                    completion(granted)
                }

                if let error = error {
                    print("❌ Lỗi xin quyền thông báo: \(error.localizedDescription)")
                }
            }
    }

    
    func scheduleNotification(for event: CalendarEvent, leadTime: Int = 15) {
        let enabled = UserDefaults.standard.bool(
            forKey: "pushNotificationsEnabled"
        )
        guard enabled else { return }

        let content = UNMutableNotificationContent()
        content.title = event.title
        content.body = String(
            format: String(localized: "upcoming_event_message"),
            event.title
        )
        content.sound = .default

        let triggerDate =
            Calendar.current.date(
                byAdding: .minute,
                value: -leadTime,
                to: event.startTime
            ) ?? event.startTime

        let interval = max(triggerDate.timeIntervalSinceNow, 5)

        let request = UNNotificationRequest(
            identifier: event.id,
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(
                timeInterval: interval,
                repeats: false
            )
        )

        UNUserNotificationCenter.current().add(request)
    }


}

// MARK: - SettingsView

struct SettingsView: View {
    // MARK: - AppStorage
    @AppStorage("notificationsEnabled") private var notificationsEnabled = false
    @AppStorage("leadTime") private var leadTime = 15
    @AppStorage("selectedLanguage") private var selectedLanguage = "vi"
    @AppStorage("pushNotificationsEnabled")
    private var pushNotificationsEnabled = false
    @AppStorage("appTheme") private var appTheme: String = "system"
    @State private var isDeletingAccount = false
    @State private var isDeleting = false

    // MARK: - State
    @State private var showLogoutAlert = false
    @State private var showPrivacySheet = false
    @State private var showUpgradeSheet = false

    // MARK: - Environment Objects
    @EnvironmentObject var session: SessionStore
    @EnvironmentObject var premium: PremiumStoreViewModel
    @State private var didFinishInitialLoad = false
    @State private var showNotificationSettingsAlert = false

    // MARK: - Constants
    let leadTimeOptions = [5, 10, 15, 30, 60]
    let appVersion = "1.0.0"

    var body: some View {
        NavigationStack {
            Form {
                // 🔥 PREMIUM / PRO BANNER (TOP)
                if premium.isLoaded && premium.tier != .pro {
                    Section {
                        SettingsPremiumBanner()
                            .environmentObject(premium)
                            .listRowInsets(EdgeInsets())          // FULL WIDTH
                            .listRowBackground(Color.clear)       // BỎ BACKGROUND CELL
                    }
                }

                // MARK: - 🔔 Notifications
                Section {
                    Toggle(isOn: $pushNotificationsEnabled) {
                        Label(String(localized: "notify_before_event"), systemImage: "bell.fill")
                    }
                    .onChange(of: pushNotificationsEnabled) { _, enabled in
                        guard didFinishInitialLoad else { return }

                        if enabled {
                            UNUserNotificationCenter.current().getNotificationSettings { settings in
                                DispatchQueue.main.async {
                                    switch settings.authorizationStatus {

                                    case .authorized:
                                        UIApplication.shared.registerForRemoteNotifications()
                                        PushPreferenceManager.enablePush()

                                        EventManager.shared.rescheduleLocalNotifications()


                                    case .notDetermined:
                                        NotificationManager.shared.requestPermission { granted in
                                            DispatchQueue.main.async {
                                                if granted {
                                                    UIApplication.shared.registerForRemoteNotifications()
                                                    PushPreferenceManager.enablePush()

                                                    EventManager.shared.rescheduleLocalNotifications()
                                                

                                                } else {
                                                    pushNotificationsEnabled = false
                                                }
                                            }
                                        }

                                    case .denied:
                                        // 🚨 CASE USER ĐÃ TỪ CHỐI TRƯỚC ĐÓ
                                        pushNotificationsEnabled = false
                                        showNotificationSettingsAlert = true

                                    default:
                                        pushNotificationsEnabled = false
                                    }
                                }
                            }
                        } else {
                            PushPreferenceManager.disablePush()
                        }
                    }




                    Picker(selection: $leadTime) {
                        ForEach(leadTimeOptions, id: \.self) { value in
                            let t = String(localized: "minutes_before")
                            Text(t.replacingOccurrences(of: "{value}", with: "\(value)"))
                                .tag(value)
                        }
                    } label: {
                        Label(String(localized: "remind_before"), systemImage: "clock")
                    }
                    .disabled(!pushNotificationsEnabled)

                } header: {
                    Text(String(localized: "notifications"))
                }


                // MARK: - 🎨 Appearance
                Section {
                    Picker(selection: $appTheme) {
                        Text(String(localized: "system")).tag("system")
                        Text(String(localized: "light")).tag("light")
                        Text(String(localized: "dark")).tag("dark")
                    } label: {
                        Label(String(localized: "display_mode"), systemImage: "circle.lefthalf.filled")
                    }
                    .pickerStyle(.segmented)
                } header: {
                    Text(String(localized: "appearance"))
                }


                // MARK: - 👤 Account & Premium
                Section {
                    HStack {
                        Label(String(localized: "display_name"), systemImage: "person.fill")
                        Spacer()
                        Text(session.currentUserName.isEmpty
                             ? String(localized: "not_set")
                             : session.currentUserName)
                            .foregroundColor(.secondary)
                    }

                    NavigationLink {
                        UpdateUserNameView().environmentObject(session)
                    } label: {
                        Label(String(localized: "change_display_name"), systemImage: "pencil")
                    }
                    Button {
                        showUpgradeSheet = true
                    } label: {
                        HStack {
                            Label(
                                premium.tier == .free
                                ? String(localized: "upgrade_account")
                                : premium.tier == .pro
                                    ? String(localized: "pro_active")
                                    : String(localized: "premium_active"),
                                systemImage: premium.tier == .pro
                                    ? "crown.fill"
                                    : "star.fill"
                            )

                            Spacer()

                            Text(
                                premium.tier == .free
                                ? String(localized: "free")
                                : premium.tier == .pro
                                    ? String(localized: "pro")
                                    : String(localized: "premium")
                            )
                            .font(.caption)
                            .foregroundColor(.secondary)
                        }
                    }

                    NavigationLink {
                        SecuritySettingsView()
                    } label: {
                        Label(String(localized: "security_management"), systemImage: "lock.shield")
                    }

                } header: {
                    Text(String(localized: "account_and_premium"))
                }


                // MARK: - 🌐 Language
                Section {
                    Button {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    } label: {
                        Label(String(localized: "change_language_in_settings"), systemImage: "globe")
                    }
                } header: {
                    Text(String(localized: "language"))
                }


                // MARK: - 🛟 Support
                Section {
                    // ▶ View onboarding (NEW)
                    Button {
                        UserDefaults.standard.set(false, forKey: "hasSeenOnboarding")
                    } label: {
                        Label(
                            String(localized: "view_onboarding"),
                            systemImage: "rectangle.on.rectangle"
                        )
                    }

                    Button {
                        showPrivacySheet = true
                    } label: {
                        Label(
                            String(localized: "privacy_policy_and_info"),
                            systemImage: "doc.text"
                        )
                    }

                    Button {
                        contactSupport()
                    } label: {
                        Label(
                            String(localized: "contact_support"),
                            systemImage: "envelope"
                        )
                    }

                    NavigationLink {
                        FAQView()
                    } label: {
                        Label(
                            String(localized: "faq"),
                            systemImage: "questionmark.circle"
                        )
                    }

                } header: {
                    Text(String(localized: "info_support"))
                }



                // MARK: - ⚙️ Account Actions
                Section {
                    NavigationLink {
                        AccountSettingsView().environmentObject(session)
                    } label: {
                        Label(String(localized: "account_management"), systemImage: "person.crop.circle")
                    }
                } header: {
                    Text(String(localized: "account_section"))
                }

            }
            .navigationTitle(String(localized: "settings"))
            .onAppear {
                DispatchQueue.main.async {
                    didFinishInitialLoad = true
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .OpenPaywall)) { _ in
                showUpgradeSheet = true
            }
            .onChange(of: leadTime) { _, _ in
                EventManager.shared.rescheduleLocalNotifications()
            }
            .onChange(of: pushNotificationsEnabled) { _, enabled in
                if enabled {
                    EventManager.shared.rescheduleLocalNotifications()
                } else {
                    UNUserNotificationCenter.current()
                        .removeAllPendingNotificationRequests()
                }
            }

            .alert(
                String(localized: "notifications_disabled_title"),
                isPresented: $showNotificationSettingsAlert
            ) {
                Button(String(localized: "open_settings")) {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                Button(String(localized: "cancel"), role: .cancel) {}
            } message: {
                Text(String(localized: "notifications_disabled_message"))
            }

            // ALERTS & SHEETS
            .alert(
                String(localized: "logout_confirm"),
                isPresented: $showLogoutAlert
            ) {
                Button(String(localized: "cancel"), role: .cancel) {}
                Button(String(localized: "logout"), role: .destructive) {
                    performLogout()
                }
            } message: {
                Text(String(localized: "logout_message"))
            }

            .sheet(isPresented: $showUpgradeSheet) {
                PremiumUpgradeSheet()
            }

            .sheet(isPresented: $showPrivacySheet) {
                PrivacyPolicyView()
            }
        }
    }



    // MARK: - Actions
    private func contactSupport() {
        let supportEmail = "easyschedulehelp@gmail.com"
        let subjectText = String(localized: "support_email_subject")
        let subject = subjectText.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        if let url = URL(string: "mailto:\(supportEmail)?subject=\(subject)") {
            UIApplication.shared.open(url)
        }
    }

    private func performLogout() {
        // 1️⃣ Reset UI / AppStorage state trước (tránh auto-trigger)
        UserDefaults.standard.removeObject(forKey: "pushNotificationsEnabled")
        UserDefaults.standard.removeObject(forKey: "notificationsEnabled")

        // 2️⃣ Clean push token cho user hiện tại
        Messaging.messaging().token { token, _ in
            if let token,
               let uid = Auth.auth().currentUser?.uid {

                Firestore.firestore()
                    .collection("users")
                    .document(uid)
                    .updateData([
                        "notificationTokens": FieldValue.arrayRemove([token])
                    ])
            }
        }

        // 3️⃣ Sign out Firebase
        do {
            try Auth.auth().signOut()

            // 4️⃣ Reset session local
            session.currentUser = nil

            print("✅ Đăng xuất Firebase thành công (SettingsView).")
        } catch let error {
            print("❌ Lỗi khi đăng xuất: \(error.localizedDescription)")
        }
    }

}





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

// MARK: - Lock Screen View
struct LockScreenView: View {
    @ObservedObject var lockManager = LockManager.shared

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "lock.fill")
                .font(.system(size: 60))
                .foregroundColor(.blue)

            Text(String(localized: "app_locked"))
                .font(.title3)
                .bold()

            Button(String(localized: "unlock_button")) {
                lockManager.unlock()
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
        .ignoresSafeArea()   // 👈 BẮT BUỘC
    }
}



final class NotificationRouter {
    static let shared = NotificationRouter()
    private init() {}

    func handle(type: String, eventId: String) {
        switch type {
        case "chat":
            openChat(eventId: eventId)

        case "event":
            openEvent(eventId: eventId)

        default:
            break
        }
    }

    private func openChat(eventId: String) {
        // Lưu tạm eventId để RootView đọc
        UserDefaults.standard.set(eventId, forKey: "pendingChatEventId")
    }

    private func openEvent(eventId: String) {
        UserDefaults.standard.set(eventId, forKey: "pendingEventId")
    }
    func handleAccessRequest() {
        UserDefaults.standard.set(true, forKey: "pendingAccessRequest")
    }

}
