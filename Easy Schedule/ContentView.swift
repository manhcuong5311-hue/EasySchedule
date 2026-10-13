//
//  ContentView.swift
//  Easy schedule
//
//  Created by Sam Manh Cuong on 11/11/25.
//
import SwiftUI
import Combine
import FirebaseCore
import FirebaseMessaging
import UserNotifications
import FirebaseAuth
import FirebaseFirestore



extension Array {
    func partitioned(by condition: (Element) -> Bool) -> (matches: [Element], nonMatches: [Element]) {
        var matches = [Element]()
        var nonMatches = [Element]()
        for element in self {
            if condition(element) { matches.append(element) } else { nonMatches.append(element) }
        }
        return (matches, nonMatches)
    }
}

struct ChatRoute: Identifiable, Hashable {
    let id: String
}

struct EventRoute: Identifiable, Hashable {
    let id: String
}

enum AppTab: Hashable {
    case events
    case partners
    case settings
}
// MARK: - ContentView
struct ContentView: View {

    @EnvironmentObject var eventManager: EventManager
    @EnvironmentObject var session: SessionStore

    @State private var selectedTab: AppTab = .events
    @State private var openChatEventId: String?
    @State private var pendingChatEventId: String?
    // One-time name nudge: fresh accounts have no display name, so partners would
    // see "No name" / a UID. Prompt once per launch when the Partner tab is opened.
    @State private var showNamePrompt = false
    @State private var didCheckNamePrompt = false
    @StateObject private var accessBadgeVM = AccessBadgeViewModel()
    @ObservedObject private var ads = AdsManager.shared
    /// Physical bottom safe-area inset (home indicator height). Read once on appear.
    @State private var bottomSafeArea: CGFloat = 0
    @Environment(\.colorScheme) private var scheme

    /// Card frame around the ad banner (padding only — the ad itself is never clipped).
    private let adFramePadding: CGFloat = 4
    private var hasBanner: Bool { ads.bannerInset > 0 }

    var body: some View {

        ZStack(alignment: .bottom) {

            // =========================
            // MAIN CONTENT (NO TABVIEW)
            // =========================
            Group {
                switch selectedTab {

                case .events:
                    NavigationStack {
                        EventListView(
                            onBookPartner: {
                                selectedTab = .partners
                            }
                        )
                        .navigationDestination(item: $openChatEventId) { id in
                            ChatEntryResolverView(eventId: id)
                        }
                        .onChange(of: pendingChatEventId) { _, chatId in
                            guard let chatId else { return }
                            openChatEventId = chatId
                            pendingChatEventId = nil
                        }
                    }

                case .partners:
                    NavigationStack {
                        PartnerCalendarTabView(
                            onBookPartner: {
                                selectedTab = .partners
                            }
                        )
                    }

                case .settings:
                    NavigationStack {
                        SettingsView()
                    }
                }
            }
            // Free users: keep scroll content clear of the ad banner above the tab bar.
            .safeAreaInset(edge: .bottom, spacing: 0) {
                Color.clear.frame(
                    height: openChatEventId == nil
                        ? ads.bannerInset + (hasBanner ? adFramePadding * 2 : 0)
                        : 0
                )
            }
            // ⭐ QUAN TRỌNG: cho content ăn full màn hình
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .ignoresSafeArea(edges: .bottom)

            // =========================
            // FLOATING TAB BAR
            // =========================
            if openChatEventId == nil {
                VStack(spacing: ads.bannerHeight > 0 ? AdsConfig.bannerSpacing : 0) {
                    // Free users only — renders nothing for Premium/Pro.
                    // Tidy card frame drawn BEHIND the banner (padding + background only):
                    // never clip / cover the ad itself (AdMob policy).
                    AdBannerView()
                        .padding(hasBanner ? adFramePadding : 0)
                        .background(
                            ZStack {
                                RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous)
                                    .fill(AppBackground.card(scheme))
                                RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous)
                                    .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
                            }
                            .opacity(hasBanner ? 1 : 0)
                            .allowsHitTesting(false)
                        )

                    AppFloatingTabBar(
                        selectedTab: $selectedTab,
                        partnersBadge: accessBadgeVM.pendingCount
                    )
                    .padding(.horizontal, 24)
                }
                // bottomSafeArea accounts for the home-indicator zone so the bar
                // sits 12 pt above the indicator on all devices (0 on older iPhones).
                .padding(.bottom, bottomSafeArea + 12)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        // Extend ZStack to true screen bottom so the floating bar aligns correctly
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea(edges: .bottom)
        .background(
            // ignoresSafeArea here lets the GeometryReader report the real
            // home-indicator inset (without it the parent constraint makes it 0).
            GeometryReader { geo in
                Color.clear
                    .onAppear { bottomSafeArea = geo.safeAreaInsets.bottom }
            }
            .ignoresSafeArea()
        )
        .animation(.easeInOut(duration: 0.25), value: openChatEventId)
        // Nudge nameless accounts to set a display name the first time they open
        // the Partner tab (where the name actually matters for booking).
        .onChange(of: selectedTab) { _, newTab in
            guard newTab == .partners else { return }
            maybePromptForName()
        }
        .sheet(isPresented: $showNamePrompt) {
            NameSetupPromptView()
        }
        // =========================
        // LIFECYCLE – GIỮ NGUYÊN
        // =========================
        .onAppear {
            handlePendingPush()
            eventManager.cleanUpPastEvents()

            if let uid = Auth.auth().currentUser?.uid {
                accessBadgeVM.load(ownerUid: uid)
            }
        }
        // Share buttons use the short /c/<handle> link when the user set one
        .task { await BookingLink.refreshCachedHandle() }

        // 🔔 CHAT PUSH – GIỮ NGUYÊN
        .onChange(of: eventManager.selectedChatEventId) { _, id in
            guard let id else { return }
            selectedTab = .events
            eventManager.selectedChatEventId = nil
            // Delay so the .events NavigationStack is in the hierarchy
            // before pendingChatEventId changes — otherwise onChange on
            // the newly-mounted stack won't fire (SwiftUI only detects
            // changes after a view is already present, not the initial value).
            DispatchQueue.main.async {
                pendingChatEventId = id
            }
        }
    }

    /// Show the "set your name" sheet at most once per launch, and only for a
    /// signed-in account that still has no real display name. A short delay lets
    /// the profile finish loading so returning, already-named users aren't nudged.
    private func maybePromptForName() {
        guard !didCheckNamePrompt, session.currentUser != nil else { return }
        didCheckNamePrompt = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            guard session.currentUser != nil, !session.hasRealName else { return }
            showNamePrompt = true
        }
    }

    private func handlePendingPush() {
        if let chatId = UserDefaults.standard.string(forKey: "pendingChatEventId") {
            UserDefaults.standard.removeObject(forKey: "pendingChatEventId")
            eventManager.openChat(eventId: chatId)
        }

        if let eventId = UserDefaults.standard.string(forKey: "pendingEventId") {
            UserDefaults.standard.removeObject(forKey: "pendingEventId")
            eventManager.openEvent(eventId: eventId)
        }
    }
}


struct AppFloatingTabBar: View {

    @Binding var selectedTab: AppTab
    let partnersBadge: Int

    @EnvironmentObject private var uiAccent: UIAccentStore
    @Environment(\.colorScheme) private var scheme
    @Namespace private var pillNS

    private var accent: Color { uiAccent.color }

    // Third element is a localization key (resolved via LocalizedStringKey below).
    private let items: [(AppTab, String, String)] = [
        (.events,   "calendar.badge.clock",  "schedule"),
        (.partners, "person.2.fill",         "partners"),
        (.settings, "gearshape.fill",        "settings"),
    ]

    var body: some View {
        HStack(spacing: 2) {
            ForEach(items, id: \.0) { appTab, icon, label in
                tabItem(
                    tab: appTab,
                    icon: icon,
                    label: label,
                    badge: appTab == .partners ? partnersBadge : 0
                )
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .overlay(
            // Glassy hairline rim — brighter at top, fading down.
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: scheme == .dark
                            ? [Color.white.opacity(0.14), Color.white.opacity(0.03)]
                            : [Color.white.opacity(0.85), Color.white.opacity(0.25)],
                        startPoint: .top, endPoint: .bottom
                    ),
                    lineWidth: 0.8
                )
        )
        // Single soft shadow (stronger in dark mode so the bar still lifts off the background).
        .shadow(color: .black.opacity(scheme == .dark ? 0.40 : 0.10), radius: 12, y: 6)
    }

    @ViewBuilder
    private func tabItem(tab: AppTab, icon: String, label: String, badge: Int) -> some View {
        let isSelected = selectedTab == tab

        Button {
            guard selectedTab != tab else { return }
            withAnimation(.spring(response: 0.38, dampingFraction: 0.74)) {
                selectedTab = tab
            }
            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        } label: {
            VStack(spacing: 4) {

                ZStack {
                    // Sliding selection pill (shared geometry → glides between tabs)
                    if isSelected {
                        Capsule(style: .continuous)
                            .fill(accent.opacity(0.16))
                            .overlay(
                                Capsule(style: .continuous)
                                    .strokeBorder(accent.opacity(0.22), lineWidth: 0.8)
                            )
                            .matchedGeometryEffect(id: "tabPill", in: pillNS)
                    }

                    Image(systemName: icon)
                        .font(.system(size: 19, weight: isSelected ? .semibold : .regular))
                        .foregroundStyle(
                            isSelected ? AnyShapeStyle(accent.gradient)
                                       : AnyShapeStyle(Color.secondary)
                        )
                        .scaleEffect(isSelected ? 1.06 : 1)
                        .shadow(color: isSelected ? accent.opacity(0.35) : .clear, radius: 5, y: 2)
                        .symbolEffect(.bounce, value: isSelected)
                }
                .frame(width: 56, height: 34)
                .overlay(alignment: .topTrailing) {
                    if badge > 0 {
                        Text(badge > 9 ? "9+" : "\(badge)")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.red))
                            .overlay(Capsule().strokeBorder(Color(.systemBackground), lineWidth: 1.5))
                            .offset(x: 8, y: -3)
                    }
                }

                Text(LocalizedStringKey(label))
                    .font(.system(size: 11, weight: isSelected ? .semibold : .medium))
                    .foregroundStyle(isSelected ? accent : Color.secondary)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }
}



func displayName(for event: CalendarEvent, uid: String, eventManager: EventManager) -> String {

    // 1️⃣ Web gửi participantNames: { uid: "Name", ... }
    if let map = event.participantNames, let name = map[uid], !name.isEmpty {
        return name
    }

    // 2️⃣ Web gửi creatorName — áp dụng cho createdBy
    if uid == event.createdBy, let name = event.creatorName, !name.isEmpty {
        return name
    }

    // 3️⃣ Fallback → dùng cache của App
    return eventManager.userNames[uid] ?? uid
}






struct ShareItem: Identifiable {
    let id = UUID()
    let url: URL
}


struct ActivityView: UIViewControllerRepresentable {
    let activityItems: [Any]
    let applicationActivities: [UIActivity]? = nil
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: applicationActivities)
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}


