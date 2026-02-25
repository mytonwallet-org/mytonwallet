//
//  ExploreVM.swift
//  UIBrowser
//
//  Created by Sina on 6/25/24.
//

import Foundation
import OrderedCollections
import WalletContext
import WalletCore
@preconcurrency import WReachability

private let log = Log("ExploreVM")

@MainActor protocol ExploreVMDelegate: AnyObject {
    func didUpdateViewModelData()
}

@MainActor final class ExploreVM: WalletCoreData.EventsObserver {
    let reachability = try! Reachability()

    // MARK: - Initializer

    weak var delegate: ExploreVMDelegate?

    private(set) var exploreSites: OrderedDictionary<String, ApiSite> = [:]
    private(set) var exploreCategories: OrderedDictionary<Int, ApiSiteCategory> = [:]
    private(set) var connectedDapps: OrderedDictionary<String, ApiDapp> = [:]
    private(set) var featuredTitle: String?

    private var loadExploreSitesTask: Task<Void, Never>?
    private var waitingForNetwork = false

    init() {
        // Listen for network connection events
        reachability.whenReachable = { [weak self] _ in
            guard let self else { return }
            if waitingForNetwork {
                refresh()
                waitingForNetwork = false
            }
            // Improvement:
            // 1. cyclic retry only when screen visible
            // 2. stop when disappear
            // 3. make attempt when appear
            // 4. not use reachability for retry logic
            // 5. Decompose data loading from retries logic
            // 6. ? show loading error / retry button
        }
        reachability.whenUnreachable = { [weak self] _ in
            self?.waitingForNetwork = true
        }
        do {
            try reachability.startNotifier()
        } catch {
            // logError || make method non-throwable
        }

        WalletCoreData.add(eventObserver: self)
    }

    deinit {
        reachability.stopNotifier()
    }

    // MARK: - WalletCoreData.EventsObserver

    func walletCore(event: WalletCoreData.Event) {
        switch event {
        case .accountChanged: loadDapps()
        case .dappsCountUpdated: loadDapps()
        case .configChanged: updateRestricted()
        default: break
        }
    }

    // MARK: - Interface methods

    func refresh() {
        loadExploreSites()
        loadDapps()
        updateRestricted()
    }

    // MARK: - Update Data Model

    func updateExploreSites(_ result: ApiExploreSitesResult) {
        featuredTitle = result.featuredTitle
        exploreSites = OrderedDictionary(result.sites.map { ($0.url, $0) }, uniquingKeysWith: { $1 })
        exploreCategories = OrderedDictionary(result.categories.map { ($0.id, $0) }, uniquingKeysWith: { $1 })
        delegate?.didUpdateViewModelData()
    }

    func updateDapps(dapps: [ApiDapp]) {
        connectedDapps = OrderedDictionary(dapps.map { ($0.url, $0) }, uniquingKeysWith: { $1 })
        delegate?.didUpdateViewModelData()
    }
    
    func updateRestricted() {
        delegate?.didUpdateViewModelData()
    }

    // MARK: - Side Effects: Data Loading

    func loadExploreSites() {
        guard loadExploreSitesTask == nil || loadExploreSitesTask?.isCancelled == true else { return }

        loadExploreSitesTask = Task { [weak self] in
            do {
                let result = try await Api.loadExploreSites(langCode: LocalizationSupport.shared.langCode)
                self?.updateExploreSites(result)
            } catch {
                log.error("failed to fetch explore sites \(error, .public)")
                if let self, !waitingForNetwork { // Improvement: retry logic should not depend on reachability
                    try? await Task.sleep(for: .seconds(3))
                    if !Task.isCancelled {
                        if exploreSites.isEmpty {
                            refresh()
                        }
                    }
                }
            }
            if !Task.isCancelled {
                self?.loadExploreSitesTask = nil
            }
        }
    }

    private func loadDapps() {
        Task {
            do {
                if let accountId = AccountStore.accountId {
                    let dapps = try await Api.getDapps(accountId: accountId)
                    self.updateDapps(dapps: dapps)
                }
            } catch {
                try? await Task.sleep(for: .seconds(3))
                loadDapps()
            }
        }
    }
}
