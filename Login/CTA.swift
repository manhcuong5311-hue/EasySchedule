//
//  CTA.swift
//  Easy Schedule
//
//  Created by Sam Manh Cuong on 16/1/26.
//


import SwiftUI
import Combine

struct FinalOnboardingCTASlide: View {
    @Environment(\.colorScheme) private var scheme

    @Binding var hasSeenOnboarding: Bool
    @State private var showPaywall = false

    var body: some View {
        ZStack {

            // MARK: - TypeAI green background
            LinearGradient(
                colors: scheme == .light
                    ? [
                        Color(red: 0.92, green: 0.98, blue: 0.95),
                        Color.white
                      ]
                    : [
                        Color(red: 14/255, green: 22/255, blue: 18/255),
                        Color(red: 10/255, green: 18/255, blue: 15/255)
                      ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()


            VStack(spacing: 18) {

                Spacer()

                // MARK: - Headline
                Text(String(localized: "final_cta_title"))
                    .font(.system(size: 40, weight: .bold))
                    .tracking(-0.8)
                    .multilineTextAlignment(.center)


                // MARK: - Subheadline
                Text(String(localized: "final_cta_subtitle"))
                    .font(.system(size: 15))
                    .foregroundColor(
                        scheme == .light
                        ? .secondary
                        : .white.opacity(0.75)
                    )
                    .multilineTextAlignment(.center)

                Spacer()

                // MARK: - Primary CTA
                ShareLink(
                    item: URL(string: "https://apps.apple.com/app/id6756092474")!
                ) {
                    Text(String(localized: "final_cta_invite"))
                        .font(.system(size: 17, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 18)
                        .background(Color.accentColor)
                        .foregroundColor(.white)
                        .cornerRadius(18)
                        .shadow(
                            color: Color.black.opacity(scheme == .light ? 0.15 : 0.45),
                            radius: 12,
                            y: 8
                        )
                }


                // MARK: - Secondary CTA
                Button {
                    showPaywall = true
                } label: {
                    Text(String(localized: "final_cta_see_plans"))
                        .font(.system(size: 15))
                        .foregroundColor(
                            scheme == .light
                            ? .secondary
                            : .white.opacity(0.85)
                        )
                        .padding(.top, 4)
                }


                // MARK: - Legal (TypeAI style)
                Text(String(localized: "final_cta_legal"))
                    .font(.system(size: 12))
                    .foregroundColor(.secondary.opacity(0.7))
                    .padding(.top, 6)

                Spacer(minLength: 24)
            }
            .padding(.horizontal, 28)
        }
        .fullScreenCover(isPresented: $showPaywall) {
            PremiumUpgradeSheet(
                preselectProductID: "com.SamCorp.EasySchedule.premium.yearly",
                autoPurchase: false   // đổi true nếu muốn auto mua
            )
            .environmentObject(PremiumStoreViewModel.shared)
            .onDisappear {
                hasSeenOnboarding = true
            }
        }


       
    }
}

