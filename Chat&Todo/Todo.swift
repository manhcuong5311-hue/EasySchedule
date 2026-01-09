//
//  Todo.swift
//  Easy Schedule
//
//  Created by Sam Manh Cuong on 2/1/26.
//

import SwiftUI
import Combine
import Foundation
import FirebaseFirestore
import FirebaseAuth
import CoreLocation
import MapKit


struct TodoItem: Identifiable, Codable {
    @DocumentID var id: String?
    var text: String
    var doneBy: [String: Bool]
    var createdAt: Date
    var createdBy: String   // ⭐️ THÊM

    init(
        id: String? = nil,
        text: String,
        doneBy: [String: Bool] = [:],
        createdAt: Date = Date(),
        createdBy: String
    ) {
        self.id = id
        self.text = text
        self.doneBy = doneBy
        self.createdAt = createdAt
        self.createdBy = createdBy
    }
}



class TodoViewModel: ObservableObject {
    @Published var todos: [TodoItem] = []

    private let db = Firestore.firestore()
    private var listener: ListenerRegistration?

    let chatId: String
    let myId: String

    init(chatId: String, myId: String) {
        self.chatId = chatId
        self.myId = myId
    }

    deinit {
        listener?.remove()
    }
    var unfinishedCount: Int {
        todos.filter { !($0.doneBy[myId] ?? false) }.count
    }

    func listen() {
        listener?.remove()
        listener = db.collection("chats")
            .document(chatId)
            .collection("todos")
            .order(by: "createdAt")
            .addSnapshotListener { snap, err in
                guard let snap = snap else { return }
                let items = snap.documents.compactMap { try? $0.data(as: TodoItem.self) }

                DispatchQueue.main.async {
                    self.todos = items
                }
            }
    }


    func toggle(_ todo: TodoItem) {
        guard let id = todo.id else { return }

        let newValue = !(todo.doneBy[myId] ?? false)

        db.collection("chats")
            .document(chatId)
            .collection("todos")
            .document(id)
            .updateData([
                "doneBy.\(myId)": newValue
            ])
    }

    func stop() {
        listener?.remove()
        listener = nil
    }

    func addTodo(text: String) {
        let data: [String: Any] = [
            "text": text,
            "doneBy": [:],
            "createdAt": Timestamp(date: Date()),
            "createdBy": myId   // ⭐️ THÊM
        ]

        db.collection("chats")
            .document(chatId)
            .collection("todos")
            .addDocument(data: data)
    }

    func delete(_ todo: TodoItem) {
        guard let id = todo.id else { return }

        db.collection("chats")
            .document(chatId)
            .collection("todos")
            .document(id)
            .delete { err in
                if let err = err {
                    print("❌ DELETE FAILED:", err)
                } else {
                    print("🗑️ TODO DELETED")
                }
            }
    }

}

struct TodoListView: View {
    let chatId: String
    let myId: String
    @State private var showPaywall = false
    @StateObject private var vm: TodoViewModel
    @ObservedObject private var nameCache = SessionStore.UserNameCache.shared
    
    @ObservedObject private var network = NetworkMonitor.shared


    @State private var isSending = false

    @EnvironmentObject var premium: PremiumStoreViewModel
    @State private var newTodo = ""
    @State private var showDeleteConfirm = false
    @State private var todoToDelete: TodoItem? = nil
    enum TodoLimitAlertType: Identifiable {
        case freeLimit        // Free user vượt 5
        case chatMaxReached   // Chat premium vượt 20
        case emptyTodo
        var id: Int { hashValue }
    }

    @State private var limitAlert: TodoLimitAlertType? = nil



    init(chatId: String, myId: String) {
        self.chatId = chatId
        self.myId = myId
        _vm = StateObject(wrappedValue: TodoViewModel(chatId: chatId, myId: myId))
    }

    var body: some View {
        NavigationView {
            VStack {
                
                // ===== OFFLINE BANNER =====
                if !network.isOnline {
                       OfflineBannerView()
                           .listRowInsets(EdgeInsets())
                           .listRowBackground(Color.clear)
                   }


                  List {
                      ForEach(vm.todos) { item in
                          todoRow(item)
                      }
                      .onDelete { indexSet in
                          if let index = indexSet.first {
                              todoToDelete = vm.todos[index]
                              showDeleteConfirm = true
                          }
                      }
                  }

                HStack(spacing: 8) {

                    // INPUT TODO
                    TextField(
                        String(localized: "add_task_placeholder"),
                        text: $newTodo,
                        axis: .vertical
                    )
                    .lineLimit(1...3)
                    .font(.system(size: 16))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 20)
                            .fill(Color(.systemGray6))
                    )

                    // NÚT ADD
                    Button {
                        guard !isSending else { return }

                        let text = newTodo.trimmingCharacters(in: .whitespaces)

                        // ⭐ PHẢN HỒI KHI RỖNG
                        guard !text.isEmpty else {
                            limitAlert = .emptyTodo   // thêm case mới
                            return
                        }

                        let limits = PremiumLimits.limits(for: premium.tier)
                        let limit = limits.maxTodosPerEvent

                        if limit != .max && vm.todos.count >= limit {
                            switch premium.tier {
                            case .free:
                                limitAlert = .freeLimit
                            case .premium:
                                limitAlert = .chatMaxReached
                            case .pro:
                                break
                            }
                            return
                        }

                        isSending = true
                        vm.addTodo(text: text)
                        newTodo = ""

                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            isSending = false
                        }
                    } label: {
                        Image(systemName: isSending ? "hourglass" : "plus")
                            .foregroundColor(.white)
                            .frame(width: 40, height: 40)
                            .background(isSending ? Color.gray : Color.blue)
                            .clipShape(Circle())
                    }
                    .disabled(isSending)
                }
                .padding(.horizontal)
                .padding(.vertical, 10)

            }
            .navigationTitle(String(localized: "todo_list_title"))
            .navigationBarTitleDisplayMode(.inline)
            .onAppear { vm.listen()
            }
            .onDisappear { vm.stop()
            }
            .sheet(isPresented: $showPaywall) {
                PremiumUpgradeSheet()
                    .environmentObject(premium)
            }
            .alert(String(localized: "delete_confirm_title"), isPresented: $showDeleteConfirm) {
                Button(String(localized:"cancel"), role: .cancel) {}

                Button(String(localized:"delete"), role: .destructive) {
                    if let item = todoToDelete {
                        vm.delete(item)
                    }
                }
            }
            .alert(item: $limitAlert) { type in
                switch type {

                // ===== Free user vượt 5 =====
                case .freeLimit:
                    return Alert(
                        title: Text(String(localized: "todo_limit_title")),
                        message: Text(
                            String(
                                format: String(localized: "todo_free_limit_message"),
                                PremiumLimits
                                    .limits(for: .free)
                                    .maxTodosPerEvent
                            )

                        ),
                        primaryButton: .default(Text(String(localized: "upgrade_to_premium"))) {
                            showPaywall = true
                            limitAlert = nil
                        },
                        secondaryButton: .cancel {
                            limitAlert = nil
                        }
                    )

                // ===== Chat premium chạm 20 =====
                case .chatMaxReached:
                    return Alert(
                        title: Text(String(localized: "todo_limit_title")),
                        message: Text(String(localized: "todo_limit_reached_message")),
                        dismissButton: .default(Text(String(localized: "ok"))) {
                            limitAlert = nil
                        }
                    )
                case .emptyTodo:
                    return Alert(
                        title: Text(String(localized: "todo_empty_title")),
                        message: Text(String(localized: "todo_empty_message")),
                        dismissButton: .default(Text(String(localized: "ok"))) {
                            limitAlert = nil
                        }
                    )

                }
            }




        }
    }

    // MARK: - Row View
    private func todoRow(_ item: TodoItem) -> some View {
        HStack(alignment: .top, spacing: 12) {

            // Tick
            Button {
                vm.toggle(item)
            } label: {
                Image(systemName: (item.doneBy[myId] ?? false)
                       ? "checkmark.circle.fill"
                       : "circle")
                    .font(.system(size: 22))
                    .foregroundColor(.blue)
            }

            VStack(alignment: .leading, spacing: 6) {

                // ⭐⭐ HIỆN TEXT CỦA TODO (MẤT DÒNG NÀY NÊN UI TRỐNG)
                Text(item.text)
                    .font(.body)
                    .foregroundColor(.primary)
                    .lineLimit(nil)

                // Hiện người tick
                ForEach(Array(item.doneBy.keys).sorted(), id: \.self) { uid in
                    if item.doneBy[uid] == true {

                        let name = uid == myId
                        ? String(localized:"you")
                            : (nameCache.names[uid] ?? uid)

                        Text(
                            String(
                                format: String(localized: "todo_done_by"),
                                name
                            )
                        )

                            .font(.caption2)
                            .foregroundColor(uid == myId ? .blue : .green)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.gray.opacity(0.15))
                            .cornerRadius(6)
                            .onAppear {
                                if nameCache.names[uid] == nil {
                                    SessionStore.UserNameCache.shared.getName(for: uid) { _ in }
                                }
                            }

                    }
                }
            }

            Spacer()
        }
        .padding(.vertical, 6)
    }
}


