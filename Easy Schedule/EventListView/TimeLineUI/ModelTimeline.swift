//
//  Model.swift
//  Easy Schedule
//
//  Created by Sam Manh Cuong on 26/1/26.
//

import CoreFoundation
import CoreGraphics

import SwiftUI

enum TimelineLayout {

    // MARK: - Time scale
    static let hourHeight: CGFloat = 64
    static let minuteHeight: CGFloat = hourHeight / 60

    // MARK: - Hour column
    static let hourLabelWidth: CGFloat = 48
    static let spineWidth: CGFloat = 1

    // MARK: - Event
    static let dotSize: CGFloat = 6
    static let blockCornerRadius: CGFloat = 12

    // ⭐ QUAN TRỌNG – CONTENT OFFSET
    static let contentPadding: CGFloat = 12
}
