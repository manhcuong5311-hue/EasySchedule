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

    /// Ask again after the 3rd, 10th and 30th successful event — happy moments.
    /// Apple still caps the system prompt to 3 times a year.
    private let successMilestones = [3, 10, 30]
    private let cooldownDays = 120

    private let hasRequestedKey = "hasRequestedReview"
    private let lastPromptKey = "review_last_prompt"
    private let successCountKey = "review_success_count"

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

        prompt(requestReview)
    }

    func requestAfterEventSuccess(_ requestReview: RequestReviewAction) {
        let count = UserDefaults.standard.integer(forKey: successCountKey) + 1
        UserDefaults.standard.set(count, forKey: successCountKey)

        guard successMilestones.contains(count),
              daysSinceFirstLaunch() >= minimumDays,
              cooldownPassed() else { return }
        prompt(requestReview)
    }

    func requestAfterPremiumUpgrade(_ requestReview: RequestReviewAction) {
        guard daysSinceFirstLaunch() >= minimumDays, cooldownPassed() else { return }
        prompt(requestReview)
    }

    // MARK: - Helpers

    private func prompt(_ requestReview: RequestReviewAction) {
        requestReview()
        UserDefaults.standard.set(true, forKey: hasRequestedKey)
        UserDefaults.standard.set(Date(), forKey: lastPromptKey)
        AppAnalytics.log(AppAnalyticsEvent.reviewPromptShown)
    }

    private func daysSinceFirstLaunch() -> Int {
        guard let firstLaunch = UserDefaults.standard.object(forKey: "firstLaunchDate") as? Date else { return 0 }
        return Calendar.current.dateComponents([.day], from: firstLaunch, to: Date()).day ?? 0
    }

    private func cooldownPassed() -> Bool {
        guard let last = UserDefaults.standard.object(forKey: lastPromptKey) as? Date else { return true }
        let days = Calendar.current.dateComponents([.day], from: last, to: Date()).day ?? 0
        return days >= cooldownDays
    }
}
