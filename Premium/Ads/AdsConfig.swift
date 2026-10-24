//
// AdsConfig.swift
//
// AdMob IDs + frequency caps. Ads are never shown to users who bought Remove Ads
// (or an old Premium / Pro plan).
//

import Foundation

enum AdsConfig {

    // MARK: - Ad unit IDs
    // AdMob app: ca-app-pub-5982140566133654~9615546773 (GADApplicationIdentifier in Info.plist).
    // Bản DEBUG luôn dùng ID test của Google để không bị AdMob khoá tài khoản vì tự click.

    #if DEBUG
    static let bannerUnitID       = "ca-app-pub-3940256099942544/2934735716"
    static let interstitialUnitID = "ca-app-pub-3940256099942544/4411468910"
    #else
    static let bannerUnitID       = "ca-app-pub-5982140566133654/2339691981"   // ES Banner - Tab bar
    static let interstitialUnitID = "ca-app-pub-5982140566133654/8816725567"   // ES Interstitial - After event created
    #endif

    // MARK: - Frequency caps

    /// Interstitial shows after every Nth event the user creates.
    static let interstitialEveryNEvents = 2

    /// Minimum gap between two interstitials.
    static let minSecondsBetweenFullScreenAds: TimeInterval = 120

    /// Gap between the banner and the floating tab bar.
    static let bannerSpacing: CGFloat = 10
}
