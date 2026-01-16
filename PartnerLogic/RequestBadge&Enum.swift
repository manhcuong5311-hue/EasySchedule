//
//  RequestBadge.swift
//  Easy Schedule
//
//  Created by Sam Manh Cuong on 16/1/26.
//
import SwiftUI
import Combine

final class AccessBadgeViewModel: ObservableObject {
    @Published var pendingCount: Int = 0

    private let service = AccessService.shared

    func load(ownerUid: String) {
        guard !ownerUid.isEmpty else { return }

        service.fetchRequestList(ownerUid: ownerUid) { reqs in
            DispatchQueue.main.async {
                self.pendingCount = reqs.count
            }
        }
    }
}

struct AccessRequestBadge: View {
    let count: Int

    var body: some View {
        if count > 0 {
            Text("\(count)")
                .font(.caption2)
                .foregroundColor(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.red)
                .clipShape(Capsule())
        }
    }
}

enum ActiveSheet: Identifiable {
    case history
    case createdEvents
    case manageAccess
    case addAppointment

    var id: Int { hashValue }
}
