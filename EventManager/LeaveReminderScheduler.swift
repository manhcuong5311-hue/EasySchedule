//
//  LeaveReminderScheduler.swift
//  Easy Schedule
//
//  "Đến giờ đi rồi": for appointments with a location in the next 24h, ask
//  Apple Maps for the driving time from the last known position and remind
//  the user to leave (travel time + 10 min buffer) before the start.
//  Only runs when location permission was already granted — never prompts.
//

import Foundation
import CoreLocation
import MapKit
import UserNotifications

@MainActor
enum LeaveReminderScheduler {

    static let identifierPrefix = "leave-"
    private static let bufferMinutes: Double = 10

    static func schedule(for events: [CalendarEvent]) {
        let now = Date()
        let upcoming = events.filter {
            $0.location != nil &&
            $0.startTime > now &&
            $0.startTime < now.addingTimeInterval(24 * 3600)
        }
        guard !upcoming.isEmpty else { return }

        let manager = CLLocationManager()
        let status = manager.authorizationStatus
        guard status == .authorizedWhenInUse || status == .authorizedAlways,
              let origin = manager.location
        else { return }

        Task {
            for event in upcoming {
                await scheduleOne(event, from: origin)
            }
        }
    }

    private static func scheduleOne(_ event: CalendarEvent, from origin: CLLocation) async {
        guard let place = event.location else { return }

        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: origin.coordinate))
        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: place.coordinate))
        request.transportType = .automobile

        guard let eta = try? await MKDirections(request: request).calculateETA() else { return }
        let travel = eta.expectedTravelTime
        // Very close by → the normal reminder is enough.
        guard travel >= 5 * 60 else { return }

        let fireDate = event.startTime.addingTimeInterval(-(travel + bufferMinutes * 60))
        guard fireDate > Date().addingTimeInterval(60) else { return }

        let minutes = Int((travel / 60).rounded())
        let content = UNMutableNotificationContent()
        content.title = String(localized: "leave_reminder_title")
        content.body = String(format: String(localized: "leave_reminder_body_format"),
                              minutes, place.name, event.title,
                              event.startTime.formatted(date: .omitted, time: .shortened))
        content.sound = .default
        content.userInfo = ["type": "leave_reminder", "eventId": event.id]
        if event.isShared {
            content.categoryIdentifier = QuickReply.sharedEventCategory
        }

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: fireDate.timeIntervalSinceNow, repeats: false)
        let request2 = UNNotificationRequest(identifier: identifierPrefix + event.id, content: content, trigger: trigger)
        try? await UNUserNotificationCenter.current().add(request2)
    }
}
