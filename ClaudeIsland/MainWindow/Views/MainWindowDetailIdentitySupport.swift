//
//  MainWindowDetailIdentitySupport.swift
//  ClaudeIsland
//
//  Keeps chat detail identity stable across thread switches so SwiftUI
//  can update in place instead of rebuilding the whole chat subtree.
//

import Foundation

enum MainWindowDetailIdentitySupport {
    nonisolated static func identity(for selectedThreadId: String?) -> String {
        selectedThreadId == nil ? "welcome" : "chat"
    }
}
