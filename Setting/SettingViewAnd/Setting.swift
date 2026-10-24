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
import StoreKit



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
    @State private var showRemoveAdsSheet = false
    @State private var showDisplaySettings = false   // moved here from Tab 1's header button
    @State private var settingsShareItem: ShareItem? = nil   // share booking link (moved from old Tab 2)
    @State private var showBookingHours = false
    @State private var showBookingLink = false

    // MARK: - Environment Objects
    @EnvironmentObject var session: SessionStore
    @EnvironmentObject var premium: PremiumStoreViewModel
    @EnvironmentObject var eventManager: EventManager
    @EnvironmentObject var uiAccent: UIAccentStore
    @ObservedObject var ads = AdsManager.shared
    @AppStorage(DeviceCalendarSync.enabledKey) var syncDeviceCalendar = false
    @State var showCalendarAccessDenied = false
    @State private var didFinishInitialLoad = false
    @State private var showNotificationSettingsAlert = false

    // MARK: - Constants
    let leadTimeOptions = [5, 10, 15, 30, 60]
    let appVersion = "1.0.0"

    @Environment(\.colorScheme) private var colorScheme
    @State private var versionTapCount = 0
    @State private var lastVersionTap = Date()
    @State private var showOnboarding = false
    @State private var showDevMenu = false

    var body: some View {
        NavigationStack {
            Form {

                profileHeader

                if premium.isLoaded && !premium.isAdFree {
                    removeAdsBanner
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
            .tint(uiAccent.color)

            .navigationTitle(String(localized: "settings"))
            .onAppear { didFinishInitialLoad = true }
            .alertNotificationSettings($showNotificationSettingsAlert)
            .sheet(isPresented: $showRemoveAdsSheet) {
                RemoveAdsSheet()
                    .environmentObject(premium)
            }
            .sheet(isPresented: $showPrivacySheet) {
                PrivacyPolicyView()
                    .environmentObject(uiAccent)
            }
            .sheet(isPresented: $showDisplaySettings) {
                DisplaySettingsSheet()
                    .environmentObject(uiAccent)
            }
            .sheet(item: $settingsShareItem) { item in
                ActivityView(activityItems: [item.url])
            }
            .sheet(isPresented: $showBookingHours) {
                BookingHoursSheet()
                    .environmentObject(uiAccent)
            }
            .sheet(isPresented: $showBookingLink) {
                BookingLinkSheet()
                    .environmentObject(uiAccent)
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

                Button("dev_open_upgrade") {
                    showRemoveAdsSheet = true
                }

                Button(String(localized: "cancel"), role: .cancel) {}
            }
        }
    }
}

// MARK: - Shared settings styling
//
// One row look for Settings and its sub-screens (iOS-Settings style):
// 30×30 rounded colored tile + white SF Symbol, title, optional trailing value,
// chevron only on rows that open another screen / sheet.

/// 30×30 rounded (r8) colored tile with a white SF Symbol.
struct SettingsIconTile: View {
    let systemName: String
    let color: Color
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 30, height: 30)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(color.gradient)
            )
            .opacity(isEnabled ? 1 : 0.45)
            .accessibilityHidden(true)
    }
}

/// Icon tile + title with a fixed 12pt gap, so every row's text starts at the same x.
struct SettingsTileLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 12) {
            configuration.icon
            configuration.title
                // Separators start under the title, not under the tile.
                .alignmentGuide(.listRowSeparatorLeading) { d in d[.leading] }
        }
    }
}

/// Standard settings row label (used for toggles, pickers, links and buttons).
struct SettingsRowLabel: View {
    let title: String
    let systemName: String
    let color: Color
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Label {
            Text(SettingsText.plain(title))
                // Buttons in a tinted Form would otherwise paint the title in the accent.
                .foregroundStyle(isEnabled ? Color.primary : Color.secondary)
        } icon: {
            SettingsIconTile(systemName: systemName, color: color)
        }
        .labelStyle(SettingsTileLabelStyle())
    }
}

/// Row for Buttons: label + optional trailing value + optional chevron
/// (NavigationLink rows get the system chevron automatically).
struct SettingsActionRow: View {
    let title: String
    let systemName: String
    let color: Color
    var value: String? = nil
    var showsChevron: Bool = true

    var body: some View {
        HStack(spacing: 8) {
            SettingsRowLabel(title: title, systemName: systemName, color: color)
            Spacer(minLength: 8)
            if let value, !value.isEmpty {
                Text(value)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            if showsChevron {
                SettingsChevron()
            }
        }
        .contentShape(Rectangle())
    }
}

/// Same look as the chevron NavigationLink draws in a Form.
struct SettingsChevron: View {
    var body: some View {
        Image(systemName: "chevron.right")
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.tertiary)
            .accessibilityHidden(true)
    }
}

enum SettingsText {
    /// Some catalog titles carry a decorative emoji ("📞 Contact support") or a stray
    /// trailing newline; the icon tile already shows a symbol, so drop both.
    static func plain(_ text: String) -> String {
        let words = text
            .filter { !$0.isDecorativeEmoji }
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
        return words.isEmpty
            ? text.trimmingCharacters(in: .whitespacesAndNewlines)
            : words.joined(separator: " ")
    }
}

private extension Character {
    var isDecorativeEmoji: Bool {
        unicodeScalars.contains { $0.properties.isEmojiPresentation || $0.value == 0xFE0F }
    }
}

import SwiftUI

// MARK: - Profile header + shared row helpers

extension SettingsView {

    /// Card-style row background shared by every section.
    var rowBackground: Color { AppBackground.card(colorScheme) }

    /// Account header: avatar + display name + plan badge, taps through to the
    /// profile editor (name + photo).
    var profileHeader: some View {
        Section {
            NavigationLink {
                UpdateUserNameView()
            } label: {
                HStack(spacing: 14) {
                    AvatarView(uid: session.currentUserId ?? "", size: 56) {
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
                    }
                    .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 6) {
                        Text(profileName)
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                        planBadge
                    }

                    Spacer(minLength: 8)

                    Text(String(localized: "edit"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 8)
            }
            .listRowBackground(rowBackground)
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

    /// "Pro" while a legacy Pro plan runs, "Ad-free" after any purchase, otherwise "Free".
    private var planBadge: some View {
        let isPaid = premium.isPro || premium.isAdFree
        let tint: Color = isPaid ? .orange : .secondary
        let title = premium.isPro
            ? String(localized: "plan_pro")
            : String(localized: premium.isAdFree ? "ad_free" : "free")
        return HStack(spacing: 4) {
            Image(systemName: isPaid ? "crown.fill" : "person.fill")
                .font(.system(size: 10, weight: .bold))
            Text(title)
                .font(.caption.weight(.semibold))
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Capsule().fill(tint.opacity(0.15)))
    }

    /// A settings row label with a 30×30 colored rounded icon tile (iOS-Settings look).
    func iconLabel(_ title: String, _ systemName: String, _ color: Color) -> some View {
        SettingsRowLabel(title: title, systemName: systemName, color: color)
    }
}

import SwiftUI

extension SettingsView {

    // MARK: - Version Section
    var versionSection: some View {
        Section(
            footer: bottomSpacer
        ) {
            VStack(spacing: 6) {
                Image(systemName: "calendar.circle.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(uiAccent.color)
                    .padding(.bottom, 2)

                Text("Easy Schedule")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)

                Text(verbatim: appVersionText)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 20)
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
    /// Language-neutral "v2.4 (57)".
    private var appVersionText: String {
        let version =
            Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
            ?? "—"

        let build =
            Bundle.main.infoDictionary?["CFBundleVersion"] as? String
            ?? "—"

        return "v\(version) (\(build))"
    }
}

//  Settings+Notifications.swift

import SwiftUI
import UserNotifications

extension SettingsView {

    var notificationsSection: some View {
        Section {

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
                iconLabel(String(localized: "remind_before"), "clock.fill", .orange)
            }
            .disabled(!pushNotificationsEnabled)
        } header: {
            Text("notifications")
        }
        .listRowBackground(rowBackground)
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
        Section {
            // Segmented controls hide their label in a Form → show the tile beside it.
            HStack(spacing: 12) {
                SettingsIconTile(systemName: "circle.lefthalf.filled", color: .indigo)

                Picker(String(localized: "display_mode"), selection: $appTheme) {
                    Text(String(localized: "system")).tag("system")
                    Text(String(localized: "light")).tag("light")
                    Text(String(localized: "dark")).tag("dark")
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .alignmentGuide(.listRowSeparatorLeading) { d in d[.leading] }
            }
            .padding(.vertical, 2)

            // Timeline / card display options (was the paintpalette button on Tab 1)
            Button {
                showDisplaySettings = true
            } label: {
                SettingsActionRow(
                    title: String(localized: "display_settings"),
                    systemName: "paintpalette.fill",
                    color: .pink
                )
            }
        } header: {
            Text("appearance")
        }
        .listRowBackground(rowBackground)
    }
}

extension SettingsView {

    // Booking-availability controls (moved out of the old Calendar tab to declutter it)
    var availabilitySection: some View {
        Section {

            // 1. Share my booking link
            Button {
                if let uid = Auth.auth().currentUser?.uid {
                    settingsShareItem = ShareItem(url: BookingLink.url(for: uid))
                }
            } label: {
                SettingsActionRow(
                    title: String(localized: "share_calendar"),
                    systemName: "square.and.arrow.up",
                    color: .blue,
                    showsChevron: false
                )
            }

            // 2. Memorable /c/<handle> booking link
            Button {
                showBookingLink = true
            } label: {
                SettingsActionRow(
                    title: String(localized: "booking_link_title"),
                    systemName: "link",
                    color: .indigo,
                    value: BookingLink.cachedHandle.map { "/c/\($0)" }
                )
            }

            // 3. Weekly hours / buffer / max per day that other people can book
            Button {
                showBookingHours = true
            } label: {
                SettingsActionRow(
                    title: String(localized: "booking_hours_title"),
                    systemName: "clock.badge.checkmark",
                    color: .green
                )
            }

            Toggle(isOn: Binding(
                get: { eventManager.allowDuplicateEvents },
                set: { eventManager.allowDuplicateEvents = $0 }
            )) {
                iconLabel(String(localized: "allow_conflict"),
                          "rectangle.on.rectangle", .teal)
            }

            // Busy times from the iPhone Calendar (times only, no titles).
            // Last row, so the section footer below explains it.
            Toggle(isOn: Binding(
                get: { syncDeviceCalendar },
                set: { on in
                    Task {
                        let result = await DeviceCalendarSync.shared.setEnabled(on)
                        if on && !result { showCalendarAccessDenied = true }
                    }
                }
            )) {
                iconLabel(String(localized: "device_calendar_sync"),
                          "calendar.badge.clock", .red)
            }
            .alert(String(localized: "device_calendar_denied_title"),
                   isPresented: $showCalendarAccessDenied) {
                Button(String(localized: "open_settings")) {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                Button(String(localized: "cancel"), role: .cancel) {}
            } message: {
                Text(String(localized: "device_calendar_denied_message"))
            }
        } header: {
            Text("availability_section")
        } footer: {
            Text(String(localized: "device_calendar_sync_footer"))
        }
        .listRowBackground(rowBackground)
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
        Section {

            Button {
                showRemoveAdsSheet = true
            } label: {
                removeAdsRow
            }

            // Legacy Premium / Pro subscribers: nothing needs the subscription anymore.
            if premium.hasActiveSubscription {
                Button {
                    if let url = URL(string: "https://apps.apple.com/account/subscriptions") {
                        UIApplication.shared.open(url)
                    }
                } label: {
                    SettingsActionRow(
                        title: String(localized: "manage_subscription"),
                        systemName: "arrow.triangle.2.circlepath",
                        color: .gray
                    )
                }
            }

            NavigationLink {
                AccountSettingsView()
                    .environmentObject(session)
            } label: {
                iconLabel(String(localized: "account_management"), "person.crop.circle.fill", .blue)
            }

            NavigationLink {
                SecuritySettingsView()
            } label: {
                iconLabel(String(localized: "security_management"), "lock.shield.fill", .green)
            }
        } header: {
            Text("account_and_premium")
        } footer: {
            if premium.hasActiveSubscription {
                Text(String(localized: "legacy_subscription_note"))
            }
        }
        .listRowBackground(rowBackground)
    }

    var removeAdsRow: some View {
        SettingsActionRow(
            title: String(localized: premium.isAdFree ? "ads_removed" : "remove_ads"),
            systemName: "sparkles",
            color: .orange,
            value: premium.isAdFree ? nil : premium.removeAdsProduct?.displayPrice
        )
    }
}

extension SettingsView {

    /// The banner is its own accent card — no extra white card around it.
    var removeAdsBanner: some View {
        Section {
            SettingsRemoveAdsBanner { showRemoveAdsSheet = true }
                .environmentObject(premium)
                .environmentObject(uiAccent)
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
        }
    }
}



// Settings+Support.swift

import SwiftUI

extension SettingsView {

    var supportSection: some View {
        Section {

            NavigationLink {
                FAQView()
            } label: {
                iconLabel(String(localized: "faq"),
                          "questionmark.circle.fill", .purple)
            }

            Button(action: contactSupport) {
                SettingsActionRow(
                    title: String(localized: "contact_support"),
                    systemName: "envelope.fill",
                    color: .blue,
                    showsChevron: false
                )
            }

            Button {
                showPrivacySheet = true
            } label: {
                SettingsActionRow(
                    title: String(localized: "privacy_policy_and_info"),
                    systemName: "doc.text.fill",
                    color: .gray
                )
            }

            // Required by Google for EEA/UK users: let them change ad consent.
            if ads.adsEnabled && ads.privacyOptionsRequired {
                Button {
                    ads.presentPrivacyOptions()
                } label: {
                    SettingsActionRow(
                        title: String(localized: "ads_privacy_options"),
                        systemName: "hand.raised.fill",
                        color: .teal,
                        showsChevron: false
                    )
                }
            }
        } header: {
            Text("info_support")
        }
        .listRowBackground(rowBackground)
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
