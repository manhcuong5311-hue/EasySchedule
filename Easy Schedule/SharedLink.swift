//
//  SharedLink.swift
//  Easy Schedule
//
//  Created by Sam Manh Cuong on 21/11/25.
//
import Foundation

struct SharedLink: Identifiable, Codable {
    var id: String
    var uid: String
    var url: String          // 👉 chuyển sang var để update được
    var createdAt: Date      // 👉 chuyển sang var để update được
    var isPinned: Bool = false
    var displayName: String? = nil   // Nếu bạn có thêm trường tên
}


