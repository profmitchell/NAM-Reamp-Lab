//
//  Extensions.swift
//  NAM Reamp Lab
//

import Foundation

// MARK: - Safe Array Access
extension Collection {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

// MARK: - Notification Names
extension Notification.Name {
    static let switchToTrainingTab = Notification.Name("switchToTrainingTab")
    static let audioRouteChanged = Notification.Name("audioRouteChanged")
}

extension FourCharCode {
    init(_ string: String) {
        var result: FourCharCode = 0
        for char in string.utf8.prefix(4) {
            result = (result << 8) + FourCharCode(char)
        }
        self = result
    }
}
