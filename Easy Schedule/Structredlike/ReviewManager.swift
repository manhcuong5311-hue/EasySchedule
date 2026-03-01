//
//  ReviewManager.swift
//  Easy Schedule
//
//  Created by Sam Manh Cuong on 1/3/26.
//
import StoreKit
import SwiftUI
import Combine

final class ReviewManager {

    static let shared = ReviewManager()

    private let minimumDays = 3
    private let minimumLaunchCount = 5

    private let hasRequestedKey = "hasRequestedReview"

    func tryRequestReview(_ requestReview: RequestReviewAction) {

        guard !UserDefaults.standard.bool(forKey: hasRequestedKey) else {
            return
        }

        let launchCount = UserDefaults.standard.integer(forKey: "launchCount") + 1
        UserDefaults.standard.set(launchCount, forKey: "launchCount")

        if UserDefaults.standard.object(forKey: "firstLaunchDate") == nil {
            UserDefaults.standard.set(Date(), forKey: "firstLaunchDate")
        }

        guard launchCount >= minimumLaunchCount else { return }

        guard let firstLaunch = UserDefaults.standard.object(forKey: "firstLaunchDate") as? Date else { return }

        let days = Calendar.current.dateComponents([.day], from: firstLaunch, to: Date()).day ?? 0

        guard days >= minimumDays else { return }

        requestReview()
        UserDefaults.standard.set(true, forKey: hasRequestedKey)
    }

    func requestAfterEventSuccess(_ requestReview: RequestReviewAction) {
        guard eligibleByDays() else { return }
        requestReview()
        UserDefaults.standard.set(true, forKey: hasRequestedKey)
    }

    func requestAfterPremiumUpgrade(_ requestReview: RequestReviewAction) {
        guard eligibleByDays() else { return }
        requestReview()
        UserDefaults.standard.set(true, forKey: hasRequestedKey)
    }

    private func eligibleByDays() -> Bool {
        guard !UserDefaults.standard.bool(forKey: hasRequestedKey) else { return false }
        guard let firstLaunch = UserDefaults.standard.object(forKey: "firstLaunchDate") as? Date else { return false }

        let days = Calendar.current.dateComponents([.day], from: firstLaunch, to: Date()).day ?? 0
        return days >= minimumDays
    }
}
