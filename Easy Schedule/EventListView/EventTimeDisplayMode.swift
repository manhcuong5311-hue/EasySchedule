//
//  EventTimeDisplayMode.swift
//  Easy Schedule
//
//  Created by Sam Manh Cuong on 22/1/26.
//
import SwiftUI
import Combine

enum EventTimeDisplayMode: String, CaseIterable {
    case startTime
    case timeRange
    case duration

    var title: String {
        switch self {
        case .startTime: return "Start time"
        case .timeRange: return "Time range"
        case .duration:  return "Duration"
        }
    }
}
