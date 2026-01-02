//
//  HistoryView.swift
//  Easy Schedule
//
//  Created by Sam Manh Cuong on 2/1/26.
//
import SwiftUI
import Foundation

struct HistoryView: View {
    @EnvironmentObject var eventManager: EventManager
    var onSelect: (String) -> Void = { _ in }

    @State private var showCopied = false

    var body: some View {
        NavigationStack {
            List {
                // ⭐ Sắp xếp: pinned trước, sau đó theo thời gian
                let sortedLinks = eventManager.sharedLinks.sorted {
                    if $0.isPinned == $1.isPinned { return $0.createdAt > $1.createdAt }
                    return $0.isPinned && !$1.isPinned
                }

                ForEach(sortedLinks) { link in
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(link.displayName ?? String(localized: "no_name"))
                                .font(.headline)

                            Text(link.url)
                                .font(.subheadline)


                            Text(
                                String(
                                    format: String(localized: "uid_prefix"),
                                    link.uid
                                )
                            )
                                .font(.caption)
                                .foregroundColor(.secondary)

                            Text(formatDate(link.createdAt))
                                .font(.caption2)
                                .foregroundColor(.gray)
                        }

                        Spacer()

                        // ⭐ Nút PIN
                        Button {
                            eventManager.togglePin(link)
                        } label: {
                            Image(systemName: link.isPinned ? "pin.fill" : "pin")
                                .foregroundColor(link.isPinned ? .orange : .gray)
                        }
                        .buttonStyle(.borderless)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        onSelect(link.url) // Load ngay
                    }
                    .onLongPressGesture {
                        UIPasteboard.general.string = link.url
                        showCopied = true
                    }
                }
                .onDelete { indexSet in
                    eventManager.sharedLinks.remove(atOffsets: indexSet)
                }
            }
            .navigationTitle(String(localized: "viewed_history"))
            .alert(String(localized: "link_copied"), isPresented: $showCopied) {
                Button(String(localized:"ok"), role: .cancel) {}
            }
        }
    }

    private func formatDate(_ date: Date) -> String {
        date.formatted(.dateTime.weekday(.wide).day().month(.wide))
    }

}

