//
//  LocationManager.swift
//  Easy Schedule
//
//  Created by Sam Manh Cuong on 2/1/26.
//
import SwiftUI
import MapKit
import Combine

final class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {

    private let manager = CLLocationManager()

    @Published var location: CLLocation?
    @Published var authorizationStatus: CLAuthorizationStatus = .notDetermined

    /// Pending one-shot request: completes with a fresh fix, or nil if denied.
    private var oneShot: ((CLLocation?) -> Void)?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        authorizationStatus = manager.authorizationStatus
    }

    var isAuthorized: Bool {
        authorizationStatus == .authorizedWhenInUse ||
        authorizationStatus == .authorizedAlways
    }

    var isDenied: Bool {
        authorizationStatus == .denied || authorizationStatus == .restricted
    }

    /// Warm up: ask permission (first time) and begin acquiring a fix.
    /// Call when the user opens the attachment menu so a location is ready.
    func start() {
        if manager.authorizationStatus == .notDetermined {
            manager.requestWhenInUseAuthorization()
        }
        if isAuthorized || manager.authorizationStatus == .notDetermined {
            manager.startUpdatingLocation()
        }
    }

    /// Request a single fresh fix. Completes on the main thread with the
    /// location, or `nil` when access is denied/restricted.
    func requestOnce(_ completion: @escaping (CLLocation?) -> Void) {
        switch manager.authorizationStatus {
        case .notDetermined:
            oneShot = completion
            manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways:
            if let loc = location {
                completion(loc)
            } else {
                oneShot = completion
                manager.startUpdatingLocation()
            }
        default:
            completion(nil)
        }
    }

    private func finishOneShot(_ loc: CLLocation?) {
        guard let cb = oneShot else { return }
        oneShot = nil
        cb(loc)
    }

    // MARK: - CLLocationManagerDelegate

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus
        if isAuthorized {
            manager.startUpdatingLocation()
        } else if isDenied {
            finishOneShot(nil)
        }
    }

    func locationManager(
        _ manager: CLLocationManager,
        didUpdateLocations locations: [CLLocation]
    ) {
        guard let loc = locations.last else { return }
        location = loc
        finishOneShot(loc)
        manager.stopUpdatingLocation()   // 🔒 dừng sau khi có
    }

    func locationManager(
        _ manager: CLLocationManager,
        didFailWithError error: Error
    ) {
        print("Location error:", error)
        finishOneShot(location)
    }
}
