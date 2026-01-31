//
//  Untitled.swift
//  Easy Schedule
//
//  Created by Sam Manh Cuong on 31/1/26.
//
import SwiftUI
import Combine

struct CalendarActionButtonStyle: ViewModifier {

    let showsHint: Bool
    let hintText: String?

    func body(content: Content) -> some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(Color(.systemGray6))
            .foregroundColor(.primary)
            .cornerRadius(12)
            .overlay(alignment: .bottom) {
                if showsHint, let hintText {
                    Text(hintText)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.bottom, 6)
                }
            }
    }
}


extension View {
    func calendarActionStyle(
        showsHint: Bool = false,
        hintText: String? = nil
    ) -> some View {
        modifier(
            CalendarActionButtonStyle(
                showsHint: showsHint,
                hintText: hintText
            )
        )
    }
}

