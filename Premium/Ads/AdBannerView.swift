//
// AdBannerView.swift
//
// Small standard AdMob banner (320×50). Renders nothing for Premium/Pro users
// and collapses to 0 height until an ad has actually loaded.
//

import SwiftUI
import UIKit
import GoogleMobileAds

struct AdBannerView: View {

    @ObservedObject private var ads = AdsManager.shared

    var body: some View {
        if ads.adsEnabled && ads.isReady {
            let size = AdSizeBanner.size

            BannerRepresentable()
                .frame(width: size.width, height: ads.bannerHeight > 0 ? size.height : 0)
                .clipped()
        }
    }
}

private struct BannerRepresentable: UIViewRepresentable {

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> BannerView {
        let banner = BannerView(adSize: AdSizeBanner)
        banner.adUnitID = AdsConfig.bannerUnitID
        banner.delegate = context.coordinator
        banner.load(Request())
        return banner
    }

    func updateUIView(_ banner: BannerView, context: Context) {}

    final class Coordinator: NSObject, BannerViewDelegate {

        func bannerViewDidReceiveAd(_ bannerView: BannerView) {
            AdsManager.shared.bannerDidLoad(height: bannerView.adSize.size.height)
        }

        func bannerView(_ bannerView: BannerView, didFailToReceiveAdWithError error: Error) {
            print("⚠️ Banner load failed:", error.localizedDescription)
            AdsManager.shared.bannerDidFail()
        }
    }
}
