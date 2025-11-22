//
//  SharedLink.swift
//  Easy Schedule
//
//  Created by Sam Manh Cuong on 21/11/25.
//
import Foundation

struct SharedLink: Identifiable, Codable, Hashable {
    var id: String = UUID().uuidString
    let uid: String               // UID đối tác / người nhận
    let url: String               // Link chia sẻ
    let createdAt: Date           // Ngày tạo link
    var isPinned: Bool = false
}

