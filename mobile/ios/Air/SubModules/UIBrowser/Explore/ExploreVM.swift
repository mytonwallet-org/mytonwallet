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
import WReachability

private let log = Log("ExploreVM")

@MainActor protocol ExploreVMDelegate: AnyObject {
    func didUpdateViewModelData()
}

@MainActor final class ExploreVM: WalletCoreData.EventsObserver {
    let reachability = Reachability()

    // MARK: - Initializer

    weak var delegate: ExploreVMDelegate?

    private(set) var exploreSites: OrderedDictionary<String, ApiSite> = [:]
    private(set) var exploreCategories: OrderedDictionary<Int, ApiSiteCategory> = [:]
    private(set) var connectedDapps: OrderedDictionary<String, ApiDapp> = [:]
    private(set) var featuredTitle: String?

    private var loadExploreSitesTask: Task<Void, Never>?
    private var loadDappsTask: Task<Void, Never>?
    private var retryTask: Task<Void, Never>?
    private var isActive = false
    private var didLoadSites = false
    private var needsDappsRefresh = true
    private var waitingForNetwork = false
    private let fetchSites: () async throws -> ApiExploreSitesResult
    private let fetchDapps: (String) async throws -> [ApiDapp]
    private let accountId: () -> String?
    private let retryDelay: Duration

    init(
        fetchSites: @escaping () async throws -> ApiExploreSitesResult = {
            try await Api.loadExploreSites(langCode: LocalizationSupport.shared.langCode)
        },
        fetchDapps: @escaping (String) async throws -> [ApiDapp] = { try await Api.getDapps(accountId: $0) },
        accountId: @escaping () -> String? = { AccountStore.accountId },
        retryDelay: Duration = .seconds(3)
    ) {
        self.fetchSites = fetchSites
        self.fetchDapps = fetchDapps
        self.accountId = accountId
        self.retryDelay = retryDelay
        // Listen for network connection events
        reachability.whenReachable = { [weak self] _ in
            guard let self else { return }
            waitingForNetwork = false
            if isActive { refreshMissingContent() }
        }
        reachability.whenUnreachable = { [weak self] _ in
            self?.waitingForNetwork = true
        }
        reachability.startNotifier()

        WalletCoreData.add(eventObserver: self)
    }

    isolated deinit {
        loadExploreSitesTask?.cancel()
        loadDappsTask?.cancel()
        retryTask?.cancel()
        reachability.stopNotifier()
    }

    // MARK: - WalletCoreData.EventsObserver

    func walletCore(event: WalletCoreData.Event) {
        switch event {
        case .accountChanged:
            invalidateDapps()
            updateDapps(dapps: [])
            if isActive { loadDapps() }
        case .dappsCountUpdated:
            invalidateDapps()
            if isActive { loadDapps() }
        case .configChanged: updateRestricted()
        case .lockdownModeChanged: delegate?.didUpdateViewModelData()
        default: break
        }
    }

    // MARK: - Interface methods

    /// Preparation may make one request; only an appearing screen owns retries.
    func setActive(_ active: Bool) {
        guard isActive != active else { return }
        isActive = active
        retryTask?.cancel()
        retryTask = nil
        if active { refreshMissingContent() }
    }

    func refresh() {
        loadExploreSites()
        loadDapps()
        updateRestricted()
    }

    // MARK: - Update Data Model

    func updateExploreSites(_ result: ApiExploreSitesResult) {
        didLoadSites = true
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

    private func loadExploreSites() {
        guard loadExploreSitesTask == nil else { return }

        loadExploreSitesTask = Task { [weak self, fetchSites] in
            do {
                let result = try await fetchSites()
                guard !Task.isCancelled else { return }
                self?.updateExploreSites(result)
            } catch {
                guard !Task.isCancelled else { return }
                log.error("failed to fetch explore sites \(error, .public)")
            }
            self?.loadExploreSitesTask = nil
            self?.scheduleRetry()
        }
    }

    private func loadDapps() {
        guard loadDappsTask == nil else { return }
        guard let accountId = accountId() else {
            needsDappsRefresh = false
            updateDapps(dapps: [])
            return
        }
        loadDappsTask = Task { [weak self, fetchDapps] in
            do {
                let dapps = try await fetchDapps(accountId)
                guard !Task.isCancelled else { return }
                self?.needsDappsRefresh = false
                self?.updateDapps(dapps: dapps)
            } catch {
                guard !Task.isCancelled else { return }
                self?.needsDappsRefresh = true
                log.error("failed to fetch connected dapps \(error, .public)")
            }
            self?.loadDappsTask = nil
            self?.scheduleRetry()
        }
    }

    private func invalidateDapps() {
        loadDappsTask?.cancel()
        loadDappsTask = nil
        needsDappsRefresh = true
    }

    private func refreshMissingContent() {
        if !didLoadSites { loadExploreSites() }
        if needsDappsRefresh { loadDapps() }
    }

    private func scheduleRetry() {
        guard isActive, !waitingForNetwork, retryTask == nil,
              !didLoadSites || needsDappsRefresh else { return }
        retryTask = Task { [weak self, retryDelay] in
            do { try await Task.sleep(for: retryDelay) } catch { return }
            guard let self, isActive else { return }
            retryTask = nil
            refreshMissingContent()
        }
    }
}
