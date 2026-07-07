import UIKit
import UIHome
import UIAgent
import UIBrowser
import UIPortfolio
import UISettings
import UIComponents
import WalletCore
import WalletContext

@MainActor
struct AppTabRegistration {
    let id: AppTabId
    let titleProvider: () -> String
    let compactIcon: UIImage
    let sidebarIcon: UIImage
    let makeNavigationController: (RootContainerLayout) -> WNavigationController
    let sidebarEdgeCoverColor: UIColor?
}

@MainActor
final class AppTabManager {
    static let shared = AppTabManager()
    static let defaultTabIds: [AppTabId] = [.wallet, .agent, .explore, .settings]

    private var registrations: [AppTabId: AppTabRegistration] = [:]
    private var registrationOrder: [AppTabId] = []
    private(set) var orderedTabIds: [AppTabId] = defaultTabIds
    private var observers: [ObjectIdentifier: ([AppTabId]) -> Void] = [:]

    private init() {
        registerDefaults()
        applyStoredTabOrder()
    }

    func registration(for id: AppTabId) -> AppTabRegistration? {
        registrations[id]
    }

    func isRegistered(_ id: AppTabId) -> Bool {
        registrations[id] != nil
    }

    func makeNavigationController(for id: AppTabId, layout: RootContainerLayout) -> WNavigationController? {
        guard let reg = registrations[id] else { return nil }
        let nc = reg.makeNavigationController(layout)
        nc.tabBarItem.image = reg.compactIcon
        nc.tabBarItem.title = reg.titleProvider()
        return nc
    }

    func title(for id: AppTabId) -> String? {
        registrations[id]?.titleProvider()
    }

    func contains(_ id: AppTabId) -> Bool {
        orderedTabIds.contains(id)
    }

    func setTabIds(_ ids: [AppTabId]) {
        let requiredIds = registeredTabIds.filter(\.isRequired)
        let missingRequired = requiredIds.filter { !ids.contains($0) }
        guard missingRequired.isEmpty else {
            assertionFailure("Missing required tabs: \(missingRequired)")
            return
        }
        guard Set(ids).count == ids.count else {
            assertionFailure("Tab list contains duplicate identifiers")
            return
        }
        for id in ids where !isRegistered(id) {
            assertionFailure("Tab '\(id)' is not registered")
            return
        }
        orderedTabIds = ids
        notifyObservers()
    }

    func resetToDefault() {
        orderedTabIds = Self.defaultTabIds
        notifyObservers()
    }

    func addObserver(_ observer: AnyObject, handler: @escaping ([AppTabId]) -> Void) {
        observers[ObjectIdentifier(observer)] = handler
    }

    func removeObserver(_ observer: AnyObject) {
        observers.removeValue(forKey: ObjectIdentifier(observer))
    }

    private func notifyObservers() {
        AppStorageHelper.appTabOrder = orderedTabIds.map(\.rawValue)
        let ids = orderedTabIds
        for handler in observers.values {
            handler(ids)
        }
    }

    private func applyStoredTabOrder() {
        let saved = AppStorageHelper.appTabOrder
        guard !saved.isEmpty else { return }
        let validated = validatedTabOrder(from: saved)
        orderedTabIds = validated
    }

    private func validatedTabOrder(from rawValues: [String]) -> [AppTabId] {
        var seen = Set<AppTabId>()
        var result = rawValues
            .map(AppTabId.init(_:))
            .filter { isRegistered($0) && seen.insert($0).inserted }
        for req in Self.defaultTabIds where req.isRequired && !result.contains(req) {
            result.append(req)
        }
        return result
    }

    var registeredTabIds: [AppTabId] { registrationOrder }

    private func register(_ registration: AppTabRegistration) {
        if registrations[registration.id] == nil {
            registrationOrder.append(registration.id)
        }
        registrations[registration.id] = registration
    }

    private func registerDefaults() {
        register(AppTabRegistration(
            id: .wallet,
            titleProvider: { lang("Wallet") },
            compactIcon: UIImage(named: "tab_home", in: AirBundle, compatibleWith: nil) ?? UIImage(),
            sidebarIcon: UIImage.airBundle("SidebarWallet"),
            makeNavigationController: { layout in
                switch layout {
                case .tab:   WNavigationController(rootViewController: HomeVC())
                case .split: WNavigationController(rootViewController: SplitHomeVC())
                }
            },
            sidebarEdgeCoverColor: .air.groupedBackground
        ))
        register(AppTabRegistration(
            id: .agent,
            titleProvider: { lang("Agent") },
            compactIcon: UIImage(named: "tab_agent", in: AirBundle, compatibleWith: nil) ?? UIImage(),
            sidebarIcon: UIImage.airBundle("SidebarAgent"),
            makeNavigationController: { _ in
                AppTabLazyNavigationController { AgentEntryPoint.makeRootViewController() }
            },
            sidebarEdgeCoverColor: nil
        ))
        register(AppTabRegistration(
            id: .explore,
            titleProvider: { lang("Explore") },
            compactIcon: UIImage(named: "tab_explore", in: AirBundle, compatibleWith: nil) ?? UIImage(),
            sidebarIcon: UIImage.airBundle("SidebarExplore"),
            makeNavigationController: { _ in
                AppTabLazyNavigationController { ExploreTabVC() }
            },
            sidebarEdgeCoverColor: .air.background
        ))
        register(AppTabRegistration(
            id: .settings,
            titleProvider: { lang("Settings") },
            compactIcon: UIImage(named: "tab_settings", in: AirBundle, compatibleWith: nil) ?? UIImage(),
            sidebarIcon: UIImage.airBundle("SidebarSettings"),
            makeNavigationController: { _ in
                AppTabLazyNavigationController { SettingsVC() }
            },
            sidebarEdgeCoverColor: nil
        ))
        register(AppTabRegistration(
            id: .portfolio,
            titleProvider: { lang("Portfolio") },
            compactIcon: UIImage(systemName: "chart.line.uptrend.xyaxis") ?? UIImage(),
            sidebarIcon: UIImage(systemName: "chart.line.uptrend.xyaxis") ?? UIImage(),
            makeNavigationController: { _ in
                AppTabLazyNavigationController {
                    PortfolioVC(accountContext: AccountContext(source: .current))
                }
            },
            sidebarEdgeCoverColor: nil
        ))
    }
}
