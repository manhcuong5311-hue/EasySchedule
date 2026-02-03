//
//  UIAccentPreset.swift
//  Easy Schedule
//
//  Created by Sam Manh Cuong on 23/1/26.
//
import SwiftUI
import Combine

enum UIAccentPreset: String, CaseIterable {
    case orange
    case blue
    case mint
    case purple
    case graphite
    case green
    case teal
    case coral

    var title: String {
        switch self {
        case .orange:
            return String(localized: "accent.color.orange")
        case .blue:
            return String(localized: "accent.color.blue")
        case .mint:
            return String(localized: "accent.color.mint")
        case .purple:
            return String(localized: "accent.color.purple")
        case .graphite:
            return String(localized: "accent.color.graphite")
        case .green:
            return String(localized: "accent.color.green")
        case .teal:
            return String(localized: "accent.color.teal")
        case .coral:
            return String(localized: "accent.color.coral")

        }
    }


    var hex: String {
        switch self {
        case .orange:   return "#FF9500" // Structured-like
        case .blue:     return "#007AFF" // iOS default
        case .mint:     return "#2AC7BE"
        case .purple:   return "#AF52DE"
        case .graphite: return "#8E8E93"
        case .green:   return "#34C759"
        case .teal:    return "#5AC8FA"
        case .coral:   return "#FF3B30"

        }
    }
}

final class UIAccentStore: ObservableObject {
    @Published var hex: String

    init() {
        self.hex = UserDefaults.standard.string(
            forKey: "ui_accent_color"
        ) ?? "#007AFF" // iOS Blue default

    }

    var color: Color {
        Color(hex: hex)
    }

    func set(hex: String) {
        self.hex = hex
        UserDefaults.standard.set(hex, forKey: "ui_accent_color")
    }
}
