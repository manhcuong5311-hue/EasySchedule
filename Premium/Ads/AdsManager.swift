//
// AdsManager.swift
//
// Google AdMob for FREE users only: banner, interstitial after creating events,
// and a rewarded ad that unlocks one extra event for a day.
// Startup order: GDPR consent (UMP, EEA/UK only) → ATT prompt → start SDK → preload.
//

import SwiftUI
import UIKit
import Combine
import AppTrackingTransparency
import GoogleMobileAds
import UserMessagingPlatform

@MainActor
final class AdsManager: NSObject, ObservableObject {

    static let shared = AdsManager()

    /// Free tier resolved → ads allowed. Premium/Pro → always false.
    @Published private(set) var adsEnabled = false
    /// Consent + ATT done and the SDK is started.
    @Published private(set) var isReady = false
    @Published private(set) var isRewardedReady = false
    /// Height of the loaded banner (0 while loading / no fill / ads off).
    @Published private(set) var bannerHeight: CGFloat = 0
    /// EEA/UK users must be able to reopen the consent form (shown in Settings).
    @Published private(set) var privacyOptionsRequired = false

    /// Bottom space screens must keep free so the banner never covers content.
    var bannerInset: CGFloat {
        adsEnabled && bannerHeight > 0 ? bannerHeight + AdsConfig.bannerSpacing : 0
    }

    private var uiReady = false
    private var isStarting = false

    private var interstitial: InterstitialAd?
    private var rewarded: RewardedAd?
    private var isLoadingInterstitial = false
    private var isLoadingRewarded = false

    private var eventsSinceInterstitial = 0
    private var lastFullScreenAdAt: Date?
    private var rewardEarned = false
    private var onRewardDismissed: (() -> Void)?

    private var cancellables = Set<AnyCancellable>()

    private override init() {
        super.init()

        let premium = PremiumStoreViewModel.shared
        premium.$isLoaded
            .combineLatest(premium.$tier)
            .map { isLoaded, tier in isLoaded && tier == .free }
            .removeDuplicates()
            .sink { [weak self] enabled in self?.setAdsEnabled(enabled) }
            .store(in: &cancellables)
    }

    // MARK: - Lifecycle

    /// Call once the main UI is on screen (after login + onboarding), so the
    /// consent form / ATT prompt never cover the login flow.
    func activate() {
        uiReady = true
        startIfNeeded()
    }

    private func setAdsEnabled(_ enabled: Bool) {
        adsEnabled = enabled

        if enabled {
            startIfNeeded()
        } else {
            // Vừa nâng cấp Premium → bỏ hết quảng cáo đã tải
            interstitial = nil
            rewarded = nil
            isRewardedReady = false
            bannerHeight = 0
        }
    }

    private func startIfNeeded() {
        guard adsEnabled, uiReady, !isStarting else { return }

        if isReady {
            preloadFullScreenAds()
            return
        }

        isStarting = true
        Task {
            // Cho UI ổn định rồi mới hiện form đồng ý / popup ATT
            try? await Task.sleep(nanoseconds: 1_500_000_000)

            await gatherConsent()
            await requestTrackingAuthorization()

            defer { isStarting = false }
            guard ConsentInformation.shared.canRequestAds, adsEnabled else { return }

            _ = await MobileAds.shared.start()
            isReady = true
            preloadFullScreenAds()
        }
    }

    // MARK: - Consent (GDPR) + ATT

    private func gatherConsent() async {
        do {
            try await ConsentInformation.shared.requestConsentInfoUpdate(with: RequestParameters())
            try await ConsentForm.loadAndPresentIfRequired(from: nil)
        } catch {
            // Lỗi mạng… vẫn dùng consent của lần trước nếu có (canRequestAds)
            print("⚠️ UMP consent error:", error.localizedDescription)
        }
        privacyOptionsRequired =
            ConsentInformation.shared.privacyOptionsRequirementStatus == .required
    }

    private func requestTrackingAuthorization() async {
        guard ATTrackingManager.trackingAuthorizationStatus == .notDetermined,
              UIApplication.shared.applicationState == .active
        else { return }
        _ = await ATTrackingManager.requestTrackingAuthorization()
    }

    /// Settings → "Ad privacy choices" (only shown when `privacyOptionsRequired`).
    func presentPrivacyOptions() {
        Task {
            do {
                try await ConsentForm.presentPrivacyOptionsForm(from: nil)
            } catch {
                print("⚠️ UMP privacy options error:", error.localizedDescription)
            }
        }
    }

    // MARK: - Banner callbacks (AdBannerView)

    func bannerDidLoad(height: CGFloat) {
        bannerHeight = height
    }

    func bannerDidFail() {
        bannerHeight = 0
    }

    // MARK: - Interstitial

    /// Call after the user successfully creates an event.
    /// Returns true if an ad was presented (caller should skip other prompts).
    @discardableResult
    func showInterstitialAfterEventCreated() -> Bool {
        guard adsEnabled, isReady else { return false }

        eventsSinceInterstitial += 1
        guard eventsSinceInterstitial >= AdsConfig.interstitialEveryNEvents,
              !isFullScreenAdOnCooldown
        else { return false }

        guard let ad = interstitial, let vc = Self.topViewController() else {
            loadInterstitial()
            return false
        }

        interstitial = nil
        eventsSinceInterstitial = 0
        lastFullScreenAdAt = Date()
        ad.present(from: vc)
        AppAnalytics.log(AppAnalyticsEvent.interstitialShown)
        return true
    }

    private func loadInterstitial() {
        guard adsEnabled, isReady, interstitial == nil, !isLoadingInterstitial else { return }
        isLoadingInterstitial = true

        Task {
            defer { isLoadingInterstitial = false }
            do {
                let ad = try await InterstitialAd.load(with: AdsConfig.interstitialUnitID, request: Request())
                ad.fullScreenContentDelegate = self
                interstitial = adsEnabled ? ad : nil
            } catch {
                print("⚠️ Interstitial load failed:", error.localizedDescription)
            }
        }
    }

    // MARK: - Rewarded

    /// Free user hit the daily limit on `date` → can we offer "watch an ad for +1 event"?
    func canOfferRewardedEvent(for date: Date) -> Bool {
        adsEnabled && isRewardedReady && RewardedEventBonus.canGrant(for: date)
    }

    /// Shows the rewarded ad. `onReward` runs AFTER the ad is closed, and only if
    /// the user watched it to the end. Returns false if nothing could be shown.
    @discardableResult
    func showRewarded(onReward: @escaping () -> Void) -> Bool {
        guard adsEnabled, let ad = rewarded, let vc = Self.topViewController() else {
            loadRewarded()
            return false
        }

        rewarded = nil
        isRewardedReady = false
        rewardEarned = false
        onRewardDismissed = onReward
        lastFullScreenAdAt = Date()

        ad.present(from: vc) { [weak self] in
            self?.rewardEarned = true
            AppAnalytics.log(AppAnalyticsEvent.rewardedAdCompleted)
        }
        return true
    }

    private func loadRewarded() {
        guard adsEnabled, isReady, rewarded == nil, !isLoadingRewarded else { return }
        isLoadingRewarded = true

        Task {
            defer { isLoadingRewarded = false }
            do {
                let ad = try await RewardedAd.load(with: AdsConfig.rewardedUnitID, request: Request())
                ad.fullScreenContentDelegate = self
                rewarded = adsEnabled ? ad : nil
                isRewardedReady = rewarded != nil
            } catch {
                print("⚠️ Rewarded load failed:", error.localizedDescription)
            }
        }
    }

    // MARK: - Helpers

    private func preloadFullScreenAds() {
        loadInterstitial()
        loadRewarded()
    }

    private var isFullScreenAdOnCooldown: Bool {
        guard let last = lastFullScreenAdAt else { return false }
        return Date().timeIntervalSince(last) < AdsConfig.minSecondsBetweenFullScreenAds
    }

    private func finishRewardedFlow() {
        let callback = rewardEarned ? onRewardDismissed : nil
        onRewardDismissed = nil
        rewardEarned = false
        callback?()
    }

    private static func topViewController() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let scene = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
        var top = scene?.keyWindow?.rootViewController
        while let presented = top?.presentedViewController, !presented.isBeingDismissed {
            top = presented
        }
        return top
    }
}

// MARK: - FullScreenContentDelegate

extension AdsManager: FullScreenContentDelegate {

    func adDidDismissFullScreenContent(_ ad: FullScreenPresentingAd) {
        if ad is RewardedAd {
            finishRewardedFlow()
        }
        preloadFullScreenAds()
    }

    func ad(_ ad: FullScreenPresentingAd,
            didFailToPresentFullScreenContentWithError error: Error) {
        print("⚠️ Full-screen ad failed to present:", error.localizedDescription)
        if ad is RewardedAd {
            finishRewardedFlow()
        }
        preloadFullScreenAds()
    }
}
