import SwiftUI
import FirebaseCore
import FirebaseMessaging
import UserNotifications
@main
struct Easy_scheduleApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var session = SessionStore()
    @StateObject private var languageManager = LanguageManager.shared   // ✅ SỬA 1

    @State private var showLaunch = true
    @State private var showOnboarding: Bool = !UserDefaults.standard.bool(forKey: "hasSeenOnboarding")

    var body: some Scene {
        WindowGroup {
            if showLaunch {
                LaunchView()
                    .environmentObject(languageManager)                // ✅ SỬA 2
                    .onAppear {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                            withAnimation { showLaunch = false }
                        }
                    }
            } else if showOnboarding {
                EnhancedOnboardingView(showOnboarding: $showOnboarding)
                    .environmentObject(languageManager)                // ✅ SỬA 2
            } else {
                RootView()
                    .environmentObject(session)
                    .environmentObject(languageManager)               // ✅ SỬA 2
                    .onAppear {
                        session.listen()
                    }
            }
        }
    }
}


import SwiftUI

struct RootView: View {
    @EnvironmentObject var session: SessionStore

    var body: some View {
        if session.currentUser == nil {
            LoginView()
        } else {
            ContentView()
                .environmentObject(SessionStore())
        }
    }
}
