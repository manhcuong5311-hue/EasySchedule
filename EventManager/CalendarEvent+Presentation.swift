//
//  CalendarEvent+Presentation.swift
//  Easy Schedule
//
//  Created by Sam Manh Cuong on 2/1/26.
//

import Foundation

extension CalendarEvent {

    var originLabel: String {
        switch origin {
        case .myEvent:
            return String(localized: "origin_my_event")
        case .createdForMe:
            return String(localized: "origin_created_for_me")
        case .iCreatedForOther:
            return String(localized: "origin_i_created_for_other")
        case .busySlot:
            return String(localized: "origin_busy")
        }
    }
}
