import SwiftUI

struct EnhancedOnboardingView: View {
    @AppStorage("hasSeenOnboarding")
      private var hasSeenOnboarding: Bool = false
    @State private var logoScale: CGFloat = 0.6
    @State private var textOpacity: Double = 0.0

    var body: some View {
        TabView {

            // Slide 1: POSITIONING — Made for two people (MOST IMPORTANT)
            featureSlide(
                imageName: "person.2.fill",
                title: String(localized: "onboarding_title_1"),
                description: String(localized: "onboarding_desc_1"),
                gradient: LinearGradient(
                    colors: [Color.orange, Color.red],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                useSystemImage: true
            )

            // Slide 2: SHARED CALENDAR — Share availability
            featureSlide(
                imageName: "calendar",
                title: String(localized: "onboarding_title_2"),
                description: String(localized: "onboarding_desc_2"),
                gradient: LinearGradient(
                    colors: [Color.blue, Color.purple],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                useSystemImage: true
            )

            // Slide 3: CHAT INSIDE EVENTS — Strong USP
            featureSlide(
                imageName: "bubble.left.and.bubble.right.fill",
                title: String(localized: "onboarding_title_3"),
                description: String(localized: "onboarding_desc_3"),
                gradient: LinearGradient(
                    colors: [Color.indigo, Color.cyan],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                useSystemImage: true
            )

            // Slide 4: TODO TOGETHER — Linked to events
            featureSlide(
                imageName: "checklist",
                title: String(localized: "onboarding_title_4"),
                description: String(localized: "onboarding_desc_4"),
                gradient: LinearGradient(
                    colors: [Color.green, Color.teal],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                useSystemImage: true
            )

            // Slide 5: NOTIFICATIONS + CTA — Activate real value
            featureSlide(
                imageName: "bell",
                title: String(localized: "onboarding_title_5"),
                description: String(localized: "onboarding_desc_5"),
                gradient: LinearGradient(
                    colors: [Color.orange, Color.red],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                useSystemImage: true,
                showButton: true
            )
        }
        .tabViewStyle(PageTabViewStyle())

    }

    @ViewBuilder
    func featureSlide(imageName: String, title: String, description: String, gradient: LinearGradient, useSystemImage: Bool, showButton: Bool = false) -> some View {
        ZStack {
            gradient
                .ignoresSafeArea()
            
            VStack(spacing: 30) {
                // Image hoặc SF Symbol
                if useSystemImage {
                    Image(systemName: imageName)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 150, height: 150)
                        .foregroundColor(.white)
                        .scaleEffect(logoScale)
                        .animation(.easeOut(duration: 1), value: logoScale)
                } else {
                    Image(imageName)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 150, height: 150)
                        .shadow(color: .black.opacity(0.3), radius: 10, x: 0, y: 5)
                        .scaleEffect(logoScale)
                        .animation(.easeOut(duration: 1), value: logoScale)
                }
                
                // Text
                VStack(spacing: 10) {
                    Text(title)
                        .font(.title)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                        .opacity(textOpacity)
                        .animation(.easeIn(duration: 1).delay(0.3), value: textOpacity)
                    
                    Text(description)
                        .font(.body)
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                        .opacity(textOpacity)
                        .animation(.easeIn(duration: 1).delay(0.5), value: textOpacity)
                }
                
                // Button "Get Started" chỉ slide cuối
                if showButton {
                    VStack(spacing: 14) {

                        // 🔵 PRIMARY CTA — Invite someone
                        Button {
                            presentInviteSheet()
                        } label: {
                            Text(String(localized: "invite_someone"))
                                .font(.headline)
                                .foregroundColor(.white)
                                .padding()
                                .frame(maxWidth: .infinity)
                                .background(Color.orange)
                                .cornerRadius(15)
                                .padding(.horizontal)
                        }

                        // ⚪ SECONDARY CTA — Get started
                        Button {
                            hasSeenOnboarding = true
                        } label: {
                            Text(String(localized: "get_started"))
                                .font(.subheadline)
                                .foregroundColor(.white.opacity(0.9))
                        }
                    }
                    .padding(.top, 20)
                }

            }
            .padding()
        }
        .onAppear {
            logoScale = 1.0
            textOpacity = 1.0
        }
    }
}

import UIKit

private func presentInviteSheet() {
    let appStoreURL = URL(
        string: "https://apps.apple.com/app/id6756092474"
    )!


    let activityVC = UIActivityViewController(
        activityItems: [appStoreURL],
        applicationActivities: nil
    )

    if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
          let root = scene.windows.first?.rootViewController {

           // ⭐ BẮT BUỘC CHO iPad / Mac Catalyst
           activityVC.popoverPresentationController?.sourceView = root.view
           activityVC.popoverPresentationController?.sourceRect = root.view.bounds

           root.present(activityVC, animated: true)
       }

    if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
       let root = scene.windows.first?.rootViewController {
        root.present(activityVC, animated: true)
    }
}



struct EnhancedOnboardingView_Previews: PreviewProvider {
    static var previews: some View {
        EnhancedOnboardingView()
    }
}

