//
//  TitleShadow.swift
//  Easy Schedule
//
//  Created by Sam Manh Cuong on 23/1/26.
//
import SwiftUI

struct TitleShadow {

    static func primary(_ scheme: ColorScheme) -> some ViewModifier {
        TitleShadowModifier(
            glow: scheme == .dark
                ? Color.white.opacity(0.35)
                : Color.clear,
            depth: scheme == .dark
                ? Color.white.opacity(0.15)
                : Color.black.opacity(0.30)
        )
    }
}

private struct TitleShadowModifier: ViewModifier {
    let glow: Color
    let depth: Color

    func body(content: Content) -> some View {
        content
            // glow nhẹ (dark mode)
            .shadow(color: glow, radius: 6, y: 0)
            // depth chính
            .shadow(color: depth, radius: 4, y: 3)
            // depth phụ
            .shadow(
                color: depth.opacity(0.4),
                radius: 1,
                y: 1
            )
    }
}

import SwiftUI

struct HeaderTitleShadow: ViewModifier {

    let scheme: ColorScheme
    let isAccent: Bool

    func body(content: Content) -> some View {

        content
            // ===== HIGHLIGHT (ánh sáng từ trên) =====
            .shadow(
                color: scheme == .dark
                    ? Color.white.opacity(0.22)
                    : Color.clear,
                radius: 2,
                y: -1
            )

            // ===== DEPTH CHÍNH =====
            .shadow(
                color: scheme == .dark
                    ? Color.black.opacity(0.55)
                    : Color.black.opacity(0.28),
                radius: 6,
                y: 4
            )

            // ===== DEPTH PHỤ =====
            .shadow(
                color: scheme == .dark
                    ? Color.black.opacity(0.25)
                    : Color.black.opacity(0.12),
                radius: 1,
                y: 1
            )
    }
}

extension View {
    func headerShadow(
        scheme: ColorScheme,
        isAccent: Bool = false
    ) -> some View {
        self.modifier(
            HeaderTitleShadow(
                scheme: scheme,
                isAccent: isAccent
            )
        )
    }
}


import SwiftUI

struct DayCellShadow: ViewModifier {

    let scheme: ColorScheme
    let isSelected: Bool

    func body(content: Content) -> some View {
        content

            // ===== WHITE HIGHLIGHT (THIẾU) =====
            .shadow(
                color: (scheme == .dark && isSelected)
                    ? Color.white.opacity(0.28)
                    : Color.clear,
                radius: 2,
                y: -1
            )

            // ===== SOFT LIFT =====
            .shadow(
                color: (scheme == .dark && isSelected)
                    ? Color.white.opacity(0.16)
                    : Color.clear,
                radius: 4,
                y: 0
            )

            // ===== MAIN DEPTH =====
            .shadow(
                color: isSelected
                    ? (scheme == .dark
                        ? Color.black.opacity(0.45)
                        : Color.black.opacity(0.28))
                    : .clear,
                radius: 5,
                y: 3
            )

            // ===== MICRO DEPTH =====
            .shadow(
                color: isSelected
                    ? (scheme == .dark
                        ? Color.black.opacity(0.20)
                        : Color.black.opacity(0.12))
                    : .clear,
                radius: 1,
                y: 1
            )
    }
}


extension View {
    func dayCellShadow(
        scheme: ColorScheme,
        isSelected: Bool
    ) -> some View {
        self.modifier(
            DayCellShadow(
                scheme: scheme,
                isSelected: isSelected
            )
        )
    }
}
