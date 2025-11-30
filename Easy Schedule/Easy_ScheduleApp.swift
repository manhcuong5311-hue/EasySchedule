import SwiftUI
import FirebaseCore
import FirebaseMessaging
import UserNotifications
@main
struct Easy_scheduleApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var session = SessionStore()
    @AppStorage("appTheme") private var appTheme: String = "system"
    @State private var showLaunch = true
    @State private var showOnboarding: Bool = !UserDefaults.standard.bool(forKey: "hasSeenOnboarding")
    @StateObject var premium = PremiumStoreViewModel.shared
    @StateObject private var eventManager = EventManager.shared

    var body: some Scene {
        
        WindowGroup {
            
            
            if showLaunch {
                LaunchView()
                    .preferredColorScheme(
                                           appTheme == "light" ? .light :
                                           appTheme == "dark" ? .dark : nil
                                       )
                    .environmentObject(eventManager)

                    .onAppear {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                            withAnimation { showLaunch = false }
                        }
                    }
            } else if showOnboarding {
                EnhancedOnboardingView(showOnboarding: $showOnboarding)
                    .preferredColorScheme(
                                           appTheme == "light" ? .light :
                                           appTheme == "dark" ? .dark : nil
                                       )
                    .environmentObject(eventManager)
            } else {
                RootView()
                    .preferredColorScheme(
                                           appTheme == "light" ? .light :
                                           appTheme == "dark" ? .dark : nil
                                       )
                    .environmentObject(session)
                    .environmentObject(premium)

                    .environmentObject(eventManager)
                    .onAppear {
                        session.listen()
                    }

            }
        }
    }
}




struct RootView: View {
    @EnvironmentObject var session: SessionStore
    @EnvironmentObject var premium: PremiumStoreViewModel

    @EnvironmentObject var eventManager: EventManager

    var body: some View {
        if session.currentUser == nil {
            LoginView()
                .environmentObject(eventManager)

        } else {
            ContentView()
                .environmentObject(session)
                .environmentObject(premium)

                .environmentObject(eventManager)

        }
    }
}
