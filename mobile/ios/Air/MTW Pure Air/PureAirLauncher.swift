//
//  ViewController.swift
//  MTW Pure Air
//
//  Created by nikstar on 18.05.2025.
//

import UIKit
import WalletCore
import WalletContext
import AirAsFramework
import UIComponents

private let log = Log("PureAirLauncher")


@MainActor func startTheApp() {
    Task(priority: .userInitiated) {
        do {
            try await GlobalStorage.loadFromWebView()
            try await GlobalStorage.migrate()
            UIApplication.shared.registerForRemoteNotifications()
            AirLauncher.soarIntoAir()
        } catch {
            AirLauncher.soarIntoAir()
        }
    }
}
