//
//  networkMonitor.swift
//  Easy Schedule
//
//  Created by Sam Manh Cuong on 8/12/25.
//
import SwiftUI
import Combine
import Network

class NetworkMonitor: ObservableObject {
    static let shared = NetworkMonitor()

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "NetworkMonitor")

    @Published var isOnline: Bool = true

    private init() {
        monitor.pathUpdateHandler = { path in
            DispatchQueue.main.async {
                self.isOnline = (path.status == .satisfied)
            }
        }
        monitor.start(queue: queue)
    }
}
