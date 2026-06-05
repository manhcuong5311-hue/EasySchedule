//
//  EventPresets.swift
//  Easy Schedule
//
//  Curated "quick add" presets shown as a horizontal carousel at the top of
//  AddEventView. Tapping a preset pre-fills title / icon / color / duration and,
//  when set, a suggested time of day — so creating a routine event is one tap.
//
//  Ported from the sibling Structify app. Display names + category labels are
//  localized (en/vi) via keys in Localizable.xcstrings.
//

import SwiftUI

struct EventPreset: Identifiable {
    let id = UUID()
    let titleKey: String              // localization key for the display name
    let icon: String                  // SF Symbol
    let colorHex: String
    let category: EventCategory
    let durationMinutes: Int          // typical length for this kind of event
    let suggestedMinutes: Int?        // optional time of day (minutes from midnight); nil = keep current

    var displayName: String {
        String(localized: String.LocalizationValue(titleKey))
    }
}

enum EventCategory: String, CaseIterable, Identifiable {
    case work, personal, health, learning, lifestyle
    var id: String { rawValue }

    var label: String {
        // Build the key as a plain String FIRST. Passing "preset_cat_\(rawValue)"
        // directly into String.LocalizationValue uses its string-interpolation
        // initializer → lookup key becomes "preset_cat_%@" (missing) → shows the
        // raw key. Materializing the String forces init(_ value:) → real key.
        let key = "preset_cat_\(rawValue)"
        return String(localized: String.LocalizationValue(key))
    }

    var icon: String {
        switch self {
        case .work:      return "briefcase.fill"
        case .personal:  return "person.fill"
        case .health:    return "heart.fill"
        case .learning:  return "book.fill"
        case .lifestyle: return "house.fill"
        }
    }

    var accent: Color {
        switch self {
        case .work:      return Color(red: 0.45, green: 0.55, blue: 0.95)
        case .personal:  return Color(red: 0.95, green: 0.62, blue: 0.45)
        case .health:    return Color(red: 0.95, green: 0.45, blue: 0.45)
        case .learning:  return Color(red: 0.62, green: 0.42, blue: 0.85)
        case .lifestyle: return Color(red: 0.55, green: 0.70, blue: 0.50)
        }
    }
}

enum EventPresetCatalog {
    static let all: [EventPreset] = [

        // ─── Work ───
        EventPreset(titleKey: "preset_meeting",      icon: "person.2.fill",                colorHex: "#5B82F0", category: .work,     durationMinutes: 60, suggestedMinutes: 10 * 60),
        EventPreset(titleKey: "preset_call",         icon: "phone.fill",                   colorHex: "#3DB5B0", category: .work,     durationMinutes: 30, suggestedMinutes: nil),
        EventPreset(titleKey: "preset_standup",      icon: "figure.stand",                 colorHex: "#6A7AE0", category: .work,     durationMinutes: 30, suggestedMinutes: 9 * 60),
        EventPreset(titleKey: "preset_interview",    icon: "person.text.rectangle.fill",   colorHex: "#3F4D7A", category: .work,     durationMinutes: 60, suggestedMinutes: nil),
        EventPreset(titleKey: "preset_focus_block",  icon: "laptopcomputer",               colorHex: "#7059D6", category: .work,     durationMinutes: 90, suggestedMinutes: 9 * 60),
        EventPreset(titleKey: "preset_review",       icon: "checklist",                    colorHex: "#4B82C0", category: .work,     durationMinutes: 60, suggestedMinutes: nil),
        EventPreset(titleKey: "preset_presentation", icon: "chart.bar.fill",               colorHex: "#E07A4B", category: .work,     durationMinutes: 60, suggestedMinutes: nil),

        // ─── Personal ───
        EventPreset(titleKey: "preset_lunch",        icon: "fork.knife",                   colorHex: "#7BC15B", category: .personal, durationMinutes: 60, suggestedMinutes: 12 * 60),
        EventPreset(titleKey: "preset_coffee",       icon: "cup.and.saucer.fill",          colorHex: "#A86B3F", category: .personal, durationMinutes: 30, suggestedMinutes: nil),
        EventPreset(titleKey: "preset_dinner",       icon: "fork.knife.circle.fill",       colorHex: "#4FA86F", category: .personal, durationMinutes: 90, suggestedMinutes: 19 * 60),
        EventPreset(titleKey: "preset_errands",      icon: "bag.fill",                     colorHex: "#E5A23A", category: .personal, durationMinutes: 60, suggestedMinutes: nil),
        EventPreset(titleKey: "preset_shopping",     icon: "cart.fill",                    colorHex: "#EC6C8A", category: .personal, durationMinutes: 90, suggestedMinutes: nil),
        EventPreset(titleKey: "preset_appointment",  icon: "calendar.badge.clock",         colorHex: "#D85B82", category: .personal, durationMinutes: 60, suggestedMinutes: nil),
        EventPreset(titleKey: "preset_date_night",   icon: "heart.fill",                   colorHex: "#E26B8E", category: .personal, durationMinutes: 120, suggestedMinutes: 19 * 60),

        // ─── Health ───
        EventPreset(titleKey: "preset_gym",          icon: "dumbbell.fill",                colorHex: "#EA5757", category: .health,   durationMinutes: 60, suggestedMinutes: 7 * 60),
        EventPreset(titleKey: "preset_workout",      icon: "figure.run",                   colorHex: "#FF8A3A", category: .health,   durationMinutes: 60, suggestedMinutes: nil),
        EventPreset(titleKey: "preset_yoga",         icon: "figure.yoga",                  colorHex: "#E07AAE", category: .health,   durationMinutes: 60, suggestedMinutes: nil),
        EventPreset(titleKey: "preset_walk",         icon: "figure.walk",                  colorHex: "#4CD980", category: .health,   durationMinutes: 30, suggestedMinutes: nil),
        EventPreset(titleKey: "preset_doctor",       icon: "cross.case.fill",              colorHex: "#D8645B", category: .health,   durationMinutes: 30, suggestedMinutes: nil),

        // ─── Learning ───
        EventPreset(titleKey: "preset_class",        icon: "graduationcap.fill",           colorHex: "#4B82C0", category: .learning, durationMinutes: 90, suggestedMinutes: nil),
        EventPreset(titleKey: "preset_study",        icon: "book.fill",                    colorHex: "#9C6CDC", category: .learning, durationMinutes: 60, suggestedMinutes: nil),
        EventPreset(titleKey: "preset_reading",      icon: "book.closed.fill",             colorHex: "#6A7AB0", category: .learning, durationMinutes: 30, suggestedMinutes: nil),
        EventPreset(titleKey: "preset_course",       icon: "play.rectangle.fill",          colorHex: "#A36AE0", category: .learning, durationMinutes: 60, suggestedMinutes: nil),

        // ─── Lifestyle ───
        EventPreset(titleKey: "preset_commute",      icon: "car.fill",                     colorHex: "#7B8794", category: .lifestyle, durationMinutes: 30, suggestedMinutes: nil),
        EventPreset(titleKey: "preset_travel",       icon: "airplane",                     colorHex: "#5BA8D6", category: .lifestyle, durationMinutes: 60, suggestedMinutes: nil),
        EventPreset(titleKey: "preset_break",        icon: "pause.circle.fill",            colorHex: "#9CD0E5", category: .lifestyle, durationMinutes: 30, suggestedMinutes: nil),
        EventPreset(titleKey: "preset_family_time",  icon: "house.fill",                   colorHex: "#7BC15B", category: .lifestyle, durationMinutes: 60, suggestedMinutes: nil)
    ]

    static func filtered(by category: EventCategory?) -> [EventPreset] {
        guard let category else { return all }
        return all.filter { $0.category == category }
    }
}
