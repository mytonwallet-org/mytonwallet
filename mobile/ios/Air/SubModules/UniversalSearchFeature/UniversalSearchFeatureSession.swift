import Foundation
import UIInAppBrowser
import UIUniversalSearch
import UniversalSearchCore
import UniversalSearchWalletCore
import WalletContext
import WalletCore

private let log = Log("UniversalSearch")

@MainActor
public final class UniversalSearchFeatureSession: @unchecked Sendable {
    private enum ResultsUpdateStyle: Equatable {
        case none
        case diffable

        var animatesDifferences: Bool { self == .diffable }
    }

    private enum QueryTrigger: String {
        case input
        case sourceUpdate = "source_update"
        case querySource = "query_source"

        var updateStyle: ResultsUpdateStyle {
            switch self {
            case .input, .sourceUpdate:
                .none
            case .querySource:
                .diffable
            }
        }

        var isSourceUpdate: Bool { self == .sourceUpdate }
    }

    private enum BrowseTrigger {
        case input
        case sourceUpdate
        case modeToggle
        case interaction

        var updateStyle: ResultsUpdateStyle {
            switch self {
            case .input, .sourceUpdate:
                .none
            case .modeToggle, .interaction:
                .diffable
            }
        }

        var isSourceUpdate: Bool {
            if case .sourceUpdate = self { true } else { false }
        }
    }

    public var onSelectRoute: ((UniversalSearchFeatureRoute) -> Void)?
    public var onAutocompleteChange: ((UniversalSearchAutocomplete?) -> Void)?

    private let screen: UniversalSearchScreenViewController
    private let coordinator: UniversalSearchCoordinator
    private let indexService: UniversalSearchIndexService?
    private let presenter: UniversalSearchResultsPresenter
    private let querySources: [any UniversalSearchQuerySource]
    private let interactionStore: WalletCoreSearchInteractionStore
    private let interactionSource: WalletCoreSearchInteractionSource

    private var routesByItemID: [String: UniversalSearchFeatureRoute] = [:]
    private var queryTask: Task<Void, Never>?
    private var renderTask: Task<Void, Never>?
    private var querySourceTasks: [Task<Void, Never>] = []
    private var querySourcesGeneration: UInt64?
    private var queryGeneration: UInt64 = 0
    private var renderGeneration: UInt64 = 0
    private var currentQuery = ""
    private var currentContext: UniversalSearchContext?
    private var browseSelectedModes: [String: UniversalSearchBrowseMode] = [:]
    private var lastAutocomplete: UniversalSearchAutocomplete?
    private var hasPresentedBrowseContent = false
    private var isStarted = false

    public init(
        screen: UniversalSearchScreenViewController,
        coordinator: UniversalSearchCoordinator? = nil,
        indexService: UniversalSearchIndexService? = nil,
        presenter: UniversalSearchResultsPresenter? = nil,
        entityRegistry: WalletCoreSearchEntityRegistry = .init(),
        querySources: [any UniversalSearchQuerySource]? = nil,
        interactionStore: WalletCoreSearchInteractionStore = .shared
    ) {
        let indexService = indexService ?? (coordinator == nil
            ? UniversalSearchFeatureFactory.sharedIndexService
            : nil)
        self.screen = screen
        self.coordinator = coordinator
            ?? indexService?.coordinator
            ?? UniversalSearchFeatureFactory.sharedCoordinator
        self.indexService = indexService
        self.presenter = presenter ?? UniversalSearchResultsPresenter(tokenResolver: { accountID, slug in
            TokenStore.getToken(slug: slug)
                ?? entityRegistry.token(accountID: accountID, slug: slug)
        })
        self.querySources = querySources ?? [
            WalletCoreWalletAddressQuerySource(),
            WalletCoreTokenAddressQuerySource(registry: entityRegistry),
        ]
        self.interactionStore = interactionStore
        self.interactionSource = WalletCoreSearchInteractionSource(store: interactionStore)

        screen.onSelect = { [weak self] item in
            guard let self, let route = routesByItemID[item.id] else { return }
            if shouldRecordSelection(of: item) {
                recordSelection(of: SearchEntityID(item.id))
            }
            onSelectRoute?(route)
        }
        screen.onHeaderAccessoryTap = { [weak self] section in
            self?.toggleBrowseMode(for: section)
        }
    }

    deinit {
        queryTask?.cancel()
        renderTask?.cancel()
        querySourceTasks.forEach { $0.cancel() }
    }

    public func start(initialQuery: String = "") {
        guard !isStarted else { return }
        isStarted = true
        indexService?.add(observer: self)
        currentContext = WalletCoreUniversalSearchFactory.currentContext()
        updateQuery(initialQuery)
    }

    public func stop() {
        guard isStarted else { return }
        isStarted = false
        indexService?.remove(observer: self)
        queryTask?.cancel()
        renderTask?.cancel()
        querySourceTasks.forEach { $0.cancel() }
        queryTask = nil
        renderTask = nil
        querySourceTasks = []
        querySourcesGeneration = nil
        routesByItemID = [:]
        let sourceIDs = querySources.map(\.sourceID)
        Task { [coordinator] in
            for sourceID in sourceIDs {
                await coordinator.remove(sourceID: sourceID)
            }
        }
    }

    public func updateQuery(_ text: String) {
        currentQuery = text
        queryGeneration &+= 1
        let generation = queryGeneration
        queryTask?.cancel()
        renderTask?.cancel()
        querySourceTasks.forEach { $0.cancel() }
        querySourceTasks = []
        querySourcesGeneration = nil
        routesByItemID = [:]

        let query = UniversalSearchQuery(text)

        let context = WalletCoreUniversalSearchFactory.currentContext()
        let inputStartedAt = CFAbsoluteTimeGetCurrent()
        queryTask = Task { [weak self] in
            guard let self else { return }
            await removeQuerySourceSnapshots()
            guard generation == queryGeneration,
                  text == currentQuery,
                  context == WalletCoreUniversalSearchFactory.currentContext() else {
                return
            }
            if query.isEmpty {
                scheduleBrowse(
                    context: context,
                    queryGeneration: generation,
                    trigger: .input
                )
                return
            }
            try? await Task.sleep(for: .milliseconds(40))
            guard !Task.isCancelled else { return }
            scheduleSearch(
                text,
                context: context,
                queryGeneration: generation,
                trigger: .input,
                inputStartedAt: inputStartedAt
            )
        }
    }

    private func refreshVisibleResults(for context: UniversalSearchContext) async {
        guard isStarted,
              context == currentContext else {
            return
        }

        if UniversalSearchQuery(currentQuery).isEmpty {
            scheduleBrowse(
                context: context,
                queryGeneration: queryGeneration,
                trigger: .sourceUpdate
            )
            return
        }

        scheduleSearch(
            currentQuery,
            context: context,
            queryGeneration: queryGeneration,
            trigger: .sourceUpdate,
            inputStartedAt: nil
        )
    }

    private func scheduleBrowse(
        context: UniversalSearchContext,
        queryGeneration: UInt64,
        trigger: BrowseTrigger
    ) {
        renderGeneration &+= 1
        let renderGeneration = renderGeneration
        renderTask?.cancel()
        renderTask = Task { [weak self] in
            if trigger.isSourceUpdate {
                try? await Task.sleep(for: .milliseconds(80))
                guard !Task.isCancelled else { return }
            }
            await self?.performBrowse(
                context: context,
                queryGeneration: queryGeneration,
                renderGeneration: renderGeneration,
                trigger: trigger
            )
        }
    }

    private func performBrowse(
        context: UniversalSearchContext,
        queryGeneration expectedQueryGeneration: UInt64,
        renderGeneration expectedRenderGeneration: UInt64,
        trigger: BrowseTrigger
    ) async {
        guard await coordinator.currentContext() == context else { return }
        let snapshot = await coordinator.browse()
        guard !Task.isCancelled,
              isStarted,
              expectedQueryGeneration == queryGeneration,
              expectedRenderGeneration == renderGeneration,
              UniversalSearchQuery(currentQuery).isEmpty,
              context == WalletCoreUniversalSearchFactory.currentContext() else {
            return
        }

        let presentation = presenter.browsePresentation(
            for: snapshot,
            selectedModes: browseSelectedModes,
            context: context
        )
        let hasContent = !presentation.sections.isEmpty
        let updateStyle: ResultsUpdateStyle = if hasContent, !hasPresentedBrowseContent {
            .diffable
        } else {
            trigger.updateStyle
        }
        hasPresentedBrowseContent = hasPresentedBrowseContent || hasContent
        apply(presentation, updateStyle: updateStyle)
    }

    private func scheduleSearch(
        _ text: String,
        context: UniversalSearchContext,
        queryGeneration: UInt64,
        trigger: QueryTrigger,
        inputStartedAt: CFAbsoluteTime?
    ) {
        renderGeneration &+= 1
        let renderGeneration = renderGeneration
        renderTask?.cancel()
        renderTask = Task { [weak self] in
            if trigger.isSourceUpdate {
                try? await Task.sleep(for: .milliseconds(80))
                guard !Task.isCancelled else { return }
            }
            await self?.performSearch(
                text,
                context: context,
                queryGeneration: queryGeneration,
                renderGeneration: renderGeneration,
                trigger: trigger,
                inputStartedAt: inputStartedAt
            )
        }
    }

    private func performSearch(
        _ text: String,
        context: UniversalSearchContext,
        queryGeneration expectedQueryGeneration: UInt64,
        renderGeneration expectedRenderGeneration: UInt64,
        trigger: QueryTrigger,
        inputStartedAt: CFAbsoluteTime?
    ) async {
        guard await coordinator.currentContext() == context else { return }
        let actorSearchStartedAt = CFAbsoluteTimeGetCurrent()
        let snapshot = await coordinator.search(text, limit: 64)
        let actorSearchMilliseconds = elapsedMilliseconds(since: actorSearchStartedAt)
        guard !Task.isCancelled,
              expectedQueryGeneration == queryGeneration,
              expectedRenderGeneration == renderGeneration,
              text == currentQuery,
              context == WalletCoreUniversalSearchFactory.currentContext() else {
            return
        }

        let projectionStartedAt = CFAbsoluteTimeGetCurrent()
        let presentation = presenter.presentation(for: snapshot, context: context)
        let projectionMilliseconds = elapsedMilliseconds(since: projectionStartedAt)
        let transitionStartedAt = CFAbsoluteTimeGetCurrent()
        apply(
            presentation,
            updateStyle: trigger.updateStyle
        ) { [weak self] in
            guard let self,
                  expectedQueryGeneration == queryGeneration,
                  expectedRenderGeneration == renderGeneration else { return }
#if DEBUG
            let inputToVisibleMilliseconds = inputStartedAt.map(elapsedMilliseconds(since:))
            log.info(
                "query visible trigger=\(trigger.rawValue, .public) chars=\(text.count, .public) corpus=\(snapshot.corpusDocumentCount, .public) hits=\(snapshot.totalHitCount, .public) sections=\(presentation.sections.count, .public) engine_top=\(snapshot.hits.first?.id.rawValue ?? "none", .public) engine_match=\(String(describing: snapshot.hits.first?.match.kind), .public) engine_field=\(String(describing: snapshot.hits.first?.match.fieldKind), .public) visible_top=\(presentation.preselectedItemID ?? "none", .public) engine_ms=\(formatted(snapshot.engineElapsedMilliseconds), .public) actor_search_ms=\(formatted(actorSearchMilliseconds), .public) projection_ms=\(formatted(projectionMilliseconds), .public) transition_ms=\(formatted(elapsedMilliseconds(since: transitionStartedAt)), .public) input_to_visible_ms=\(formatted(inputToVisibleMilliseconds), .public)"
            )
#endif
        }
        startQuerySources(
            query: snapshot.query,
            context: context,
            generation: expectedQueryGeneration
        )
#if DEBUG
        let inputToScheduleMilliseconds = inputStartedAt.map(elapsedMilliseconds(since:))
        log.info(
            "query scheduled trigger=\(trigger.rawValue, .public) chars=\(text.count, .public) corpus=\(snapshot.corpusDocumentCount, .public) hits=\(snapshot.totalHitCount, .public) engine_top=\(snapshot.hits.first?.id.rawValue ?? "none", .public) visible_top=\(presentation.preselectedItemID ?? "none", .public) engine_ms=\(formatted(snapshot.engineElapsedMilliseconds), .public) actor_search_ms=\(formatted(actorSearchMilliseconds), .public) projection_ms=\(formatted(projectionMilliseconds), .public) input_to_schedule_ms=\(formatted(inputToScheduleMilliseconds), .public)"
        )
#endif
    }

    private func startQuerySources(
        query: UniversalSearchQuery,
        context: UniversalSearchContext,
        generation: UInt64
    ) {
        guard querySourcesGeneration != generation else { return }
        querySourcesGeneration = generation
        querySourceTasks = querySources.map { source in
            Task { [weak self] in
                guard let self else { return }
                let startedAt = CFAbsoluteTimeGetCurrent()
                do {
                    for try await sourceSnapshot in source.snapshots(
                        for: query,
                        context: context
                    ) {
                        guard !Task.isCancelled,
                              generation == queryGeneration,
                              query.text == currentQuery,
                              context == WalletCoreUniversalSearchFactory.currentContext(),
                              sourceSnapshot.sourceID == source.sourceID else {
                            return
                        }
                        let snapshot = stamped(
                            sourceSnapshot,
                            queryGeneration: generation
                        )
                        let wasApplied = await coordinator.replace(
                            snapshot,
                            ifContext: context
                        )
                        guard wasApplied else { continue }
                        guard !Task.isCancelled,
                              generation == queryGeneration,
                              query.text == currentQuery,
                              context == WalletCoreUniversalSearchFactory.currentContext() else {
                            await coordinator.remove(
                                sourceID: snapshot.sourceID,
                                ifRevision: snapshot.revision
                            )
                            return
                        }
#if DEBUG
                        log.info(
                            "query source ready id=\(source.sourceID, .public) docs=\(snapshot.documents.count, .public) elapsed_ms=\(formatted(elapsedMilliseconds(since: startedAt)), .public)"
                        )
#endif
                        scheduleSearch(
                            query.text,
                            context: context,
                            queryGeneration: generation,
                            trigger: .querySource,
                            inputStartedAt: nil
                        )
                    }
                } catch is CancellationError {
                    return
                } catch {
#if DEBUG
                    log.error(
                        "query source failed id=\(source.sourceID, .public) error=\(String(describing: error), .public)"
                    )
#endif
                }
            }
        }
    }

    private func removeQuerySourceSnapshots() async {
        for source in querySources {
            await coordinator.remove(sourceID: source.sourceID)
        }
    }

    private func recordSelection(of entityID: SearchEntityID) {
        let context = WalletCoreUniversalSearchFactory.currentContext()
        guard let scopeID = context.scopeID else { return }
        interactionStore.recordSelection(of: entityID, scopeID: scopeID)
        let interactionSource = interactionSource
        let coordinator = coordinator
        Task {
            guard let snapshot = try? await interactionSource.snapshot(for: context) else { return }
            guard await coordinator.replace(snapshot, ifContext: context) else { return }
            guard isStarted, UniversalSearchQuery(currentQuery).isEmpty else { return }
            scheduleBrowse(
                context: context,
                queryGeneration: queryGeneration,
                trigger: .interaction
            )
        }
    }

    private func shouldRecordSelection(of item: UniversalSearchItem) -> Bool {
        if item.id == UniversalSearchResultsPresenter.startAgentConversationItemID {
            return false
        }
        return switch item.content {
        case .askAgent, .google, .openWebsite:
            false
        default:
            true
        }
    }

    private func toggleBrowseMode(for section: UniversalSearchSection) {
        guard UniversalSearchQuery(currentQuery).isEmpty,
              case .toggle(_, _, let selected) = section.headerAccessory else {
            return
        }
        browseSelectedModes[section.id] = selected == .primary ? .trending : .recent
        scheduleBrowse(
            context: WalletCoreUniversalSearchFactory.currentContext(),
            queryGeneration: queryGeneration,
            trigger: .modeToggle
        )
    }

    private func stamped(
        _ snapshot: UniversalSearchSourceSnapshot,
        queryGeneration: UInt64
    ) -> UniversalSearchSourceSnapshot {
        UniversalSearchSourceSnapshot(
            sourceID: snapshot.sourceID,
            authority: snapshot.authority,
            revision: "query:\(queryGeneration):\(snapshot.revision ?? "")",
            generatedAt: snapshot.generatedAt,
            expiresAt: snapshot.expiresAt,
            staleUntil: snapshot.staleUntil,
            documents: snapshot.documents,
            signalContributions: snapshot.signalContributions
        )
    }

    private func apply(
        _ presentation: UniversalSearchPresentation,
        updateStyle: ResultsUpdateStyle,
        completion: (() -> Void)? = nil
    ) {
        routesByItemID = presentation.routesByItemID
        let autocomplete = autocomplete(for: presentation)
        if autocomplete != lastAutocomplete {
            lastAutocomplete = autocomplete
            onAutocompleteChange?(autocomplete)
        }
        screen.setSections(
            presentation.sections,
            preselectedItemID: presentation.preselectedItemID,
            animated: updateStyle.animatesDifferences
        ) {
            completion?()
        }
    }

    private func autocomplete(
        for presentation: UniversalSearchPresentation
    ) -> UniversalSearchAutocomplete? {
        guard let preselectedItemID = presentation.preselectedItemID,
              let item = presentation.sections.lazy
                .flatMap(\.items)
                .first(where: { $0.id == preselectedItemID }) else {
            return nil
        }

        let typedText = currentQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !typedText.isEmpty else { return nil }
        switch item.content {
        case .askAgent(let query):
            return UniversalSearchAutocomplete(
                suggestion: query,
                actionTitle: lang("Ask Agent"),
                style: .agent
            )
        case .shortcut(let result):
            return standardAutocomplete(
                typedText: typedText,
                suggestion: result.title,
                actionTitle: lang("Open")
            )
        case .openWebsite:
            return UniversalSearchAutocomplete(
                suggestion: typedText,
                actionTitle: lang("Open Website")
            )
        case .token(let result):
            return standardAutocomplete(
                typedText: typedText,
                suggestion: result.title,
                actionTitle: lang("Open Token")
            )
        case .collectible(let result):
            return standardAutocomplete(
                typedText: typedText,
                suggestion: result.title,
                actionTitle: lang("Open Collectible")
            )
        case .collection(let result):
            return standardAutocomplete(
                typedText: typedText,
                suggestion: result.title,
                actionTitle: lang("Open Collection")
            )
        case .app(let result):
            return standardAutocomplete(
                typedText: typedText,
                suggestion: result.title,
                actionTitle: lang("Open App")
            )
        case .wallet(let result):
            return standardAutocomplete(
                typedText: typedText,
                suggestion: result.title,
                actionTitle: lang("Open Wallet")
            )
        case .chat(let result):
            return standardAutocomplete(
                typedText: typedText,
                suggestion: result.title,
                actionTitle: lang("Open Chat")
            )
        case .recentSearch(let result):
            return standardAutocomplete(
                typedText: typedText,
                suggestion: result.title,
                actionTitle: lang("Search in Google")
            )
        case .site(let result):
            let domain = result.subtitle.components(separatedBy: " · ").first ?? result.subtitle
            return standardAutocomplete(
                typedText: typedText,
                suggestion: domain,
                actionTitle: result.title
            )
        case .google, .prompt:
            return nil
        }
    }

    private func standardAutocomplete(
        typedText: String,
        suggestion: String,
        actionTitle: String
    ) -> UniversalSearchAutocomplete? {
        guard suggestion.range(
            of: typedText,
            options: [.anchored, .caseInsensitive, .diacriticInsensitive]
        ) != nil else {
            return nil
        }
        return UniversalSearchAutocomplete(
            suggestion: suggestion,
            actionTitle: actionTitle
        )
    }

    private func elapsedMilliseconds(since startedAt: CFAbsoluteTime) -> Double {
        (CFAbsoluteTimeGetCurrent() - startedAt) * 1_000
    }

    private func formatted(_ value: Double?) -> String {
        value.map { String(format: "%.2f", $0) } ?? "n/a"
    }
}

extension UniversalSearchFeatureSession: UniversalSearchIndexServiceObserver {
    func universalSearchIndexService(
        _: UniversalSearchIndexService,
        didUpdate update: UniversalSearchIndexUpdate
    ) {
        guard isStarted else { return }
        if currentContext != update.context {
            currentContext = update.context
            browseSelectedModes = [:]
            hasPresentedBrowseContent = false
            apply(.empty, updateStyle: .none)
        }
        guard case .source = update.kind else { return }
        Task { [weak self] in
            await self?.refreshVisibleResults(for: update.context)
        }
    }
}
