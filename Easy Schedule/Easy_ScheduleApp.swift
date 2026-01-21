import SwiftUI
import FirebaseCore
import FirebaseMessaging
import FirebaseAppCheck        // ⭐ THÊM
import UserNotifications

@main
struct Easy_scheduleApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate

    // ⭐ APP CHECK SETUP
    init() {
        #if DEBUG
        AppCheck.setAppCheckProviderFactory(
            AppCheckDebugProviderFactory()
        )
        #else
        AppCheck.setAppCheckProviderFactory(
            DeviceCheckProviderFactory()
        )
        #endif
    }


    @StateObject private var session = SessionStore()
    @AppStorage("appTheme") private var appTheme: String = "system"

    @State private var showLaunch = true
    @AppStorage("hasSeenOnboarding")
    private var hasSeenOnboarding: Bool = false
    @StateObject private var network = NetworkMonitor.shared


    @StateObject var premium = PremiumStoreViewModel.shared
    @StateObject private var eventManager = EventManager.shared
    @StateObject private var lockManager = LockManager.shared
    @StateObject private var guideManager = GuideManager()

    var body: some Scene {
        WindowGroup {
            ZStack {
                appMainContent

                /// 🔐 FaceID Lock
                if lockManager.isLocked &&
                    UserDefaults.standard.bool(forKey: "useBiometricAuth") {

                    LockScreenView()
                        .transition(.opacity)
                }
            }
            .environmentObject(session)        // ⭐ BẮT BUỘC
                   .environmentObject(premium)        // ⭐ BẮT BUỘC
                   .environmentObject(eventManager)
                   .environmentObject(network)
                   .environmentObject(guideManager)
                   .onAppear {
                       lockManager.startTimer()

                       if UserDefaults.standard.bool(forKey: "useBiometricAuth") {
                           lockManager.lock()   // ⭐ DÒNG QUAN TRỌNG NHẤT
                       }
                   }

            .onReceive(
                NotificationCenter.default.publisher(
                    for: UIApplication.willResignActiveNotification
                )
            ) { _ in
                lockManager.lock()
            }
        }
    }
}

// MARK: - MAIN CONTENT
extension Easy_scheduleApp {

    @ViewBuilder
    var appMainContent: some View {
        if showLaunch {
            LaunchView()
                .preferredColorScheme(colorScheme)
                .environmentObject(eventManager)
                .environmentObject(premium)
                .onAppear {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        withAnimation { showLaunch = false }
                    }
                }

        } else if !hasSeenOnboarding {
            OnboardingContainerView()
                .preferredColorScheme(colorScheme)
        } else {
            RootView()
                .preferredColorScheme(colorScheme)
                .environmentObject(session)
                .environmentObject(eventManager)
        }
    }

    private var colorScheme: ColorScheme? {
        appTheme == "light" ? .light :
        appTheme == "dark" ? .dark : nil
    }
}

// MARK: - ROOT VIEW
struct RootView: View {
    @EnvironmentObject var session: SessionStore
    @EnvironmentObject var premium: PremiumStoreViewModel
    @EnvironmentObject var eventManager: EventManager

    @State private var showPremiumIntro = false
    @State private var showPaywall = false
    @EnvironmentObject var network: NetworkMonitor
    @EnvironmentObject var guideManager: GuideManager



    var body: some View {
        Group {
            if session.currentUser == nil {
                LoginView()
            } else {
                ContentView()
                    
                    .onAppear {
                        guideManager.startIfNeeded() 
                              // ⭐⭐⭐ DÒNG QUAN TRỌNG NHẤT ⭐⭐⭐
                              if let uid = session.currentUserId {
                                  eventManager.configureForUser(uid: uid)
                                  eventManager.preloadUsersIfNeeded() 
                              }

                              Task { await premium.refresh() }
                            
                          }
                    .onChange(of: premium.isLoaded) { _, loaded in
                        guard loaded else { return }

                        if premium.tier == .free,
                           PremiumIntroGate.shouldShowToday() {

                            showPremiumIntro = true
                            PremiumIntroGate.markShown()
                        }
                    }
            }
        }
        // ⭐⭐⭐ INJECT Ở ĐÂY — NGOÀI GROUP ⭐⭐⭐
        .environmentObject(session)
        .environmentObject(eventManager)
        .environmentObject(network)

        .sheet(isPresented: $showPremiumIntro) {
            PremiumIntroView(
                isPresented: $showPremiumIntro,
                onUpgrade: {
                    showPaywall = true
                }
            )
        }
        .sheet(isPresented: $showPaywall) {
            PremiumUpgradeSheet()
                .environmentObject(premium)
        }
    }
}

struct OnboardingContainerView: View {

    @AppStorage("hasSeenOnboarding")
    private var hasSeenOnboarding = false

    @State private var step: OnboardingStep = .hero

    var body: some View {
        TabView(selection: $step) {

            // 1️⃣ HERO
            OnboardingHeroSlide(
                onNext: { step = .webBooking }   // 👉 đi thẳng sang Web Booking
            )
            .tag(OnboardingStep.hero)

            // 2️⃣ WEB BOOKING (đưa lên đây)
            OnboardingWebBookingSlide(
                onNext: { step = .availability }
            )
            .tag(OnboardingStep.webBooking)

            // 3️⃣ AVAILABILITY
            AvailabilityFeatureSlide(
                onNext: { step = .chat }
            )
            .tag(OnboardingStep.availability)

            // 4️⃣ CHAT AI
            ChatToPlanAISlide(
                onNext: { step = .planning }
            )
            .tag(OnboardingStep.chat)

            // 5️⃣ SMART PLANNING AI
            SmartPlanningAISlide(
                onNext: { step = .cta }
            )
            .tag(OnboardingStep.planning)

            // 6️⃣ CTA
            FinalOnboardingCTASlide(
                hasSeenOnboarding: $hasSeenOnboarding
            )
            .tag(OnboardingStep.cta)
        }
        .tabViewStyle(.page)
        .ignoresSafeArea()
    }
}
