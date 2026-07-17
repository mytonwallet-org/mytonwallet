//
//  SettingsSection.swift
//  UISettings
//
//  Created by Sina on 6/26/24.
//

import Foundation

struct SettingsSection: Identifiable {
    enum Section: String, CaseIterable, Equatable, Hashable {
        case header
        case accounts
        case tabsAndModules
        case general
        case questionAndAnswers
        case about
    }
    let id: Section
    var children: [SettingsItem]
}
