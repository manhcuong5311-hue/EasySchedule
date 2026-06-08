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
    @State private var showDisplaySettings = false   // moved here from Tab 1's header button
    @State private var settingsShareItem: ShareItem? = nil   // share booking link (moved from old Tab 2)

    // MARK: - Environment Objects
    @EnvironmentObject var session: SessionStore
    @EnvironmentObject var premium: PremiumStoreViewModel
    @EnvironmentObject var eventManager: EventManager
    @EnvironmentObject var uiAccent: UIAccentStore
    @State private var didFinishInitialLoad = false
    @State private var showNotificationSettingsAlert = false

    // MARK: - Constants
    let leadTimeOptions = [5, 10, 15, 30, 60]
    let appVersion = "1.0.0"

    @Environment(\.colorScheme) private var colorScheme
    @State private var versionTapCount = 0
    @State private var lastVersionTap = Date()
    @State private var showPremiumIntro = false
    @State private var showOnboarding = false
    @State private var showDevMenu = false
    
    var body: some View {
        NavigationStack {
            Form {

                profileHeader

                if premium.isLoaded && premium.tier != .pro {
                    premiumBanner
                }

                notificationsSection
                appearanceSection
                availabilitySection
                accountSection
                supportSection
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
                PremiumUpgradeSheet(
                    preselectProductID: "com.SamCorp.EasySchedule.premium.yearly",
                    autoPurchase: false
                )
                .environmentObject(premium)
            }
            .sheet(isPresented: $showPrivacySheet) {
                PrivacyPolicyView()
            }
            .sheet(isPresented: $showDisplaySettings) {
                DisplaySettingsSheet()
            }
            .sheet(item: $settingsShareItem) { item in
                ActivityView(activityItems: [item.url])
            }
            .sheet(isPresented: $showPremiumIntro) {
                PremiumIntroView(
                    isPresented: $showPremiumIntro,
                    onUpgrade: {
                        showUpgradeSheet = true
                    }
                )
            }
            .fullScreenCover(isPresented: $showOnboarding) {
                OnboardingContainerView(onClose: { showOnboarding = false })
            }

            .confirmationDialog(
                "dev_menu_title",
                isPresented: $showDevMenu,
                titleVisibility: .visible
            ) {

                Button("dev_open_onboarding") {
                    showDevMenu = false
                    showOnboarding = true   // present the onboarding preview directly
                }

                Button("dev_open_premium_intro") {
                    showPremiumIntro = true
                }

                Button("dev_open_upgrade") {
                    showUpgradeSheet = true
                }

                Button("Cancel", role: .cancel) {}
            }
        }
    }
}

import SwiftUI

// MARK: - Profile header + shared row helpers

extension SettingsView {

    /// Account header: avatar + display name + plan badge, taps through to the
    /// account-management hub (logout / delete). Replaces the buried name row.
    var profileHeader: some View {
        Section {
            NavigationLink {
                UpdateUserNameView()
            } label: {
                HStack(spacing: 14) {
                    ZStack(alignment: .bottomTrailing) {
                        ZStack {
                            Circle()
                                .fill(
                                    LinearGradient(
                                        colors: [uiAccent.color, uiAccent.color.opacity(0.75)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .frame(width: 56, height: 56)
                            Text(profileInitial)
                                .font(.system(size: 24, weight: .semibold, design: .rounded))
                                .foregroundStyle(.white)
                        }

                        // Editable-avatar pencil badge → signals the row edits the name
                        Circle()
                            .fill(Color(.systemBackground))
                            .frame(width: 22, height: 22)
                            .overlay(
                                Image(systemName: "pencil")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(uiAccent.color)
                            )
                    }

                    VStack(alignment: .leading, spacing: 5) {
                        Text(profileName)
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(.primary)
                        planBadge
                    }
                }
                .padding(.vertical, 6)
            }
        }
    }

    private var profileName: String {
        session.currentUserName.isEmpty
            ? String(localized: "not_set")
            : session.currentUserName
    }

    private var profileInitial: String {
        let trimmed = session.currentUserName.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? "?" : trimmed.prefix(1).uppercased()
    }

    private var planBadge: some View {
        let isPro = premium.tier != .free
        let tint: Color = isPro ? .orange : .secondary
        return HStack(spacing: 4) {
            Image(systemName: isPro ? "crown.fill" : "person.fill")
                .font(.system(size: 10, weight: .bold))
            Text(premium.tier.displayName)
                .font(.caption.weight(.semibold))
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Capsule().fill(tint.opacity(0.15)))
    }

    /// A settings row label with a tinted rounded-square icon (iOS-Settings look).
    func iconLabel(_ title: String, _ systemName: String, _ color: Color) -> some View {
        Label {
            Text(title)
        } icon: {
            Image(systemName: systemName)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous).fill(color)
                )
        }
    }
}

import SwiftUI

extension SettingsView {

    // MARK: - Version Section
    var versionSection: some View {
        Section(
            footer: bottomSpacer
        ) {
            VStack(spacing: 8) {
                Image(systemName: "calendar.circle.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(uiAccent.color)
                    .padding(.bottom, 2)

                Text("Easy Schedule")
                    .font(.footnote.weight(.semibold))
                    .foregroundColor(.secondary)

                Text(appVersionText)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
            .contentShape(Rectangle()) // ⭐ QUAN TRỌNG
            .onTapGesture {
                handleVersionTap()
            }
        }
        .listRowBackground(Color.clear)
    }
    
    private func handleVersionTap() {
        let now = Date()

        if now.timeIntervalSince(lastVersionTap) > 2 {
            versionTapCount = 0
        }

        versionTapCount += 1
        lastVersionTap = now

        if versionTapCount >= 5 {
            versionTapCount = 0
            showDevMenu = true
        }
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
                iconLabel(String(localized: "notify_before_event"), "bell.fill", .red)
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
                iconLabel(String(localized: "remind_before"), "clock", .orange)
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
                iconLabel(String(localized: "display_mode"),
                          "circle.lefthalf.filled", .indigo)
            }
            .pickerStyle(.segmented)

            // Timeline / card display options (was the paintpalette button on Tab 1)
            Button {
                showDisplaySettings = true
            } label: {
                HStack {
                    iconLabel(String(localized: "display_settings"), "paintpalette", .pink)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
            }
            .tint(.primary)
        }
    }
}

extension SettingsView {

    // Booking-availability controls (moved out of the old Calendar tab to declutter it)
    var availabilitySection: some View {
        Section(header: Text("availability_section")) {

            Toggle(isOn: Binding(
                get: { eventManager.allowDuplicateEvents },
                set: { eventManager.allowDuplicateEvents = $0 }
            )) {
                iconLabel(String(localized: "allow_conflict"),
                          "arrow.triangle.2.circlepath", .teal)
            }

            Button {
                if let uid = Auth.auth().currentUser?.uid,
                   let url = URL(string: "https://easyschedule-ce98a.web.app/calendar/\(uid)") {
                    settingsShareItem = ShareItem(url: url)
                }
            } label: {
                HStack {
                    iconLabel(String(localized: "share_calendar"),
                              "square.and.arrow.up", .blue)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
            }
            .tint(.primary)
        }
    }
}

// Settings+Account.swift

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

            Button {
                showUpgradeSheet = true
            } label: {
                premiumRow
            }

            NavigationLink {
                SecuritySettingsView()
            } label: {
                iconLabel(String(localized: "security_management"), "lock.shield", .green)
            }

            NavigationLink {
                AccountSettingsView()
                    .environmentObject(session)
            } label: {
                iconLabel(String(localized: "account_management"), "person.crop.circle", .blue)
            }
        }
    }

    var premiumRow: some View {
        HStack {
            iconLabel(
                premium.tier == .free
                ? String(localized: "upgrade_account")
                : String(localized: "pro_active"),
                "crown.fill",
                .orange
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
                    radius: 12,
                    y: 6
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
                showPrivacySheet = true
            } label: {
                iconLabel(String(localized: "privacy_policy_and_info"),
                          "doc.text", .gray)
            }

            Button(action: contactSupport) {
                iconLabel(String(localized: "contact_support"),
                          "envelope", .blue)
            }

            NavigationLink {
                FAQView()
            } label: {
                iconLabel(String(localized: "faq"),
                          "questionmark.circle", .indigo)
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
