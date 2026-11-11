import Foundation
import Testing
import UIUniversalSearch
import UniversalSearchCore
import UniversalSearchWalletCore
@testable import UniversalSearchFeature

@Suite("Universal Search browse preferences", .serialized)
@MainActor
struct UniversalSearchBrowsePreferenceTests {
    @Test(arguments: [("chats", true), ("tokens", true), ("apps", true), ("chats", false)])
    func rememberSelectionAcrossSessions(sectionID: String, hasRecentChats: Bool) async throws {
        let suiteName = "UniversalSearchBrowsePreferenceTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let coordinator = UniversalSearchCoordinator(sources: [])
        let context = WalletCoreUniversalSearchFactory.currentContext()
        try await coordinator.refresh(context: context)
        await coordinator.replace(UniversalSearchSourceSnapshot(
            sourceID: SearchSourceID("test:browse"),
            authority: 100,
            generatedAt: Date(),
            documents: makeDocuments().filter { hasRecentChats || $0.kind != .agentChat }
        ))

        let selections: [UniversalSearchSection.HeaderAccessory.ToggleSelection] = hasRecentChats
            ? [.primary, .secondary, .primary]
            : [.secondary, .primary, .secondary]
        for expectedSelection in selections {
            let screen = UniversalSearchScreenViewController()
            screen.loadViewIfNeeded()
            let results = try #require(screen.children.first as? UniversalSearchViewController)
            let session = UniversalSearchFeatureSession(
                screen: screen,
                coordinator: coordinator,
                presenter: makePresenter(),
                querySources: [],
                userDefaults: try #require(UserDefaults(suiteName: suiteName))
            )
            session.start()
            defer { session.stop() }
            try await waitForSections(in: results)
            let section = try #require(results.sections.first { $0.id == sectionID })
            #expect(getSelection(section) == expectedSelection)
            let expectedItemID = expectedSelection == .secondary
                ? "\(sectionID):trending"
                : (!hasRecentChats ? "agent-chat:start" : "\(sectionID):recent")
            #expect(section.items.map(\.id) == [expectedItemID])
            for otherSection in results.sections where otherSection.id != sectionID {
                #expect(getSelection(otherSection) == .primary)
            }

            let service = UniversalSearchIndexService(coordinator: coordinator)
            session.universalSearchIndexService(service, didUpdate: .init(
                context: UniversalSearchContext(
                    scopeID: "another-account",
                    network: context.network,
                    localeIdentifier: context.localeIdentifier
                ),
                kind: .contextChanged
            ))
            session.updateQuery("")
            try await waitForSections(in: results)
            #expect(getSelection(try #require(results.sections.first { $0.id == sectionID })) == expectedSelection)

            screen.onHeaderAccessoryTap?(section)
            session.stop()
        }
    }

    private func waitForSections(in results: UniversalSearchViewController) async throws {
        for _ in 0..<100 {
            if results.sections.count == 3 { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        Issue.record("Browse sections did not load")
    }

    private func getSelection(_ section: UniversalSearchSection) -> UniversalSearchSection.HeaderAccessory.ToggleSelection? {
        guard case .toggle(_, _, let selected) = section.headerAccessory else { return nil }
        return selected
    }

    private func makeDocuments() -> [SearchDocument] {
        let kinds: [(String, SearchEntityKind, SearchEntityKind)] = [
            ("chats", .agentChat, .agentAction),
            ("tokens", .token, .token),
            ("apps", .application, .application),
        ]
        return kinds.flatMap { sectionID, recentKind, trendingKind in
            [
                SearchDocument(
                    id: SearchEntityID("\(sectionID):recent"),
                    kind: recentKind,
                    fields: [.init("Recent", kind: .title)],
                    signals: SearchSignals(interaction: .init(lastSelectedAt: Date(), selectionCount: 1))
                ),
                SearchDocument(
                    id: SearchEntityID("\(sectionID):trending"),
                    kind: trendingKind,
                    fields: [.init("Trending", kind: .title)],
                    signals: SearchSignals(traits: [.trending])
                ),
            ]
        }
    }

    private func makePresenter() -> UniversalSearchResultsPresenter {
        UniversalSearchResultsPresenter { document, _ in
            UniversalSearchResolvedResult(
                item: UniversalSearchItem(
                    id: document.id.rawValue,
                    content: .chat(UniversalSearchChatResult(title: document.id.rawValue, subtitle: ""))
                ),
                route: .agent(query: nil)
            )
        }
    }
}
