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

    let location: CLLocation?
    var onPick: (CLLocationCoordinate2D) -> Void

    // iOS 17+ dùng MapCameraPosition
    @State private var position: MapCameraPosition

    init(
        location: CLLocation?,
        onPick: @escaping (CLLocationCoordinate2D) -> Void
    ) {
        self.location = location
        self.onPick = onPick

        let coord = location?.coordinate ??
            CLLocationCoordinate2D(latitude: 10.7626, longitude: 106.6601)

        let region = MKCoordinateRegion(
            center: coord,
            span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
        )

        _position = State(initialValue: .region(region))
    }

    var body: some View {
        ZStack {

            // 🗺️ MAP – API MỚI
            Map(position: $position) {
                UserAnnotation()
            }
            .ignoresSafeArea()

            // 📍 PIN GIỮA MÀN HÌNH
            Image(systemName: "mappin.circle.fill")
                .font(.system(size: 42))
                .foregroundColor(.red)
                .offset(y: -22)

            VStack {

                // ❌ NÚT ĐÓNG
                HStack {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 34))
                            .foregroundColor(.white)
                            .shadow(radius: 4)
                    }
                    .padding(.leading, 16)
                    .padding(.top, 30)

                    Spacer()
                }

                Spacer()

                // 📍 VỀ VỊ TRÍ CỦA TÔI
                if let loc = location {
                    Button {
                        withAnimation {
                            position = .region(
                                MKCoordinateRegion(
                                    center: loc.coordinate,
                                    span: MKCoordinateSpan(
                                        latitudeDelta: 0.01,
                                        longitudeDelta: 0.01
                                    )
                                )
                            )
                        }
                    } label: {
                        HStack {
                            Image(systemName: "location.fill")
                            Text(String(localized: "go_to_my_location"))
                        }
                        .padding(8)
                        .background(Color.white.opacity(0.9))
                        .cornerRadius(12)
                    }
                    .padding(.bottom, 8)
                }

                // ✅ CHỌN VỊ TRÍ
                Button(String(localized: "pick_location")) {
                    if let region = position.region {
                        onPick(region.center)
                    }
                    dismiss()
                }

                .padding()
                .background(Color.blue)
                .foregroundColor(.white)
                .cornerRadius(12)
                .padding(.bottom, 40)
            }
        }
        .interactiveDismissDisabled(false)
    }
}
