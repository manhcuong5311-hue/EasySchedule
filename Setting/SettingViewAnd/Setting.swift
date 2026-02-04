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



// MARK: - SettingsView
//  SettingsView.swift

import SwiftUI

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

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        NavigationStack {
            Form {

                if premium.isLoaded && premium.tier != .pro {
                    premiumBanner
                }

                notificationsSection
                appearanceSection
                accountSection
                supportSection
                accountActionsSection
                versionSection

            }
            .scrollContentBackground(.hidden)   // QUAN TRỌNG
            .background(
                AppBackground.settings(colorScheme)
                    .ignoresSafeArea()
            )

            
            .navigationTitle(String(localized: "settings"))
            .onAppear { didFinishInitialLoad = true }
            .onReceive(NotificationCenter.default.publisher(for: .OpenPaywall)) {
                _ in showUpgradeSheet = true
            }
            .alertNotificationSettings($showNotificationSettingsAlert)
            .sheet(isPresented: $showUpgradeSheet) {
                PremiumUpgradeSheet()
            }
            .sheet(isPresented: $showPrivacySheet) {
                PrivacyPolicyView()
            }
        }
    }
}

import SwiftUI

extension SettingsView {

    // MARK: - Version Section
    var versionSection: some View {
        Section(
            footer: bottomSpacer   // 👈 quyết định việc scroll dư
        ) {
            VStack(spacing: 8) {
                Text("Easy Schedule")
                    .font(.footnote)
                    .foregroundColor(.secondary)

                Text(appVersionText)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
        }
        .listRowBackground(Color.clear)
    }

    // MARK: - Bottom Spacer (KHÔNG bị collapse)
    private var bottomSpacer: some View {
        Color.clear
            .frame(height: 120) // 👈 kéo xuống thoải mái, không dính đáy
    }

    // MARK: - App Version (đọc từ Info.plist)
    private var appVersionText: String {
        let version =
            Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
            ?? "—"

        let build =
            Bundle.main.infoDictionary?["CFBundleVersion"] as? String
            ?? "—"

        return "Version \(version) (\(build))"
    }
}

//  Settings+Notifications.swift

import SwiftUI
import UserNotifications

extension SettingsView {

    var notificationsSection: some View {
        Section(header: Text(String(localized: "notifications"))) {

            Toggle(isOn: $pushNotificationsEnabled) {
                Label(String(localized: "notify_before_event"), systemImage: "bell.fill")
            }
            .onChange(of: pushNotificationsEnabled) { _, enabled in
                guard didFinishInitialLoad else { return }
                handlePushToggle(enabled)
            }

            Picker(selection: $leadTime) {
                ForEach([5, 10, 15, 30, 60], id: \.self) { value in
                    Text(
                        String(localized: "minutes_before")
                            .replacingOccurrences(of: "{value}", with: "\(value)")
                    )
                    .tag(value)
                }
            } label: {
                Label(String(localized: "remind_before"), systemImage: "clock")
            }
            .disabled(!pushNotificationsEnabled)
        }
    }

    func handlePushToggle(_ enabled: Bool) {
        if enabled {
            NotificationManager.shared.requestPermissionIfNeeded(
                onDenied: {
                    pushNotificationsEnabled = false
                    showNotificationSettingsAlert = true
                },
                onGranted: {
                    PushPreferenceManager.enablePush()
                    EventManager.shared.rescheduleLocalNotifications()
                }
            )
        } else {
            PushPreferenceManager.disablePush()
            UNUserNotificationCenter.current()
                .removeAllPendingNotificationRequests()
        }
    }
}

// Settings+Appearance.swift

import SwiftUI

extension SettingsView {

    var appearanceSection: some View {
        Section(header: Text(String(localized: "appearance"))) {
            Picker(selection: $appTheme) {
                Text(String(localized: "system")).tag("system")
                Text(String(localized: "light")).tag("light")
                Text(String(localized: "dark")).tag("dark")
            } label: {
                Label(String(localized: "display_mode"),
                      systemImage: "circle.lefthalf.filled")
            }
            .pickerStyle(.segmented)
        }
    }
}

// Settings+Account.swift

extension SettingsView {

    var accountActionsSection: some View {
        Section(header: Text(String(localized: "account_section"))) {

            NavigationLink {
                AccountSettingsView()
                    .environmentObject(session)
            } label: {
                Label(
                    String(localized: "account_management"),
                    systemImage: "person.crop.circle"
                )
            }
        }
    }
}

import UserNotifications
import UIKit

extension NotificationManager {

    /// Wrapper dành riêng cho SettingsView
    /// - Không phá logic cũ
    /// - Không duplicate permission flow
    func requestPermissionIfNeeded(
        onDenied: @escaping () -> Void,
        onGranted: @escaping () -> Void
    ) {
        UNUserNotificationCenter.current()
            .getNotificationSettings { settings in
                DispatchQueue.main.async {
                    switch settings.authorizationStatus {

                    case .authorized:
                        UIApplication.shared.registerForRemoteNotifications()
                        onGranted()

                    case .notDetermined:
                        self.requestPermission { granted in
                            DispatchQueue.main.async {
                                granted ? onGranted() : onDenied()
                            }
                        }

                    case .denied:
                        onDenied()

                    default:
                        onDenied()
                    }
                }
            }
    }
}

extension SettingsView {

    var accountSection: some View {
        Section(header: Text(String(localized: "account_and_premium"))) {

            HStack {
                Label(String(localized: "display_name"), systemImage: "person.fill")
                Spacer()
                Text(
                    session.currentUserName.isEmpty
                    ? String(localized: "not_set")
                    : session.currentUserName
                )
                .foregroundColor(.secondary)
            }

            NavigationLink {
                UpdateUserNameView()
            } label: {
                Label(String(localized: "change_display_name"), systemImage: "pencil")
            }

            Button {
                showUpgradeSheet = true
            } label: {
                premiumRow
            }

            NavigationLink {
                SecuritySettingsView()
            } label: {
                Label(String(localized: "security_management"), systemImage: "lock.shield")
            }
        }
    }

    var premiumRow: some View {
        HStack {
            Label(
                premium.tier == .free
                ? String(localized: "upgrade_account")
                : String(localized: "pro_active"),
                systemImage: "crown.fill"
            )
            Spacer()
            Text(premium.tier.displayName)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}

extension SettingsView {

    var premiumBanner: some View {
        Section {
            SettingsPremiumBanner()
                .environmentObject(premium)
                .padding()
                .background(AppBackground.card(colorScheme))
                .clipShape(
                    RoundedRectangle(
                        cornerRadius: 16,
                        style: .continuous
                    )
                )
                .shadow(
                    color: AppBackground.panelShadow(colorScheme),
                    radius: 18,
                    y: 8
                )

        }
        .listRowInsets(.init())
        .listRowBackground(Color.clear)
    }
}



// Settings+Support.swift

import SwiftUI

extension SettingsView {

    var supportSection: some View {
        Section(header: Text(String(localized: "info_support"))) {

            Button {
                UserDefaults.standard.set(false, forKey: "hasSeenOnboarding")
            } label: {
                Label(String(localized: "view_onboarding"),
                      systemImage: "rectangle.on.rectangle")
            }

            Button {
                showPrivacySheet = true
            } label: {
                Label(String(localized: "privacy_policy_and_info"),
                      systemImage: "doc.text")
            }

            Button(action: contactSupport) {
                Label(String(localized: "contact_support"),
                      systemImage: "envelope")
            }

            NavigationLink {
                FAQView()
            } label: {
                Label(String(localized: "faq"),
                      systemImage: "questionmark.circle")
            }
        }
    }
}


// Settings+Actions.swift

import SwiftUI
import FirebaseAuth
import FirebaseMessaging
import FirebaseFirestore

extension SettingsView {

    func contactSupport() {
        let subject = String(localized: "support_email_subject")
            .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        if let url = URL(string: "mailto:easyschedulehelp@gmail.com?subject=\(subject)") {
            UIApplication.shared.open(url)
        }
    }

    func performLogout() {
        UserDefaults.standard.removeObject(forKey: "pushNotificationsEnabled")

        Messaging.messaging().token { token, _ in
            guard let token,
                  let uid = Auth.auth().currentUser?.uid else { return }

            Firestore.firestore()
                .collection("users")
                .document(uid)
                .updateData([
                    "notificationTokens": FieldValue.arrayRemove([token])
                ])
        }

        try? Auth.auth().signOut()
        session.currentUser = nil
    }
}

extension PremiumTier {

    var displayName: String {
        switch self {
        case .free:
            return String(localized: "free")
        case .premium:
            return String(localized: "premium")
        case .pro:
            return String(localized: "pro")
        }
    }
}

import SwiftUI

extension View {

    func alertNotificationSettings(
        _ isPresented: Binding<Bool>
    ) -> some View {
        alert(
            String(localized: "notifications_disabled_title"),
            isPresented: isPresented
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
    }
}

import SwiftUI

extension View {

    func alertLogout(
        isPresented: Binding<Bool>,
        onConfirm: @escaping () -> Void
    ) -> some View {
        alert(
            String(localized: "logout_confirm"),
            isPresented: isPresented
        ) {
            Button(String(localized: "cancel"), role: .cancel) {}

            Button(String(localized: "logout"), role: .destructive) {
                onConfirm()
            }
        } message: {
            Text(String(localized: "logout_message"))
        }
    }
}
