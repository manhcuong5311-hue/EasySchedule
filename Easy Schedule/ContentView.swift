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
    case calendar
    case partners
    case settings
}
// MARK: - ContentView
struct ContentView: View {

    @EnvironmentObject var eventManager: EventManager

    @State private var selectedTab: AppTab = .events
    @State private var openChatEventId: String?
    @State private var pendingChatEventId: String?
    @StateObject private var accessBadgeVM = AccessBadgeViewModel()

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

                case .calendar:
                    NavigationStack {
                        CustomizableCalendarView()
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
            // ⭐ QUAN TRỌNG: cho content ăn full màn hình
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // =========================
            // FLOATING TAB BAR
            // =========================
            if openChatEventId == nil {
                AppFloatingTabBar(
                    selectedTab: $selectedTab,
                    partnersBadge: accessBadgeVM.pendingCount
                )
                .padding(.horizontal, 24)
                .padding(.bottom, 12)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.25), value: openChatEventId)
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

    private let items: [(AppTab, String, String)] = [
        (.events,   "calendar.badge.clock",  "Schedule"),
        (.calendar, "calendar",              "Calendar"),
        (.partners, "person.2.fill",         "Partners"),
        (.settings, "gearshape.fill",        "Settings"),
    ]

    var body: some View {
        HStack(spacing: 0) {
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
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.13), radius: 20, x: 0, y: 6)
                .shadow(color: .black.opacity(0.06), radius: 4, x: 0, y: 1)
        )
    }

    @ViewBuilder
    private func tabItem(tab: AppTab, icon: String, label: String, badge: Int) -> some View {
        let isSelected = selectedTab == tab

        Button {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.72)) {
                selectedTab = tab
            }
            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        } label: {
            ZStack(alignment: .topTrailing) {
                VStack(spacing: 4) {
                    // Icon with selection pill
                    ZStack {
                        if isSelected {
                            Capsule()
                                .fill(Color.accentColor.opacity(0.15))
                                .frame(width: 52, height: 32)
                        }
                        Image(systemName: icon)
                            .font(.system(size: 20, weight: isSelected ? .semibold : .regular))
                            .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                            .symbolEffect(.bounce, value: isSelected)
                    }
                    .frame(height: 32)
                    .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelected)

                    Text(label)
                        .font(.system(size: 10, weight: isSelected ? .semibold : .regular))
                        .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                }
                .frame(maxWidth: .infinity)

                // Badge
                if badge > 0 {
                    Text(badge > 9 ? "9+" : "\(badge)")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.red))
                        .offset(x: -10, y: -2)
                }
            }
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


