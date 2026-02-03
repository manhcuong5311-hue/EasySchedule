//
//  Untitled.swift
//  Easy Schedule
//
//  Created by Sam Manh Cuong on 2/1/26.
//
import SwiftUI

struct HistoryLinksView: View {
    @EnvironmentObject var eventManager: EventManager
    var onSelect: (String) -> Void

   
    @State private var showConfirmClear = false
    @State private var searchText: String = ""
    @State private var copiedMessage: String?
    @State private var nameCache: [String: String] = [:]

    
    var sortedLinks: [SharedLink] {
        eventManager.sharedLinks.sorted(by: { $0.createdAt > $1.createdAt })
    }

    var filteredLinks: [SharedLink] {
        if searchText.isEmpty {
            return sortedLinks
        } else {
            return sortedLinks.filter { link in
                let name = eventManager.displayName(for: link.uid).lowercased()
                let uid = link.uid.lowercased()
                let query = searchText.lowercased()

                return name.contains(query) || uid.contains(query)
            }

        }
    }

    var body: some View {
        
        Group {
               if filteredLinks.isEmpty {
                   emptyStateView
               } else {
                   listView
               }
           }
      
        
        .listStyle(.insetGrouped)
        .alert(String(localized: "clear_history"),
               isPresented: $showConfirmClear) {

            Button(String(localized: "clear"), role: .destructive) {
                eventManager.sharedLinks.removeAll()
                eventManager.saveSharedLinks()
            }

            Button(String(localized: "cancel"), role: .cancel) {}

        } message: {
            Text(String(localized: "clear_history_confirm"))
        }


        .navigationTitle(String(localized: "viewed_history"))
        .searchable(text: $searchText,
                    placement: .navigationBarDrawer(displayMode: .automatic),
                    prompt: String(localized: "search_name"))
        .alert(copiedMessage ?? "", isPresented: .constant(copiedMessage != nil)) {
            Button(String(localized: "ok")) {
                copiedMessage = nil
            }
        }
        .onChange(of: copiedMessage) { _, newValue in
            guard newValue != nil else { return }

            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                copiedMessage = nil
            }
        }

        .onChange(
            of: eventManager.sharedLinks.map { $0.uid }
        ) { _, uids in
            for uid in uids {
                if nameCache[uid] == nil {
                    nameCache[uid] = eventManager.displayName(for: uid)
                }
            }
        }



        .onAppear {
            if eventManager.sharedLinks.contains(where: { $0.status == .pending }) {
                eventManager.refreshSharedLinksStatus()
            }
        }


    }

    private var emptyStateView: some View {
        ContentUnavailableView(
            String(localized: "no_history"),
            systemImage: "clock.arrow.circlepath",
            description: Text(String(localized: "no_history_desc"))
        )
    }

    private var listView: some View {
        List {
            ForEach(filteredLinks) { link in
                HistoryLinkRow(
                    link: link,
                    displayName: nameCache[link.uid]
                        ?? eventManager.displayName(for: link.uid)
,
                    onSelect: {
                        onSelect(link.uid)
                    },
                    onCopyLink: {
                        UIPasteboard.general.string = link.url
                        copiedMessage = String(localized: "link_copied")
                    
                    },
                    onCopyUID: {
                        UIPasteboard.general.string = link.uid
                        copiedMessage = String(localized: "uid_copied")
                    }
                )
            }
            .onDelete(perform: deleteAt)
        }
        .navigationTitle(String(localized: "viewed_history"))
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                EditButton()
            }

            ToolbarItem(placement: .navigationBarLeading) {
                Button(role: .destructive) {
                    showConfirmClear = true
                } label: {
                    Image(systemName: "trash")
                }
            }
        }

    }
    
    
    
    private func deleteAt(at offsets: IndexSet) {
        let ids = offsets.map { sortedLinks[$0].id }
        eventManager.sharedLinks.removeAll { ids.contains($0.id) }
        eventManager.saveSharedLinks()
    }


    private func formatDate(_ date: Date) -> String {
        date.formatted(.dateTime.weekday(.wide).day().month(.wide))
    }
}

struct HistoryLinkRow: View {
    let link: SharedLink
    let displayName: String
    let onSelect: () -> Void
    let onCopyLink: () -> Void
    let onCopyUID: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {

            // ===== Top: Name + Status =====
            HStack {
                Text(displayName.isEmpty
                     ? String(localized: "unknown_user")
                     : displayName)
                    .font(.headline)
                    .lineLimit(1)

                Spacer()

                statusView
            }

            // ===== UID =====
            Text("UID: \(link.uid)")
                .font(.caption)
                .foregroundColor(.secondary)
                .textSelection(.enabled)

            // ===== Meta =====
            HStack(spacing: 8) {
                Text(link.createdAt.formatted(.dateTime.day().month().year()))
                    .font(.caption2)
                    .foregroundColor(.secondary)

                Spacer()
            }
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .onTapGesture { onSelect() }
        .contextMenu {
            Button {
                onCopyUID()
            } label: {
                Label(String(localized: "copy_uid"), systemImage: "doc.on.doc")
            }
        }

        .background(
            link.status == .pending
            ? Color.orange.opacity(0.06)
            : Color.clear
        )
        .animation(.easeInOut(duration: 0.2), value: link.status)

        
    }

    @ViewBuilder
    private var statusView: some View {
        switch link.status {
        case .connected:
            Label(String(localized: "connected"),
                  systemImage: "checkmark.circle.fill")
                .font(.caption2)
                .foregroundColor(.green)

        case .pending:
            Label(String(localized: "pending"),
                  systemImage: "clock.fill")
                .font(.caption2)
                .foregroundColor(.orange)
        }
    }
}
