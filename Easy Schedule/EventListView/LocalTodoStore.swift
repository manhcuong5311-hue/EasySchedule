//
//  LocalTodoStore.swift
//  Easy Schedule
//
//  Created by Sam Manh Cuong on 22/1/26.
//
import SwiftUI
import Combine

struct LocalTodo: Identifiable, Codable {
    let id: UUID
    var title: String
    var isDone: Bool
    var isPinned: Bool        // ⭐ NEW
}


final class LocalTodoStore: ObservableObject {

    static let shared = LocalTodoStore()

    @Published private(set) var todosByEvent: [String: [LocalTodo]] = [:]

    private let key = "local_event_todos"

    private init() {
        load()
    }

    func todos(for eventId: String) -> [LocalTodo] {
        todosByEvent[eventId] ?? []
    }

    func addTodo(_ title: String, to eventId: String) {
        var list = todosByEvent[eventId] ?? []
        list.append(
            LocalTodo(
                id: UUID(),
                title: title,
                isDone: false,
                isPinned: false   // ⭐ thêm dòng này
            )
        )
        todosByEvent[eventId] = list
        save()
    }


    func toggle(todoId: UUID, eventId: String) {
        guard var list = todosByEvent[eventId],
              let idx = list.firstIndex(where: { $0.id == todoId })
        else { return }

        list[idx].isDone.toggle()
        todosByEvent[eventId] = list
        save()
    }

    private func save() {
        if let data = try? JSONEncoder().encode(todosByEvent) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    private func load() {
        guard
            let data = UserDefaults.standard.data(forKey: key),
            let decoded = try? JSONDecoder().decode([String: [LocalTodo]].self, from: data)
        else { return }

        todosByEvent = decoded
    }
    
    func delete(todoId: UUID, eventId: String) {
        guard var list = todosByEvent[eventId] else { return }
        list.removeAll { $0.id == todoId }
        todosByEvent[eventId] = list
        save()
    }


    func move(from source: IndexSet, to destination: Int, eventId: String) {
        todosByEvent[eventId]?.move(fromOffsets: source, toOffset: destination)
        save()
    }

    func togglePin(todoId: UUID, eventId: String) {
        guard var list = todosByEvent[eventId],
              let idx = list.firstIndex(where: { $0.id == todoId })
        else { return }

        list[idx].isPinned.toggle()

        // pin lên đầu
        list.sort {
            if $0.isPinned != $1.isPinned {
                return $0.isPinned
            }
            return false
        }

        todosByEvent[eventId] = list
        save()
    }

    func unfinishedCount(for eventId: String) -> Int {
        todosByEvent[eventId]?.filter { !$0.isDone }.count ?? 0
    }

    
}

struct LocalTodoListView: View {

    let eventId: String
    @ObservedObject private var store = LocalTodoStore.shared
    @State private var newTodo = ""

    var body: some View {
        VStack(spacing: 0) {

            // ===== TODO LIST =====
            VStack(spacing: 0) {
                ForEach(store.todos(for: eventId)) { todo in
                    HStack(spacing: 12) {

                        // CHECK
                        Button {
                            store.toggle(todoId: todo.id, eventId: eventId)
                        } label: {
                            Image(systemName: todo.isDone
                                  ? "checkmark.circle.fill"
                                  : "circle")
                                .foregroundStyle(
                                    todo.isDone ? .green : .secondary
                                )
                                .font(.system(size: 18))
                        }
                        .buttonStyle(.plain)

                        // TITLE
                        Text(todo.title)
                            .font(.system(size: 15))
                            .foregroundStyle(
                                todo.isDone ? .secondary : .primary
                            )
                            .strikethrough(todo.isDone)

                        Spacer()

                        // PIN
                        Button {
                            store.togglePin(todoId: todo.id, eventId: eventId)
                        } label: {
                            Image(systemName: todo.isPinned ? "pin.fill" : "pin")
                                .foregroundStyle(
                                    todo.isPinned
                                        ? Color.orange
                                        : Color(.tertiaryLabel)
                                )
                                .font(.system(size: 14))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.vertical, 10)
                    .contentShape(Rectangle())
                    .contextMenu {

                        // DONE / UNDONE
                        Button {
                            store.toggle(todoId: todo.id, eventId: eventId)
                        } label: {
                            Label(
                                String(localized: todo.isDone
                                    ? "todo_mark_undone"
                                    : "todo_mark_done"),
                                systemImage: todo.isDone ? "arrow.uturn.left" : "checkmark"
                            )

                        }

                        // PIN / UNPIN
                        Button {
                            store.togglePin(todoId: todo.id, eventId: eventId)
                        } label: {
                            Label(
                                String(localized: todo.isPinned
                                    ? "todo_unpin"
                                    : "todo_pin"),
                                systemImage: todo.isPinned ? "pin.slash" : "pin"
                            )

                        }

                        Divider()

                        // DELETE
                        Button(role: .destructive) {
                            store.delete(todoId: todo.id, eventId: eventId)
                        } label: {
                            Label(
                                String(localized: "todo_delete"),
                                systemImage: "trash"
                            )

                        }
                    }

                    // separator (trừ item cuối)
                    if todo.id != store.todos(for: eventId).last?.id {
                        Divider()
                            .padding(.leading, 30)
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)

            // ===== INPUT =====
            Divider()

            HStack(spacing: 10) {

                Image(systemName: "plus.circle.fill")
                    .foregroundStyle(.secondary)
                    .font(.system(size: 18))

                TextField(
                    String(localized: "todo_add_placeholder"),
                    text: $newTodo
                )
                    .font(.system(size: 15))
                    .textFieldStyle(.plain)

                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
            
            .onSubmit {
                addTodo()
            }
            .onTapGesture {
                // giữ feel native
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
    }

    private func addTodo() {
        let text = newTodo.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        store.addTodo(text, to: eventId)
        newTodo = ""
    }
}

extension LocalTodoStore {

    func hasUnfinishedTodo(for eventId: String) -> Bool {
        unfinishedCount(for: eventId) > 0
    }
}
