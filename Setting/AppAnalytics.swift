//
//  AppAnalytics.swift
//  Easy Schedule
//
//  Thin wrapper over Firebase Analytics so call sites stay one line and event
//  names live in one place (`AppAnalyticsEvent`).
//
//  Usage:
//      AppAnalytics.log(AppAnalyticsEvent.eventCreated, ["source": "quick_add"])
//
//  Param values are normalised to String / Int (Bool → 0/1, other integers →
//  Int, everything else → String, max 100 chars) to match Firebase limits.
//

import Foundation
import FirebaseAnalytics

nonisolated enum AppAnalytics {

    /// Logs a custom event. Safe to call from any thread.
    static func log(_ name: String, _ params: [String: Any] = [:]) {
        let cleaned = params.compactMapValues(normalize)
        Analytics.logEvent(name, parameters: cleaned.isEmpty ? nil : cleaned)
    }

    /// Firebase accepts String / Int / Double; this app keeps to String / Int.
    private static func normalize(_ value: Any) -> Any? {
        switch value {
        case let v as String:         return String(v.prefix(maxValueLength))
        case let v as Bool:           return v ? 1 : 0
        case let v as Int:            return v
        case let v as any BinaryInteger: return Int(clamping: v)
        case let v as Double:         return v.isFinite ? Int(v.rounded()) : nil
        case let v as Float:          return v.isFinite ? Int(v.rounded()) : nil
        case let v as CustomStringConvertible:
            return String(v.description.prefix(maxValueLength))
        default:
            return nil
        }
    }

    /// Firebase truncates string param values longer than 100 characters.
    private static let maxValueLength = 100
}

/// Event names (snake_case, ≤ 40 chars, as Firebase requires).
nonisolated enum AppAnalyticsEvent {
    static let eventCreated        = "event_created"
    static let bookingCreated      = "booking_created"
    static let proposalSent        = "proposal_sent"
    static let proposalVoted       = "proposal_voted"
    static let quickReplySent      = "quick_reply_sent"
    static let paywallShown        = "paywall_shown"
    static let rewardedAdCompleted = "rewarded_ad_completed"
    static let interstitialShown   = "interstitial_shown"
    static let bookingLinkSet      = "booking_link_set"
    static let bookingHoursSaved   = "booking_hours_saved"
    static let reviewPromptShown   = "review_prompt_shown"
    static let quickAddParsed      = "quick_add_parsed"
}
