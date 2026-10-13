//
//  SharedLinksListView.swift
//  Easy Schedule
//
//  Created by Sam Manh Cuong on 23/2/26.
//
import SwiftUI

struct SharedLinksListView: View {

    @EnvironmentObject var eventManager: EventManager
    @Binding var searchText: String      // driven by the search field in the Partners header
    var onSelect: (String) -> Void

    @State private var pendingLink: SharedLink?
    @State private var showDeleteConfirm = false
    
    private var sortedLinks: [SharedLink] {
        eventManager.sharedLinks.sorted {
            $0.createdAt > $1.createdAt
        }
    }

    private var filteredLinks: [SharedLink] {
        if searchText.isEmpty { return sortedLinks }

        return sortedLinks.filter { link in
            let name = eventManager.displayName(for: link.uid).lowercased()
            let uid = link.uid.lowercased()
            let query = searchText.lowercased()
            return name.contains(query) || uid.contains(query)
        }
    }

    var body: some View {

        VStack(spacing: 12) {

            // 📋 Content (search field lives in the Partners header → SharedLinksListView)
            if filteredLinks.isEmpty {

                if searchText.isEmpty {
                    ContentUnavailableView(
                        String(localized: "no_history"),
                        systemImage: "person.2",
                        description: Text(String(localized: "no_history_desc"))
                    )
                } else {
                    ContentUnavailableView.search
                }

            } else {

                // All partners in ONE card, rows separated by inset dividers.
                VStack(spacing: 0) {
                    ForEach(Array(filteredLinks.enumerated()), id: \.element.id) { index, link in
                        if index > 0 {
                            Divider().padding(.leading, 52)
                        }
                        SharedLinkCard(
                            link: link,
                            displayName: eventManager.displayName(for: link.uid),
                            onTap: {
                                if link.status == .connected {
                                    onSelect(link.uid)
                                } else {
                                    pendingLink = link
                                }
                            }
                        )
                    }
                }
                .partnerCardSurface()
            }
        }
        .onAppear {
            eventManager.refreshSharedLinksStatus()
        }
        .alert(
            String(localized: "request_pending"),
            isPresented: Binding(
                get: { pendingLink != nil },
                set: { if !$0 { pendingLink = nil } }
            )
        ) {
            Button(String(localized: "ok"), role: .cancel) { }
        } message: {
            Text(String(localized: "waiting_for_accept"))
        }
        
    }
}

struct SharedLinkCard: View {

    @EnvironmentObject var eventManager: EventManager

    let link: SharedLink
    let displayName: String
    let onTap: () -> Void

    var body: some View {

        HStack(spacing: 12) {

            AvatarView(uid: link.uid, size: 40) {
                Circle()
                    .fill(color.opacity(0.15))
                    .frame(width: 40, height: 40)
                    .overlay(
                        Text(initial)
                            .font(.headline)
                            .foregroundColor(color)
                    )
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(displayName)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                statusLine
            }

            Spacer(minLength: 8)

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color(.tertiaryLabel))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .onTapGesture { onTap() }

        // ✅ HOLD MENU
        .contextMenu {
            Button {
                withAnimation {
                    if let myUid = eventManager.currentUserId {
                        eventManager.deleteSharedLinkFromFirestore(
                            myUid: myUid,
                            otherUid: link.uid
                        )
                    }
                    eventManager.sharedLinks.removeAll { $0.uid == link.uid }
                    eventManager.saveSharedLinks()
                }
            } label: {
                Label(
                    String(localized: "delete"),
                    systemImage: "trash"
                )
                .foregroundColor(.red)
            }
        }
    }

    private var color: Color {
        link.status == .connected ? .green : .orange
    }

    private var initial: String {
        displayName.prefix(1).uppercased()
    }

    /// Status line under the name: green dot + "Connected", or clock + "Pending".
    @ViewBuilder
    private var statusLine: some View {
        switch link.status {
        case .connected:
            HStack(spacing: 5) {
                Circle()
                    .fill(.green)
                    .frame(width: 7, height: 7)
                Text(String(localized: "connected"))
                    .foregroundStyle(.secondary)
            }
            .font(.caption)

        case .pending:
            HStack(spacing: 4) {
                Image(systemName: "clock.fill")
                Text(String(localized: "pending"))
            }
            .font(.caption)
            .foregroundColor(.orange)
        }
    }
}
