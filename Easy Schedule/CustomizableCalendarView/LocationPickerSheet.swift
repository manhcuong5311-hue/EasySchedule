//
//  LocationPickerSheet.swift
//  Easy Schedule
//
//  Pick where an appointment happens: search Apple Maps (with autocomplete)
//  or use the current position.
//

import SwiftUI
import MapKit
import Combine

struct LocationPickerSheet: View {

    var onPick: (EventLocation) -> Void

    @Environment(\.dismiss) private var dismiss
    @StateObject private var search = PlaceSearchModel()
    @StateObject private var locationManager = LocationManager()
    @State private var isResolving = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        useCurrentLocation()
                    } label: {
                        Label(String(localized: "location_use_current"), systemImage: "location.fill")
                    }
                    .disabled(isResolving)
                }

                if !search.results.isEmpty {
                    Section {
                        ForEach(search.results, id: \.self) { item in
                            Button {
                                resolve(item)
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.title).foregroundStyle(.primary)
                                    if !item.subtitle.isEmpty {
                                        Text(item.subtitle)
                                            .font(.footnote)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                            .disabled(isResolving)
                        }
                    }
                }

                if let errorMessage {
                    Section { Text(errorMessage).foregroundStyle(.red).font(.footnote) }
                }
            }
            .overlay {
                if isResolving { ProgressView() }
            }
            .searchable(text: $search.query,
                        placement: .navigationBarDrawer(displayMode: .always),
                        prompt: Text(String(localized: "location_search_prompt")))
            .navigationTitle(String(localized: "location_title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "cancel")) { dismiss() }
                }
            }
        }
    }

    // MARK: - Actions

    private func resolve(_ completion: MKLocalSearchCompletion) {
        isResolving = true
        errorMessage = nil
        Task {
            defer { isResolving = false }
            do {
                let response = try await MKLocalSearch(request: MKLocalSearch.Request(completion: completion)).start()
                guard let item = response.mapItems.first else { throw CLError(.geocodeFoundNoResult) }
                let coord = item.placemark.coordinate
                finish(EventLocation(
                    name: item.name ?? completion.title,
                    address: completion.subtitle.isEmpty ? Self.address(of: item.placemark) : completion.subtitle,
                    latitude: coord.latitude,
                    longitude: coord.longitude
                ))
            } catch {
                errorMessage = String(localized: "location_not_found")
            }
        }
    }

    private func useCurrentLocation() {
        isResolving = true
        errorMessage = nil
        locationManager.requestOnce { loc in
            guard let loc else {
                isResolving = false
                errorMessage = String(localized: "location_permission_denied")
                return
            }
            Task {
                defer { isResolving = false }
                let placemark = try? await CLGeocoder().reverseGeocodeLocation(loc).first
                finish(EventLocation(
                    name: placemark?.name ?? String(localized: "location_current_name"),
                    address: placemark.map(Self.address(of:)),
                    latitude: loc.coordinate.latitude,
                    longitude: loc.coordinate.longitude
                ))
            }
        }
    }

    private func finish(_ location: EventLocation) {
        onPick(location)
        dismiss()
    }

    private static func address(of placemark: CLPlacemark) -> String {
        [placemark.thoroughfare, placemark.subLocality, placemark.locality, placemark.administrativeArea]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
    }
}

// MARK: - Autocomplete

@MainActor
final class PlaceSearchModel: NSObject, ObservableObject, MKLocalSearchCompleterDelegate {

    @Published var query = "" {
        didSet { completer.queryFragment = query }
    }
    @Published private(set) var results: [MKLocalSearchCompletion] = []

    private let completer = MKLocalSearchCompleter()

    override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = [.pointOfInterest, .address]
    }

    nonisolated func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        let found = completer.results
        Task { @MainActor in self.results = found }
    }

    nonisolated func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        Task { @MainActor in self.results = [] }
    }
}

// MARK: - Directions

enum DirectionsLauncher {

    /// Opens turn-by-turn directions in Apple Maps.
    static func openAppleMaps(to location: EventLocation) {
        let item = MKMapItem(placemark: MKPlacemark(coordinate: location.coordinate))
        item.name = location.name
        item.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDefault])
    }

    /// Google Maps universal link — opens the app when installed, the web otherwise.
    static func googleMapsURL(to location: EventLocation) -> URL? {
        URL(string: "https://www.google.com/maps/dir/?api=1&destination=\(location.latitude),\(location.longitude)")
    }
}
