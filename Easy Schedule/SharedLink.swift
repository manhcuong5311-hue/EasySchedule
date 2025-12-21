//
//  SharedLink.swift
//  Easy Schedule
//
//  Created by Sam Manh Cuong on 21/11/25.
//
import Foundation

enum LinkStatus: String, Codable {
    case pending
    case connected
}

struct SharedLink: Identifiable, Codable {
    var id: String
    var uid: String
    var url: String
    var createdAt: Date

    var isPinned: Bool = false
    var displayName: String? = nil

    // ✅ THÊM
    var status: LinkStatus = .pending
    var allowedAt: Date? = nil
}


