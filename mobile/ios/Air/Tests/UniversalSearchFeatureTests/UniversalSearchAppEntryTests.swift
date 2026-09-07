import Testing
import Foundation
import UIUniversalSearch
import UniversalSearchCore
import WalletCore
@testable import UniversalSearchFeature

@Suite("Universal Search app entries")
struct UniversalSearchAppEntryTests {
    @MainActor @Test
    func `actions and settings have separate sections and keep native routes`() throws {
        let entries = UniversalSearchAppEntries.all.filter {
            ["action:fund", "action:send", "setting:appearance"].contains($0.id)
        }
        let documents = entries.map {
            SearchDocument(id: SearchEntityID($0.id), kind: $0.kind, fields: [.init("Wallet", kind: .title)])
        }
        let hits = documents.map(makeSearchHit)
        let presenter = UniversalSearchResultsPresenter(resolver: { document, _ in
            guard let entry = entries.first(where: { $0.id == document.id.rawValue }) else { return nil }
            return UniversalSearchResolvedResult(
                item: UniversalSearchItem(
                    id: entry.id,
                    content: .shortcut(UniversalSearchShortcutResult(
                        icon: UniversalSearchIcon(.init(systemName: "gearshape")),
                        title: entry.titleKey, subtitle: entry.subtitleKey
                    ))
                ),
                route: entry.route
            )
        })
        let presentation = presenter.presentation(
            for: UniversalSearchResultSnapshot(
                query: UniversalSearchQuery("wallet"), hits: hits, totalHitCount: hits.count,
                corpusRevision: 1, rankingPolicyVersion: "test", generatedAt: Date()
            ),
            context: UniversalSearchContext(scopeID: "test", network: "mainnet", localeIdentifier: "en")
        )
        #expect(presentation.sections.map(\.id) == ["top-hit", "actions", "settings", "ask-agent", "search-google"])
        #expect(presentation.preselectedItemID == "action:fund")
        #expect(presentation.sections.first { $0.id == "actions" }?.rowHeight == 52)
        #expect(presentation.sections.first { $0.id == "settings" }?.rowHeight == 56)
        #expect(presentation.sections.flatMap(\.items).filter { $0.id == "action:fund" }.count == 1)
        guard case .settings(.appearance) = presentation.routesByItemID["setting:appearance"] else {
            Issue.record("The Settings result lost its native route")
            return
        }
    }

    @Test
    func `localized titles and Android aliases open the same destination`() throws {
        let documents = UniversalSearchAppEntries.documents(
            availability: .init(actions: [.fund, .send]),
            localize: { ["Send": "Отправить", "Receive": "Получить", "Appearance": "Оформление"][$0] ?? $0 }
        )
        let engine = UniversalSearchEngine()
        for (query, expectedID) in [
            ("send", "action:send"), ("transfer", "action:send"), ("отправ", "action:send"),
            ("receive", "action:fund"), ("получ", "action:fund"), ("deposit", "action:fund"),
            ("appearance", "setting:appearance"), ("оформ", "setting:appearance"),
            ("theme", "setting:appearance"),
        ] {
            #expect(engine.search(query, in: documents).first?.id.rawValue == expectedID)
        }
        let entry = try #require(UniversalSearchAppEntries.all.first { $0.id == "action:send" })
        guard case .walletAction(.send) = entry.route else {
            Issue.record("Send must route to the native Send flow")
            return
        }
        let appearance = try #require(UniversalSearchAppEntries.all.first { $0.id == "setting:appearance" })
        guard case .settings(.appearance) = appearance.route else {
            Issue.record("Appearance must route to its Settings section")
            return
        }
    }

    @Test
    func `unavailable wallet actions and conditional settings are removed`() {
        let limited = UniversalSearchAppEntries.available(in: .init(actions: [.fund, .scan]))
        let ids = Set(limited.map(\.id))
        #expect(ids.contains("action:fund"))
        #expect(ids.contains("setting:appearance"))
        #expect(ids.isDisjoint(with: [
            "action:send", "action:swap", "action:earn", "action:buy-with-card", "action:sell",
            "setting:dapps", "setting:wallet-versions", "setting:security", "setting:subwallets",
        ]))
        let enabled = UniversalSearchAppEntries.available(in: .init(
            actions: Set(UniversalSearchWalletAction.allCases), hasConnectedApps: true,
            hasWalletVersions: true, hasSecurity: true, hasSubwallets: true
        ))
        #expect(enabled.count == UniversalSearchAppEntries.all.count)
        #expect(Set(enabled.map(\.id)).count == enabled.count)
    }
}
