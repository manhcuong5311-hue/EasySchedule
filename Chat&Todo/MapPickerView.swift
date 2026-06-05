//
//  MapPickerView.swift
//  Easy Schedule
//
//  Created by Sam Manh Cuong on 2/1/26.
//

import SwiftUI
import MapKit

struct MapPickerView: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject var locationManager: LocationManager
    var onPick: (CLLocationCoordinate2D) -> Void

    // iOS 17+ camera + the live center we actually send (tracks panning).
    @State private var position: MapCameraPosition
    @State private var centerCoord: CLLocationCoordinate2D
    @State private var address: String = ""
    @State private var isGeocoding = false

    private let geocoder = CLGeocoder()
    private static let fallback = CLLocationCoordinate2D(latitude: 10.7626, longitude: 106.6601)

    init(
        locationManager: LocationManager,
        onPick: @escaping (CLLocationCoordinate2D) -> Void
    ) {
        _locationManager = ObservedObject(wrappedValue: locationManager)
        self.onPick = onPick

        let coord = locationManager.location?.coordinate ?? Self.fallback
        _position = State(initialValue: .region(
            MKCoordinateRegion(
                center: coord,
                span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
            )
        ))
        _centerCoord = State(initialValue: coord)
    }

    var body: some View {
        ZStack {
            Map(position: $position) {
                UserAnnotation()
            }
            .ignoresSafeArea()
            // Keep the live center in sync with panning — fixes the old bug
            // where picking after a pan sent a stale (or nil) coordinate.
            // (default frequency is .onEnded — fires when the user stops panning)
            .onMapCameraChange { ctx in
                centerCoord = ctx.region.center
                reverseGeocode(ctx.region.center)
            }

            // Fixed centre marker (its tip points at the map centre).
            Image(systemName: "mappin.circle.fill")
                .font(.system(size: 40))
                .foregroundStyle(.red)
                .shadow(color: .black.opacity(0.3), radius: 3, y: 1)
                .offset(y: -20)
                .allowsHitTesting(false)

            VStack(spacing: 0) {
                HStack {
                    circleButton(system: "xmark") { dismiss() }
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)

                Spacer()

                if locationManager.location != nil {
                    HStack {
                        Spacer()
                        circleButton(system: "location.fill", tint: .blue) {
                            recenterOnUser()
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
                }

                locationCard
            }
        }
        .onAppear { reverseGeocode(centerCoord) }
    }

    // MARK: - Bottom card
    private var locationCard: some View {
        VStack(spacing: 14) {
            HStack(spacing: 12) {
                Image(systemName: "mappin.and.ellipse")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.red)
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(Color.red.opacity(0.12)))

                VStack(alignment: .leading, spacing: 2) {
                    Text(String(localized: "selected_location"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(address.isEmpty ? String(localized: "fetching_address") : address)
                        .font(.subheadline.weight(.medium))
                        .lineLimit(2)
                        .redacted(reason: (isGeocoding && address.isEmpty) ? .placeholder : [])
                }
                Spacer(minLength: 0)
            }

            Button {
                onPick(centerCoord)
                dismiss()
            } label: {
                Text(String(localized: "send_this_location"))
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color.blue)
                    )
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color(.systemBackground))
        )
        .padding(.horizontal, 12)
        .padding(.bottom, 16)
        .shadow(color: .black.opacity(0.12), radius: 12, y: -2)
    }

    private func circleButton(
        system: String,
        tint: Color = .primary,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: system)
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(tint)
                .frame(width: 42, height: 42)
                .background(Circle().fill(Color(.systemBackground)))
                .shadow(color: .black.opacity(0.18), radius: 5, y: 2)
        }
    }

    // MARK: - Logic
    private func recenterOnUser() {
        guard let loc = locationManager.location else { return }
        withAnimation {
            position = .region(
                MKCoordinateRegion(
                    center: loc.coordinate,
                    span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
                )
            )
        }
        centerCoord = loc.coordinate
        reverseGeocode(loc.coordinate)
    }

    private func reverseGeocode(_ coord: CLLocationCoordinate2D) {
        isGeocoding = true
        geocoder.cancelGeocode()
        geocoder.reverseGeocodeLocation(
            CLLocation(latitude: coord.latitude, longitude: coord.longitude)
        ) { places, _ in
            DispatchQueue.main.async {
                isGeocoding = false
                guard let p = places?.first else { return }
                let parts = [p.name, p.subLocality, p.locality, p.administrativeArea]
                    .compactMap { $0 }
                address = parts.isEmpty
                    ? String(localized: "location_sent")
                    : parts.joined(separator: ", ")
            }
        }
    }
}
