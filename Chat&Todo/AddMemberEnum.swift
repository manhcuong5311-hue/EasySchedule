//
//  AddMemberEnum.swift
//  Easy Schedule
//
//  Created by Sam Manh Cuong on 29/1/26.
//
import SwiftUI

enum AddMemberValidationResult {
    case ok

    case notLoggedIn
    case noPermission
    case userNotFound

    case eventEnded
    case offDay
    case busy

    case limitReached
}
