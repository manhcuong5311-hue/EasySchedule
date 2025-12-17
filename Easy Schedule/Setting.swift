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
import UserNotifications
import FirebaseFunctions

final class NotificationManager: ObservableObject {
    static let shared = NotificationManager()
    @Published var notificationsEnabled = false
    @Published var leadTime: Int = 15 // phút trước khi nhắc
    @AppStorage("firebasePushEnabled") private var firebasePushEnabled = true

    
    
    
    func requestPermission() {
        UserNotifications.UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            DispatchQueue.main.async {
                self.notificationsEnabled = granted
            }
            if let error = error {
                print("❌ Lỗi xin quyền thông báo: \(error.localizedDescription)")
            }
        }
    }
    
    func scheduleNotification(for event: CalendarEvent, leadTime: Int = 15) {
        guard notificationsEnabled else { return }

        let content = UNMutableNotificationContent()
        content.title = event.title
        content.body = String(localized: "upcoming_event_message") + event.title
        content.sound = .default

        let triggerDate = Calendar.current.date(byAdding: .minute, value: -leadTime, to: event.startTime) ?? event.startTime
        let interval = max(triggerDate.timeIntervalSinceNow, 5)

        let request = UNNotificationRequest(
            identifier: event.id,   // <<< DÙNG EVENT ID LÀ IDENTIFIER
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
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
    @AppStorage("pushNotificationsEnabled") private var pushNotificationsEnabled = true
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
    @AppStorage("firebasePushEnabled") private var firebasePushEnabled = true


    // MARK: - Constants
    let leadTimeOptions = [5, 10, 15, 30, 60]
    let appVersion = "1.0.0"

    var body: some View {
        NavigationStack {
            Form {

                // MARK: - 🔔 Notifications
                Section {
                    Toggle(isOn: $pushNotificationsEnabled) {
                        Label(String(localized: "notify_before_event"), systemImage: "bell.fill")
                    }
                    .onChange(of: pushNotificationsEnabled) { _, newValue in
                        if newValue { NotificationManager.shared.requestPermission() }
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
                        HStack(spacing: 12) {

                            Image(systemName: "star.fill")
                                .foregroundColor(
                                    premium.isPremium
                                    ? AppColors.premiumGold
                                    : .secondary
                                )

                            Text(
                                premium.isPremium
                                ? String(localized: "premium_active")
                                : String(localized: "upgrade_account")
                            )
                            .fontWeight(.medium)

                            Spacer()

                            if premium.isPremium {
                                Text(String(localized: "premium"))
                                    .font(.caption)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(
                                        AppColors.premiumGold.opacity(0.2)
                                    )
                                    .foregroundColor(AppColors.premiumGold)
                                    .clipShape(Capsule())
                            } else {
                                Text(String(localized: "free"))
                                    .foregroundColor(.secondary)
                                    .font(.subheadline)
                            }
                        }
                        .padding(.vertical, 4)
                        .contentShape(Rectangle())
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
                    Button {
                        showPrivacySheet = true
                    } label: {
                        Label("Privacy Policy & App Info", systemImage: "doc.text")
                    }

                    Button {
                        contactSupport()
                    } label: {
                        Label(String(localized: "contact_support"), systemImage: "envelope")
                    }

                    NavigationLink {
                        FAQView()
                    } label: {
                        Label("FAQ", systemImage: "questionmark.circle")
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
        let supportEmail = "Manhcuong5311@gmail.com"
        let subjectText = String(localized: "support_email_subject")
        let subject = subjectText.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        if let url = URL(string: "mailto:\(supportEmail)?subject=\(subject)") {
            UIApplication.shared.open(url)
        }
    }

    private func performLogout() {
        do {
            try Auth.auth().signOut()
            session.currentUser = nil
            print("✅ Đăng xuất Firebase thành công (SettingsView).")
        } catch let error {
            print("❌ Lỗi khi đăng xuất: \(error.localizedDescription)")
        }
    }
}



struct FAQView: View {

    @State private var expandedSection: String? = nil

    var body: some View {
        List {

            FAQSectionView(
                id: "sharing",
                titleKey: "faq_section_sharing",
                questions: [
                    ("faq_1_q", "faq_1_a"),
                    ("faq_2_q", "faq_2_a"),
                    ("faq_3_q", "faq_3_a"),
                    ("faq_8_q", "faq_8_a")
                ],
                expandedSection: $expandedSection
            )

            FAQSectionView(
                id: "limits",
                titleKey: "faq_section_limits",
                questions: [
                    ("faq_4_q", "faq_4_a"),
                    ("faq_5_q", "faq_5_a"),
                    ("faq_6_q", "faq_6_a"),

                    // ⭐ NEW — Chat limit
                    ("faq_chat_limit_q", "faq_chat_limit_a"),

                    // ⭐ NEW — Todo limit
                    ("faq_todo_limit_q", "faq_todo_limit_a")
                ],
                expandedSection: $expandedSection
            )


            FAQSectionView(
                id: "notifications",
                titleKey: "faq_section_notifications",
                questions: [
                    ("faq_7_q", "faq_7_a")
                ],
                expandedSection: $expandedSection
            )
        }
        .navigationTitle("FAQ")
    }
}
struct FAQSectionView: View {
    let id: String
    let titleKey: String
    let questions: [(String, String)]

    @Binding var expandedSection: String?

    var body: some View {
        Section {
            Button {
                withAnimation(.easeInOut) {
                    expandedSection = expandedSection == id ? nil : id
                }
            } label: {
                HStack {
                    Text(LocalizedStringKey(titleKey))
                        .font(.headline)

                    Spacer()

                    Image(systemName: expandedSection == id ? "chevron.down" : "chevron.right")
                        .foregroundColor(.secondary)
                }
                .contentShape(Rectangle())
            }

            if expandedSection == id {
                ForEach(questions, id: \.0) { q, a in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(LocalizedStringKey(q))
                            .font(.subheadline)
                            .bold()

                        Text(LocalizedStringKey(a))
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }
}

struct FAQItem: View {
    let qKey: String
    let aKey: String

    init(_ q: String, _ a: String) {
        self.qKey = q
        self.aKey = a
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(LocalizedStringKey(qKey))
                .font(.headline)

            Text(LocalizedStringKey(aKey))
                .font(.body)
                .foregroundColor(.secondary)
        }
    }
}




// MARK: - Privacy Policy View
struct PrivacyPolicyView: View {
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(String(localized: "privacy_title"))
                        .font(.headline)
                    Text(String(localized: "privacy_text"))
                        .font(.body)
                    Link("Website 🧾 Privacy Policy & App Info", destination: URL(string: "https://manhcuong5311-hue.github.io/easyschedule-privacy/")!)
                }
                .padding()
            }
            .navigationTitle(String(localized: "privacy_nav_title"))
        }
    }
}





// MARK: - Security View

struct SecuritySettingsView: View {
    // MARK: - AppStorage để lưu trạng thái
    @AppStorage("useBiometricAuth") private var useBiometricAuth = false
    @AppStorage("autoLockEnabled") private var autoLockEnabled = false
    
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
                        Button("OK", role: .cancel) {}
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
    }
    
    // MARK: - Face ID / Touch ID xác thực
    private func authenticateUser() {
        let context = LAContext()
        var error: NSError?
        
        if context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) {
            let reason = String(localized: "security_reason")
            context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: reason) { success, _ in
                DispatchQueue.main.async {
                    if success {
                        useBiometricAuth = true
                    } else {
                        showAuthError = true
                    }
                }
            }
        } else {
            showAuthError = true
        }
    }
}

// MARK: - Lock Manager
class LockManager: ObservableObject {
    static let shared = LockManager()
    
    @Published var isLocked = false
    private var lastInteractionTime = Date()
    private var timer: Timer?
    
    private init() { }
    
    func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { _ in
            self.checkForInactivity()
        }
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
        if UserDefaults.standard.bool(forKey: "useBiometricAuth") {
            isLocked = true
        }
    }
    
    func unlock() {
        let context = LAContext()
        let reason = String(localized: "unlock_reason")
        context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: reason) { success, _ in
            DispatchQueue.main.async {
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
    }
}



class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {

        // Firebase
        FirebaseApp.configure()

        // Firestore offline cache
        let db = Firestore.firestore()
        let settings = FirestoreSettings()
        settings.cacheSettings = PersistentCacheSettings()
        db.settings = settings

        // Load users cache
        EventManager.shared.preloadUsersIfNeeded()

        // Notifications (LOCAL ONLY)
        UNUserNotificationCenter.current().delegate = self

        // Xin quyền thông báo
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            if settings.authorizationStatus == .notDetermined {
                UNUserNotificationCenter.current()
                    .requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
                        if let error = error {
                            print("❌ Notification permission error:", error.localizedDescription)
                        }
                    }
            }
        }


        return true
    }
    func applicationDidEnterBackground(_ application: UIApplication) {
        ChatForegroundTracker.shared.activeChatEventId = nil
    }

    // Show banner in foreground
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
}
