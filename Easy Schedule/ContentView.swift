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

    var body: some View {

        TabView(selection: $selectedTab) {

            NavigationStack {
                EventListView(
                    onBookPartner: {
                        selectedTab = .partners   // 👈 SWITCH SANG TAB ĐỐI TÁC
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

            .tabItem {
                Label("tab_events", systemImage: "list.bullet.rectangle")
            }
            .tag(AppTab.events)

            NavigationStack {
                CustomizableCalendarView()
            }
            .tabItem {
                Label("tab_calendar", systemImage: "calendar")
            }
            .tag(AppTab.calendar)

            NavigationStack {
                   PartnerCalendarTabView(
                       onBookPartner: {
                           selectedTab = .partners    // 👈 TAB 3
                       }
                   )
               }
               .tabItem {
                   Label("tab_partners", systemImage: "person.2.fill")
               }
               .tag(AppTab.partners)
            
            NavigationStack {
                SettingsView()
            }
            .tabItem {
                Label("tab_settings", systemImage: "gearshape")
            }
            .tag(AppTab.settings)
        }
        .onAppear {
            handlePendingPush()
            eventManager.cleanUpPastEvents()
        }

        // 🔔 CHAT PUSH
        .onChange(of: eventManager.selectedChatEventId) { _, id in
            guard let id else { return }

            pendingChatEventId = id       // 1. Ghi nhớ intent
            selectedTab = .events         // 2. Chỉ switch tab
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


