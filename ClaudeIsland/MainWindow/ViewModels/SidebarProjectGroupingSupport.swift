//
//  SidebarProjectGroupingSupport.swift
//  ClaudeIsland
//
//  Shared grouping helpers for session-heavy sidebar data.
//

import Foundation

struct SidebarProjectRecord: Equatable, Sendable {
    let id: String
    let name: String
    let path: String
    let updatedAt: Date
}

protocol SidebarProjectGroupItem: Identifiable, Equatable where ID == String {
    var sidebarProjectId: String? { get }
    var sidebarUpdatedAt: Date { get }
}

struct SidebarProjectGroup<Item: SidebarProjectGroupItem>: Identifiable, Equatable {
    let id: String
    let name: String
    let path: String
    var updatedAt: Date
    var items: [Item]
}

enum SidebarProjectGroupingSupport {
    static func groups<Item: SidebarProjectGroupItem>(
        projects: [SidebarProjectRecord],
        items: [Item]
    ) -> [SidebarProjectGroup<Item>] {
        let itemsByProjectId = Dictionary(grouping: items) { $0.sidebarProjectId ?? "" }

        return projects.compactMap { project in
            guard let projectItems = itemsByProjectId[project.id], !projectItems.isEmpty else {
                return nil
            }

            return SidebarProjectGroup(
                id: project.id,
                name: project.name,
                path: project.path,
                updatedAt: project.updatedAt,
                items: projectItems.sorted { $0.sidebarUpdatedAt > $1.sidebarUpdatedAt }
            )
        }
        .sorted { lhs, rhs in
            if lhs.updatedAt != rhs.updatedAt {
                return lhs.updatedAt > rhs.updatedAt
            }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    static func replacingItem<Item: SidebarProjectGroupItem>(
        _ item: Item,
        in groups: [SidebarProjectGroup<Item>]
    ) -> [SidebarProjectGroup<Item>] {
        var updatedGroups = groups

        guard let groupIndex = updatedGroups.firstIndex(where: { $0.id == item.sidebarProjectId }),
              let itemIndex = updatedGroups[groupIndex].items.firstIndex(where: { $0.id == item.id }) else {
            return groups
        }

        updatedGroups[groupIndex].items[itemIndex] = item
        updatedGroups[groupIndex].items.sort { $0.sidebarUpdatedAt > $1.sidebarUpdatedAt }
        updatedGroups[groupIndex].updatedAt = max(updatedGroups[groupIndex].updatedAt, item.sidebarUpdatedAt)

        return updatedGroups.sorted { lhs, rhs in
            if lhs.updatedAt != rhs.updatedAt {
                return lhs.updatedAt > rhs.updatedAt
            }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }
}
