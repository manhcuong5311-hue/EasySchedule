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
            AppFloatingTabBar(
                selectedTab: $selectedTab,
                partnersBadge: accessBadgeVM.pendingCount
            )
        }
        // ⭐ CHÌA KHÓA CUỐI CÙNG
        .ignoresSafeArea(edges: .bottom)

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
            pendingChatEventId = id
            selectedTab = .events
            eventManager.selectedChatEventId = nil
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

    var body: some View {
        HStack(spacing: 0) {
            tab(.events, "Events", "list.bullet.rectangle")
            tab(.calendar, "Calendar", "calendar")
            tab(.partners, "Partners", "person.2.fill", badge: partnersBadge)
            tab(.settings, "Settings", "gearshape")
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 28)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .shadow(color: .black.opacity(0.15), radius: 20, y: 8)
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }

    private func tab(
        _ tab: AppTab,
        _ title: String,
        _ systemImage: String,
        badge: Int = 0
    ) -> some View {
        Button {
            selectedTab = tab
        } label: {
            VStack(spacing: 4) {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: systemImage)
                        .font(.system(size: 18, weight: .semibold))

                    if badge > 0 {
                        Text("\(badge)")
                            .font(.caption2)
                            .foregroundColor(.white)
                            .padding(4)
                            .background(Color.red)
                            .clipShape(Circle())
                            .offset(x: 8, y: -6)
                    }
                }

                Text(title)
                    .font(.caption2)
            }
            .foregroundColor(selectedTab == tab ? .accentColor : .secondary)
            .frame(maxWidth: .infinity)
        }
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


