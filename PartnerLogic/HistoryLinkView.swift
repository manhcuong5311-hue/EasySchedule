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

    @State private var showCopied = false
    @State private var showConfirmClear = false
    @State private var searchText: String = ""

    var sortedLinks: [SharedLink] {
        eventManager.sharedLinks.sorted(by: { $0.createdAt > $1.createdAt })
    }

    var filteredLinks: [SharedLink] {
        if searchText.isEmpty {
            return sortedLinks
        } else {
            return sortedLinks.filter { link in
                (link.displayName ?? "")
                    .lowercased()
                    .contains(searchText.lowercased())
            }
        }
    }

    var body: some View {
        List {
            ForEach(filteredLinks) { link in
                VStack(alignment: .leading) {
                    Text(link.displayName ?? "")
                        .font(.headline)

                    Text("\(String(localized: "uid_label")): \(link.uid)")
                        .font(.caption)


                    HStack(spacing: 8) {

                        Text(formatDate(link.createdAt))
                            .font(.caption2)
                            .foregroundColor(.secondary)

                        switch link.status {
                        case .connected:
                            Text(String(localized: "connected"))
                                .font(.caption2)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.green.opacity(0.15))
                                .foregroundColor(.green)
                                .clipShape(Capsule())

                        case .pending:
                            Text(String(localized: "pending"))
                                .font(.caption2)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.orange.opacity(0.15))
                                .foregroundColor(.orange)
                                .clipShape(Capsule())
                        }
                    }

                }
                .onTapGesture { onSelect(link.uid) }
                .onLongPressGesture {
                    UIPasteboard.general.string = link.url
                    showCopied = true
                }
            }
            .onDelete(perform: deleteAt)
        }
        .navigationTitle(String(localized: "viewed_history"))
        .searchable(text: $searchText,
                    placement: .navigationBarDrawer(displayMode: .automatic),
                    prompt: String(localized: "search_name"))
        .alert(String(localized:"link_copied"), isPresented: $showCopied) {
            Button(String(localized:"ok")) {}
        }
        .onAppear {
            eventManager.refreshSharedLinksStatus()
        }

    }

    private func deleteAt(at offsets: IndexSet) {
        let sorted = sortedLinks
        for index in offsets {
            let item = sorted[index]
            if let originalIndex = eventManager.sharedLinks.firstIndex(where: { $0.id == item.id }) {
                eventManager.sharedLinks.remove(at: originalIndex)
            }
        }
        eventManager.saveSharedLinks()
    }

    private func formatDate(_ date: Date) -> String {
        date.formatted(.dateTime.weekday(.wide).day().month(.wide))
    }
}
