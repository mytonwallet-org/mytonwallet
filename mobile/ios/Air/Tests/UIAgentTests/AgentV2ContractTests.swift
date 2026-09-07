import XCTest
@testable import UIAgent
import WalletContext
@testable import WalletCore

final class AgentV2ContractTests: XCTestCase {
    @MainActor
    func testAgentSearchPreviewStripsMarkdownFormatting() {
        XCTAssertEqual(
            AgentStore.searchPreviewText("I am **My Wallet** with a [guide](https://mywallet.io)."),
            "I am My Wallet with a guide."
        )
    }

    func testDecodesModelOwnedFollowUpCopy() throws {
        let payloads = [
            (#"{"id":"adadadad-adad-4dad-8dad-adadadadadad","kind":"suggested_prompt","text":"Explain market analysis."}"#, "Explain market analysis."),
            (#"{"id":"adadadad-adad-4dad-8dad-adadadadadad","kind":"suggested_prompt","text":"Объясни анализ рынка."}"#, "Объясни анализ рынка."),
            (#"{"id":"adadadad-adad-4dad-8dad-adadadadadad","kind":"suggested_prompt","text":"xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"}"#, "xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"),
        ]

        for (payload, text) in payloads {
            let followup = try JSONDecoder().decode(ApiAgentV2FollowUp.self, from: Data(payload.utf8))
            XCTAssertEqual(followup.kind, "suggested_prompt")
            XCTAssertEqual(followup.text, text)
        }
    }

    func testRejectsInvalidModelOwnedFollowUpCopy() {
        let overlongText = String(repeating: "x", count: 81)
        let payloads = [
            #"{"id":"adadadad-adad-4dad-8dad-adadadadadad","kind":"deterministic","code":"prepare_send","intent":"prepare_candidate"}"#,
            #"{"id":"adadadad-adad-4dad-8dad-adadadadadad","kind":"suggested_prompt","text":" Detailed analysis"}"#,
            #"{"id":"adadadad-adad-4dad-8dad-adadadadadad","kind":"suggested_prompt","text":"Explain\nthis market analysis."}"#,
            #"{"id":"adadadad-adad-4dad-8dad-adadadadadad","kind":"suggested_prompt","text":"**Detailed analysis**"}"#,
            #"{"id":"adadadad-adad-4dad-8dad-adadadadadad","kind":"suggested_prompt","text":"\#(overlongText)"}"#,
        ]

        for payload in payloads {
            XCTAssertThrowsError(
                try JSONDecoder().decode(ApiAgentV2FollowUp.self, from: Data(payload.utf8)),
                payload
            )
        }
    }

    func testFiltersInvalidFollowUpsWithoutDroppingPersistedMessage() throws {
        let json = #"{"id":"11111111-1111-4111-8111-111111111111","threadId":"22222222-2222-4222-8222-222222222222","role":"assistant","status":"complete","content":{"kind":"markdown","text":"Still readable"},"createdAt":"2026-08-27T00:00:00.000Z","followups":[{"id":"33333333-3333-4333-8333-333333333333","kind":"deterministic","code":"prepare_send","intent":"prepare_candidate"},{"id":"adadadad-adad-4dad-8dad-adadadadadad","kind":"suggested_prompt","text":"Help me prepare a transfer."},{"id":"44444444-4444-4444-8444-444444444444","kind":"suggested_prompt","text":"**Invalid**"}]}"#
        let message = try JSONDecoder().decode(ApiAgentV2PersistedMessage.self, from: Data(json.utf8))

        XCTAssertEqual(message.followups?.map(\.text), ["Help me prepare a transfer."])
        guard case .some(.markdown(let text)) = message.content else {
            return XCTFail("Expected persisted Markdown body")
        }
        XCTAssertEqual(text, "Still readable")
    }

    func testFiltersInvalidFollowUpsFromClientUpdate() throws {
        let json = #"{"kind":"followupsAvailable","clientRunId":"11111111-1111-4111-8111-111111111111","runId":"22222222-2222-4222-8222-222222222222","threadId":"33333333-3333-4333-8333-333333333333","messageId":"44444444-4444-4444-8444-444444444444","items":[{"id":"55555555-5555-4555-8555-555555555555","kind":"deterministic","code":"prepare_send","intent":"prepare_candidate"},{"id":"adadadad-adad-4dad-8dad-adadadadadad","kind":"suggested_prompt","text":"Help me prepare a transfer."}]}"#
        let update = try JSONDecoder().decode(ApiAgentV2ClientUpdate.self, from: Data(json.utf8))

        guard case .followupsAvailable(_, _, let items) = update else {
            return XCTFail("Expected follow-up update")
        }
        XCTAssertEqual(items.map(\.text), ["Help me prepare a transfer."])
    }

    func testCapsClientFollowUpsWithoutDroppingValidItems() throws {
        let json = #"{"kind":"followupsAvailable","clientRunId":"11111111-1111-4111-8111-111111111111","runId":"22222222-2222-4222-8222-222222222222","threadId":"33333333-3333-4333-8333-333333333333","messageId":"44444444-4444-4444-8444-444444444444","items":[{"id":"55555555-5555-4555-8555-555555555555","kind":"deterministic"},{"id":"adadadad-adad-4dad-8dad-adadadadadad","kind":"suggested_prompt","text":"First prompt."},{"id":"adadadad-adad-4dad-8dad-adadadadadad","kind":"suggested_prompt","text":"Duplicate id."},{"id":"bdbdbdbd-bdbd-4dbd-8dbd-bdbdbdbdbdbd","kind":"suggested_prompt","text":"Second prompt."},{"id":"cdcdcdcd-cdcd-4dcd-8dcd-cdcdcdcdcdcd","kind":"suggested_prompt","text":"Third prompt."},{"id":"dededede-dede-4ede-8ede-dededededede","kind":"suggested_prompt","text":"Fourth prompt."}]}"#
        let update = try JSONDecoder().decode(ApiAgentV2ClientUpdate.self, from: Data(json.utf8))

        guard case .followupsAvailable(_, _, let items) = update else {
            return XCTFail("Expected follow-up update")
        }
        XCTAssertEqual(items.map(\.text), ["First prompt.", "Second prompt.", "Third prompt."])
    }

    func testDecodesMessageContentEndIndependentlyFromRunCompletion() throws {
        let json = #"{"kind":"messageContentEnded","clientRunId":"11111111-1111-4111-8111-111111111111","runId":"22222222-2222-4222-8222-222222222222","threadId":"33333333-3333-4333-8333-333333333333","messageId":"44444444-4444-4444-8444-444444444444"}"#
        let update = try JSONDecoder().decode(ApiAgentV2ClientUpdate.self, from: Data(json.utf8))

        guard case .messageContentEnded(_, let messageId) = update else {
            return XCTFail("Expected message content end update")
        }
        XCTAssertEqual(messageId, "44444444-4444-4444-8444-444444444444")
    }

    func testCurrentCanonicalNoticeCodesDecodeAsSupportedSemanticContent() throws {
        let payloads = [
            #"{"kind":"notice","schemaVersion":1,"code":"analysis_unavailable","arguments":{"analysisFailure":"planning_unavailable"}}"#,
            #"{"kind":"notice","schemaVersion":1,"code":"receive_details_required","arguments":{"receiveFields":["asset","network"]}}"#,
            #"{"kind":"notice","schemaVersion":1,"code":"send_form_amount_required"}"#,
            #"{"kind":"notice","schemaVersion":1,"code":"staking_ready"}"#,
            #"{"kind":"notice","schemaVersion":1,"code":"staking_unavailable","arguments":{"stakeFailure":"planning_unavailable"}}"#,
            #"{"kind":"notice","schemaVersion":1,"code":"swap_details_required","arguments":{"swapDetails":{"field":"direction"}}}"#,
            #"{"kind":"notice","schemaVersion":1,"code":"swap_ready","arguments":{"swapReady":{"sourceAsset":{"slug":"toncoin","chain":"ton","symbol":"TON"},"destinationAsset":{"slug":"usdton","chain":"ton","symbol":"USDT"},"amount":{"value":"1","valueType":"decimal","side":"source"},"quote":{"status":"unavailable","reason":"price_unavailable","observedAt":"2026-08-24T00:00:00.000Z"}}}}"#,
            #"{"kind":"notice","schemaVersion":1,"code":"swap_unavailable","arguments":{"swapFailure":"planning_unavailable"}}"#,
        ]

        for payload in payloads {
            let content = try JSONDecoder().decode(
                ApiAgentV2SemanticContent.self,
                from: Data(payload.utf8)
            )
            guard case .notice(let notice) = content else {
                XCTFail("Canonical notice decoded as unsupported: \(payload)")
                continue
            }
            XCTAssertFalse(AgentV2Copy.notice(notice).isEmpty)
            XCTAssertNotEqual(AgentV2Copy.notice(notice), lang("$agent_semantic_update_required"))
        }
    }

    func testReceiveNetworkNoticeUsesTypedArgumentsAndFallsBackSafely() throws {
        let unsupported = try JSONDecoder().decode(
            ApiAgentV2NoticeContent.self,
            from: Data(#"{"kind":"notice","schemaVersion":1,"code":"receive_unavailable","arguments":{"receiveFailure":"chain_unsupported","requestedChain":"tron","activeChain":"ton","futureDisplay":{"emphasis":"network"}}}"#.utf8)
        )
        let unsupportedText = AgentV2Copy.notice(unsupported)
        XCTAssertNotEqual(unsupportedText, AgentV2Copy.notice(.receiveUnavailable))

        let incomplete = try JSONDecoder().decode(
            ApiAgentV2NoticeContent.self,
            from: Data(#"{"kind":"notice","schemaVersion":1,"code":"receive_unavailable","arguments":{"receiveFailure":"active_network_mismatch","requestedChain":"tron"}}"#.utf8)
        )
        XCTAssertEqual(AgentV2Copy.notice(incomplete), AgentV2Copy.notice(.receiveUnavailable))

        let unknown = try JSONDecoder().decode(
            ApiAgentV2NoticeContent.self,
            from: Data(#"{"kind":"notice","schemaVersion":1,"code":"receive_unavailable","arguments":{"receiveFailure":"future_reason","requestedChain":"tron","activeChain":"ton"}}"#.utf8)
        )
        XCTAssertEqual(AgentV2Copy.notice(unknown), AgentV2Copy.notice(.receiveUnavailable))
    }

    func testMarketQuoteNoticeDecodesClosedStates() throws {
        let resolved = try JSONDecoder().decode(
            ApiAgentV2NoticeContent.self,
            from: Data(#"{"kind":"notice","schemaVersion":1,"code":"market_quote","arguments":{"marketQuote":{"status":"resolved","asset":{"slug":"gram","chain":"ton","symbol":"GRAM","name":"Gram **[literal]**"},"price":"0.004321","quoteCurrency":"USD","percentChange24h":"1.25","asOf":"2026-08-16T12:00:00.000Z","futureDisplay":"ignored"}}}"#.utf8)
        )
        XCTAssertEqual(resolved.marketQuote?.status, .resolved)
        XCTAssertEqual(
            AgentV2Copy.marketQuoteAsset(try XCTUnwrap(resolved.marketQuote?.asset)),
            "Gram **[literal]** (GRAM)"
        )
        let ambiguous = try JSONDecoder().decode(
            ApiAgentV2NoticeContent.self,
            from: Data(#"{"kind":"notice","schemaVersion":1,"code":"market_quote","arguments":{"marketQuote":{"status":"ambiguous","candidates":[{"slug":"gram-ton","chain":"ton","symbol":"GRAM"},{"slug":"gram-eth","chain":"eth","symbol":"GRAM"}],"hasMore":true,"asOf":"2026-08-16T12:00:00.000Z"}}}"#.utf8)
        )
        XCTAssertEqual(ambiguous.marketQuote?.candidates?.count, 2)
        let priceUnavailable = try JSONDecoder().decode(
            ApiAgentV2NoticeContent.self,
            from: Data(#"{"kind":"notice","schemaVersion":1,"code":"market_quote","arguments":{"marketQuote":{"status":"price_unavailable","asset":{"slug":"gram","chain":"ton","symbol":"GRAM"},"asOf":"2026-08-16T12:00:00.000Z"}}}"#.utf8)
        )
        XCTAssertEqual(priceUnavailable.marketQuote?.status, .priceUnavailable)

        let notFound = try JSONDecoder().decode(
            ApiAgentV2NoticeContent.self,
            from: Data(#"{"kind":"notice","schemaVersion":1,"code":"market_quote","arguments":{"marketQuote":{"status":"not_found","asOf":"2026-08-16T12:00:00.000Z"}}}"#.utf8)
        )
        XCTAssertEqual(notFound.marketQuote?.status, .notFound)

        XCTAssertThrowsError(try JSONDecoder().decode(
            ApiAgentV2NoticeContent.self,
            from: Data(#"{"kind":"notice","schemaVersion":1,"code":"market_quote","arguments":{"marketQuote":{"status":"resolved","asset":{"slug":"gram","chain":"ton","symbol":"GRAM"},"price":"1","quoteCurrency":"USD","percentChange24h":"0"}}}"#.utf8)
        ))
    }

    @MainActor
    func testMarketQuoteUsesTheOrdinaryAssistantBubble() throws {
        let persisted = try decodePersistedMessage(content: [
            "kind": "semantic",
            "content": [
                "kind": "notice",
                "schemaVersion": 1,
                "code": "market_quote",
                "arguments": [
                    "marketQuote": [
                        "status": "resolved",
                        "asset": [
                            "slug": "gram",
                            "chain": "ton",
                            "symbol": "GRAM",
                            "name": "Gram **literal**"
                        ],
                        "price": "1.25",
                        "quoteCurrency": "USD",
                        "percentChange24h": "2",
                        "asOf": "2026-08-16T12:00:00.000Z"
                    ]
                ]
            ]
        ])
        let bubble = try XCTUnwrap(
            AgentV2MessagePresentation.bubble(for: AgentV2NativeMessage(persisted: persisted))
        )

        guard case .some(.semantic(let semantic)) = persisted.content,
              case .notice(let notice) = semantic
        else { return XCTFail("Expected market quote notice") }
        XCTAssertEqual(bubble.text, AgentV2Copy.notice(notice))
        XCTAssertFalse(bubble.rendersMarkdown)
    }

    func testDecodesLiveSendContract() throws {
        let action = try JSONDecoder().decode(
            ApiAgentV2ResolvedAction.self,
            from: Data(#"{"kind":"sendForm","tokenSlug":"toncoin","toAddress":"UQ-recipient"}"#.utf8)
        )
        XCTAssertEqual(action.kind, .openSend)
        XCTAssertEqual(action.tokenSlug, "toncoin")
        XCTAssertEqual(action.toAddress, "UQ-recipient")
    }

    func testDecodesNativeStakeAndSwapActionContracts() throws {
        let stakeProposal = try JSONDecoder().decode(
            ApiAgentV2ActionProposal.self,
            from: Data(#"{"id":"action-stake","kind":"stake","labelCode":"open_staking","requiresConfirmation":false}"#.utf8)
        )
        XCTAssertEqual(stakeProposal.kind, .stake)
        XCTAssertEqual(stakeProposal.labelCode, .openStaking)

        let persistedSwap = try JSONDecoder().decode(
            ApiAgentV2PersistedAction.self,
            from: Data(#"{"id":"action-swap","kind":"swap","labelCode":"open_swap","requiresConfirmation":false}"#.utf8)
        )
        XCTAssertEqual(persistedSwap.kind, .swap)
        XCTAssertEqual(persistedSwap.labelCode, .openSwap)

        let staking = try JSONDecoder().decode(
            ApiAgentV2ResolvedAction.self,
            from: Data(#"{"kind":"openStaking","productId":"liquid","tokenSlug":"toncoin","amount":{"kind":"exact","value":"10"}}"#.utf8)
        )
        XCTAssertEqual(staking.kind, .openStaking)
        XCTAssertEqual(staking.productId, "liquid")
        XCTAssertEqual(staking.tokenSlug, "toncoin")
        XCTAssertEqual(staking.stakeAmount?.kind, .exact)
        XCTAssertEqual(staking.stakeAmount?.value, "10")

        let swap = try JSONDecoder().decode(
            ApiAgentV2ResolvedAction.self,
            from: Data(#"{"kind":"openSwap","tokenInSlug":"toncoin","tokenOutSlug":"usdton","amount":"10","amountSide":"source"}"#.utf8)
        )
        XCTAssertEqual(swap.kind, .openSwap)
        XCTAssertEqual(swap.tokenInSlug, "toncoin")
        XCTAssertEqual(swap.tokenOutSlug, "usdton")
        XCTAssertEqual(swap.swapAmount, "10")
        XCTAssertEqual(swap.amountSide, .source)

        let navigation = try JSONDecoder().decode(
            ApiAgentV2ResolvedAction.self,
            from: Data(#"{"kind":"openToken","slug":"toncoin","chain":"ton","tokenAddress":"EQ-token"}"#.utf8)
        )
        XCTAssertEqual(navigation.kind, .openToken)
        XCTAssertEqual(navigation.slug, "toncoin")
        XCTAssertEqual(navigation.chain, "ton")
        XCTAssertEqual(navigation.tokenAddress, "EQ-token")
    }

    func testDecodesEveryOpenAgentEntryPointShape() throws {
        let tokenScreen = try JSONDecoder().decode(
            ApiAgentV2ResolvedAction.self,
            from: Data(#"{"kind":"openAgent","entryPoint":{"kind":"tokenScreen","asset":{"slug":"toncoin","chain":"ton"}}}"#.utf8)
        )
        guard case .tokenScreen(let asset) = tokenScreen.entryPoint else {
            return XCTFail("Expected token screen entry point")
        }
        XCTAssertEqual(asset.slug, "toncoin")
        XCTAssertEqual(asset.chain, "ton")
        XCTAssertNil(asset.tokenAddress)

        let emptyState = try JSONDecoder().decode(
            ApiAgentV2ResolvedAction.self,
            from: Data(#"{"kind":"openAgent","entryPoint":{"kind":"emptyState","surface":"agentTab"}}"#.utf8)
        )
        guard case .emptyState(let hintId, let catalogVersion) = emptyState.entryPoint else {
            return XCTFail("Expected empty state entry point")
        }
        XCTAssertNil(hintId)
        XCTAssertNil(catalogVersion)

        XCTAssertThrowsError(try JSONDecoder().decode(
            ApiAgentV2ResolvedAction.self,
            from: Data(#"{"kind":"openAgent","entryPoint":{"kind":"emptyState","surface":"portfolio"}}"#.utf8)
        ))
    }

    @MainActor
    func testStakingOffersUseTheTonProductSelectedByNativeNavigation() {
        let liquid = ApiStakingState.liquid(ApiStakingStateLiquid(
            id: "liquid",
            tokenSlug: TONCOIN_SLUG,
            annualYield: 3,
            yieldType: .apy,
            balance: 1,
            pool: "liquid-pool",
            unstakeRequestAmount: nil,
            tokenBalance: 1,
            instantAvailable: 0,
            start: 0,
            end: 0,
            totalStakers: 1,
            tvl: 1
        ))
        let nominators = ApiStakingState.nominators(ApiStakingStateNominators(
            id: "nominators",
            tokenSlug: TONCOIN_SLUG,
            annualYield: 4,
            yieldType: .apy,
            balance: 1,
            pool: "nominators-pool",
            unstakeRequestAmount: nil,
            start: 0,
            end: 0
        ))

        XCTAssertEqual(
            AgentV2HostContextProvider.selectStakingOfferStates(
                [liquid, nominators],
                shouldUseNominators: false
            ).map(\.id),
            ["liquid"]
        )
        XCTAssertEqual(
            AgentV2HostContextProvider.selectStakingOfferStates(
                [liquid, nominators],
                shouldUseNominators: true
            ).map(\.id),
            ["nominators"]
        )
    }

    @MainActor
    func testHostHoldingUsesCurrentBalanceAsAvailableBalance() {
        let token = ApiToken(
            slug: "test-token",
            name: "Test Token",
            symbol: "TEST",
            decimals: 9,
            chain: .ton
        )
        let tokenBalance = MTokenBalance(
            tokenSlug: token.slug,
            balance: 1_234_567_890,
            isStaking: false
        )

        let holding = AgentV2HostContextProvider.makeHolding(tokenBalance: tokenBalance, token: token)

        XCTAssertEqual(holding.balance, "1.23456789")
        XCTAssertEqual(holding.availableBalance, holding.balance)
        XCTAssertEqual(holding.visibility, "visible")

        let hiddenHolding = AgentV2HostContextProvider.makeHolding(
            tokenBalance: tokenBalance,
            token: token,
            visibility: "hidden"
        )
        XCTAssertEqual(hiddenHolding.visibility, "hidden")

        let stakedHolding = AgentV2HostContextProvider.makeHolding(
            tokenBalance: MTokenBalance(tokenSlug: token.slug, balance: 1_234_567_890, isStaking: true),
            token: token
        )
        XCTAssertNil(stakedHolding.availableBalance)
    }

    @MainActor
    func testSavedAddressIdentifiersRemainStableAcrossReordering() {
        let addresses = [
            SavedAddress(name: "Mom", address: "EQ-mom", chain: .ton),
            SavedAddress(name: "Alice", address: "0x-alice", chain: .ethereum)
        ]

        let first = AgentV2HostContextProvider.makeSavedAddresses(addresses)
        let reordered = AgentV2HostContextProvider.makeSavedAddresses(Array(addresses.reversed()))

        XCTAssertEqual(first.map(\.id), ["ton:EQ-mom", "ethereum:0x-alice"])
        XCTAssertEqual(
            Dictionary(uniqueKeysWithValues: first.map { ($0.address, $0.id) }),
            Dictionary(uniqueKeysWithValues: reordered.map { ($0.address, $0.id) })
        )
    }

    @MainActor
    func testSwapCatalogDoesNotApplyTheFormerIOSOnlyFiveHundredAssetCap() {
        let ordinary = (0..<600).map { index in
            ApiToken(
                slug: "ordinary-\(index)",
                name: "Ordinary \(index)",
                symbol: "O\(index)",
                decimals: 9,
                chain: .ton,
                tokenAddress: "token-\(index)"
            )
        }
        let tether = ApiToken(
            slug: "ton-tether",
            name: "Tether USD",
            symbol: "USD₮",
            decimals: 6,
            chain: .ton,
            tokenAddress: "tether-token",
            isPopular: true
        )

        let catalog = AgentV2HostContextProvider.makeSwapAssetCatalog(
            tokens: ordinary + [tether]
        )

        XCTAssertEqual(catalog?.count, 601)
        XCTAssertTrue(catalog?.contains(where: { $0.slug == tether.slug }) == true)
    }

    func testHydratedMarkdownMessageUsesTheContentUnion() throws {
        let source = "Wallet **warning:** keep TON for fees."
        let persisted = try decodePersistedMessage(content: [
            "kind": "markdown",
            "text": source
        ])

        let message = AgentV2NativeMessage(persisted: persisted)

        XCTAssertEqual(message.contentKind, .markdown)
        XCTAssertEqual(message.text, source)
        XCTAssertNil(message.semanticContent)
    }

    func testRemovedPersistedPresentationFieldsFailClosed() throws {
        for field in ["text", "textFormat", "widget"] {
            var object = persistedMessageObject(content: ["kind": "markdown", "text": "Current"])
            object[field] = field == "widget" ? ["kind": "removedWidget"] : "legacy"
            let data = try JSONSerialization.data(withJSONObject: object)

            XCTAssertThrowsError(
                try JSONDecoder().decode(ApiAgentV2PersistedMessage.self, from: data),
                "Expected removed field \(field) to fail closed"
            )
        }
    }

    @MainActor
    func testAgentMarkdownV1RendersRestrainedInlineAndListSyntax() {
        let rendered = AgentMessageTextRenderer.makeAttributedText(
            "Wallet **warning:** keep `GRAM` for fees.\n- First item\n- Second *item*\n1. Verify\n2) Review",
            textColor: .label,
            rendersMarkdown: true,
            detectsLinks: false,
            markdownProfile: .agentMarkdownV1
        )

        XCTAssertEqual(
            rendered.string,
            "Wallet warning: keep GRAM for fees.\n•\tFirst item\n•\tSecond item\n1.\tVerify\n2.\tReview"
        )
    }

    @MainActor
    func testAgentMarkdownV1RendersEscapedPunctuationAsLiteralText() {
        let rendered = AgentMessageTextRenderer.makeAttributedText(
            #"Daily changes: \+1\.62% and \-2\.01%. Escaped \*\*literal\*\*."#,
            textColor: .label,
            rendersMarkdown: true,
            detectsLinks: false,
            markdownProfile: .agentMarkdownV1
        )

        XCTAssertEqual(
            rendered.string,
            "Daily changes: +1.62% and -2.01%. Escaped **literal**."
        )
    }

    @MainActor
    func testAgentMarkdownV1KeepsLinksPassiveAndUnsupportedBlocksReadable() {
        let rendered = AgentMessageTextRenderer.makeAttributedText(
            "# Heading\n> Quote\n**unfinished\n[Source](https://example.com/path_with_value)\n[Receive](mtw://receive)",
            textColor: .label,
            rendersMarkdown: true,
            detectsLinks: false,
            markdownProfile: .agentMarkdownV1
        )

        XCTAssertEqual(
            rendered.string,
            "# Heading\n> Quote\n**unfinished\nSource (https://example.com/path_with_value)\nReceive"
        )
        let fullRange = NSRange(location: 0, length: rendered.length)
        var containsLink = false
        rendered.enumerateAttribute(.link, in: fullRange) { value, _, stop in
            if value != nil {
                containsLink = true
                stop.pointee = true
            }
        }
        XCTAssertFalse(containsLink)
    }

    @MainActor
    func testAgentMarkdownV1RendersTaggedFencedCodeWithoutMarkers() {
        let rendered = AgentMessageTextRenderer.makeAttributedText(
            "```javascript\nconst safe = true;\n```",
            textColor: .label,
            rendersMarkdown: true,
            detectsLinks: false,
            markdownProfile: .agentMarkdownV1
        )

        XCTAssertEqual(rendered.string, "const safe = true;")
    }

    @MainActor
    func testAgentMarkdownV1KeepsUntaggedFencesReadable() {
        let rendered = AgentMessageTextRenderer.makeAttributedText(
            "```\nconst safe = true;\n```",
            textColor: .label,
            rendersMarkdown: true,
            detectsLinks: false,
            markdownProfile: .agentMarkdownV1
        )

        XCTAssertEqual(rendered.string, "```\nconst safe = true;\n```")
    }

    func testOverrideConfigDefaultsToV1WhenMissingOrInvalid() {
        XCTAssertEqual(AgentOverrideConfig.resolve(data: nil), AgentOverrideConfig(value: .v1))
        XCTAssertEqual(
            AgentOverrideConfig.resolve(data: Data(#"{"override":"invalid"}"#.utf8)),
            AgentOverrideConfig(value: .v1)
        )
    }

    func testOverrideConfigDecodesSupportedValues() {
        for value in AgentOverrideConfig.Value.allCases {
            let data = Data(#"{"override":"\#(value.rawValue)"}"#.utf8)
            XCTAssertEqual(AgentOverrideConfig.resolve(data: data), AgentOverrideConfig(value: value))
        }
    }

    func testOverrideConfigResolvesBackendAndForcedVersions() {
        XCTAssertEqual(AgentOverrideConfig(value: .noOverride).resolve(backendVersion: .v2), .v2)
        XCTAssertEqual(AgentOverrideConfig(value: .v1).resolve(backendVersion: .v2), .v1)
        XCTAssertEqual(AgentOverrideConfig(value: .v2).resolve(backendVersion: .v1), .v2)
    }

    func testDecodesBoundTextDelta() throws {
        let data = Data(#"""
        {
          "type":"agentV2",
          "update":{
            "kind":"textDelta",
            "clientRunId":"client-run",
            "runId":"run-1",
            "threadId":"thread-1",
            "messageId":"message-1",
            "delta":"Hello"
          }
        }
        """#.utf8)

        let envelope = try JSONDecoder().decode(ApiAgentV2ClientUpdateEnvelope.self, from: data)
        guard case .textDelta(let bound, let messageId, let delta) = envelope.update else {
            return XCTFail("Expected text delta")
        }
        XCTAssertEqual(bound.threadId, "thread-1")
        XCTAssertEqual(messageId, "message-1")
        XCTAssertEqual(delta, "Hello")
    }

    func testDecodesRuntimeReadyAndToolActivityUpdates() throws {
        let ready = try JSONDecoder().decode(
            ApiAgentV2ClientUpdateEnvelope.self,
            from: Data(#"{"type":"agentV2","update":{"kind":"runtimeReady","generation":7}}"#.utf8)
        )
        guard case .runtimeReady(let generation) = ready.update else {
            return XCTFail("Expected runtime-ready update")
        }
        XCTAssertEqual(generation, 7)

        let activity = try JSONDecoder().decode(
            ApiAgentV2ClientUpdateEnvelope.self,
            from: Data(#"""
            {
              "type":"agentV2",
              "update":{
                "kind":"toolActivityChanged",
                "clientRunId":"client-run",
                "runId":"run-1",
                "threadId":"thread-1",
                "toolCallId":"tool-call-1",
                "toolName":"wallet.data.query",
                "operation":"positions.list",
                "status":"complete"
              }
            }
            """#.utf8)
        )
        guard case .toolActivityChanged(
            let bound,
            let toolCallId,
            let toolName,
            let operation,
            let status
        ) = activity.update else {
            return XCTFail("Expected tool-activity update")
        }
        XCTAssertEqual(bound.threadId, "thread-1")
        XCTAssertEqual(toolCallId, "tool-call-1")
        XCTAssertEqual(toolName, "wallet.data.query")
        XCTAssertEqual(operation, "positions.list")
        XCTAssertEqual(status, "complete")
    }

    func testDecodesRunActivityUpdate() throws {
        let update = try decodeRunActivityUpdate(threadId: "thread-1")

        guard case .runActivityChanged(let bound, let event) = update else {
            return XCTFail("Expected run-activity update")
        }
        XCTAssertEqual(bound.threadId, "thread-1")
        XCTAssertEqual(event.protocolVersion, 2)
        XCTAssertEqual(event.sequence, 3)
        XCTAssertEqual(event.code, .webReadingSources)
        XCTAssertEqual(event.status, .completed)
        XCTAssertEqual(event.detail?.kind, .sourceCount)
        XCTAssertEqual(event.detail?.count, 4)
    }

    func testDecodesAvailabilityAndQuotaUpdates() throws {
        let availabilityEnvelope = try JSONDecoder().decode(
            ApiAgentV2ClientUpdateEnvelope.self,
            from: Data(#"{"type":"agentV2","update":{"kind":"availabilityChanged","availability":{"state":"capacity_exhausted","resetAt":1787752800000}}}"#.utf8)
        )
        guard case .availabilityChanged(let availability) = availabilityEnvelope.update else {
            return XCTFail("Expected availability update")
        }
        XCTAssertEqual(availability.state, .capacityExhausted)
        XCTAssertEqual(availability.resetAt, 1_787_752_800_000)

        let quotaEnvelope = try JSONDecoder().decode(
            ApiAgentV2ClientUpdateEnvelope.self,
            from: Data(#"{"type":"agentV2","update":{"kind":"userQuotaChanged","quota":{"limit":100,"used":100,"remaining":0,"resetAt":"2099-08-27T00:00:00.000Z"}}}"#.utf8)
        )
        guard case .userQuotaChanged(let quota) = quotaEnvelope.update else {
            return XCTFail("Expected user-quota update")
        }
        XCTAssertEqual(quota?.limit, 100)
        XCTAssertEqual(quota?.remaining, 0)

        let clearedQuotaEnvelope = try JSONDecoder().decode(
            ApiAgentV2ClientUpdateEnvelope.self,
            from: Data(#"{"type":"agentV2","update":{"kind":"userQuotaChanged"}}"#.utf8)
        )
        guard case .userQuotaChanged(nil) = clearedQuotaEnvelope.update else {
            return XCTFail("Expected cleared user-quota update")
        }
    }

    func testRunFailurePreservesRetryBinding() throws {
        let envelope = try JSONDecoder().decode(
            ApiAgentV2ClientUpdateEnvelope.self,
            from: Data(#"{"type":"agentV2","update":{"kind":"runFailed","clientRunId":"client-1","threadId":"thread-1","messageId":"message-1","code":"user_quota_exhausted","retryable":true,"resetAt":1787752800000}}"#.utf8)
        )
        guard case .runFailed(
            _,
            let clientRunId,
            let threadId,
            let messageId,
            let code,
            let retryable,
            let resetAt
        ) = envelope.update else {
            return XCTFail("Expected run failure")
        }
        XCTAssertEqual(clientRunId, "client-1")
        XCTAssertEqual(threadId, "thread-1")
        XCTAssertEqual(messageId, "message-1")
        XCTAssertEqual(code, .userQuotaExhausted)
        XCTAssertTrue(retryable)
        XCTAssertEqual(resetAt, 1_787_752_800_000)
    }

    func testDecodesAgentPortfolioHistoryUpdate() throws {
        let data = Data(#"{"type":"agentV2PortfolioHistory","accountId":"account-1","baseCurrency":"USD","range":"1D","fetchedAtSlot":7,"netWorth":{"status":"ok","datasets":[],"base":"USD","density":"5m"}}"#.utf8)
        let update = try JSONDecoder().decode(ApiAgentV2PortfolioHistoryUpdate.self, from: data)

        XCTAssertEqual(update.type, .portfolioHistory)
        XCTAssertEqual(update.accountId, "account-1")
        XCTAssertEqual(update.range, .day)
        XCTAssertEqual(update.fetchedAtSlot, 7)
    }

    func testDecodesInputContinuationsAndEncodesTheirRunReference() throws {
        let data = Data(#"""
        {
          "type":"agentV2",
          "update":{
            "kind":"inputContinuationsAvailable",
            "clientRunId":"client-run",
            "runId":"run-1",
            "threadId":"thread-1",
            "messageId":"message-1",
            "items":[{
              "id":"continuation-amount",
              "kind":"collect_input",
              "code":"prepare_send_amount",
              "scenario":"prepare-send",
              "field":"amount"
            }]
          }
        }
        """#.utf8)

        let envelope = try JSONDecoder().decode(ApiAgentV2ClientUpdateEnvelope.self, from: data)
        guard case .inputContinuationsAvailable(let bound, let messageId, let items) = envelope.update else {
            return XCTFail("Expected input continuations")
        }
        XCTAssertEqual(bound.threadId, "thread-1")
        XCTAssertEqual(messageId, "message-1")
        XCTAssertEqual(items.first?.code, .prepareSendAmount)
        XCTAssertEqual(items.first?.field, "amount")

        let command = ApiAgentV2RunCommand(
            threadId: "thread-1",
            expectedThreadRevision: 1,
            input: .append(text: "10"),
            entryPoint: nil,
            continuationOf: .init(messageId: "message-1", continuationId: "continuation-amount")
        )
        let encoded = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(command)) as? [String: Any]
        )
        XCTAssertEqual(
            (encoded["continuationOf"] as? [String: Any])?["continuationId"] as? String,
            "continuation-amount"
        )
    }

    func testOrdinaryIOSRunCommandCannotAttachWalletConversationAuthority() throws {
        let command = ApiAgentV2RunCommand(
            threadId: "thread-1",
            expectedThreadRevision: 7,
            input: .append(text: "What changed?"),
            entryPoint: nil
        )
        let encoded = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(command)) as? [String: Any]
        )
        XCTAssertNil(encoded["walletScopeSelectionOf"])
    }

    func testRejectsUnknownUpdateKind() {
        let data = Data(#"{"type":"agentV2","update":{"kind":"futureUpdate"}}"#.utf8)
        XCTAssertThrowsError(try JSONDecoder().decode(ApiAgentV2ClientUpdateEnvelope.self, from: data))
    }

    func testDecodesEverySemanticContentVariant() throws {
        let fixtures: [[String: Any]] = [
            ["kind": "notice", "schemaVersion": 1, "code": "empty_result"],
            [
                "kind": "walletQuery", "schemaVersion": 1, "queryKind": "transactions",
                "outcome": "complete", "hasMore": false,
                "rows": [[
                    "chain": "ton", "transactionType": "transfer", "status": "completed",
                    "timestamp": "2026-07-30T00:00:00.000Z", "assetSymbol": "TON", "quantity": "1.5"
                ]]
            ],
            [
                "kind": "portfolio", "schemaVersion": 1, "view": "positions", "outcome": "partial",
                "payload": [
                    "id": "portfolio-1", "status": "partial", "accountScope": "current",
                    "baseCurrency": "USD", "generatedAt": "2026-07-30T00:00:00.000Z",
                    "positions": [], "unpriced": [], "omittedUnpricedAssetCount": 0,
                    "dataQuality": ["coverage": "partial", "limitations": ["unpriced_assets"]]
                ]
            ],
            [
                "kind": "market", "schemaVersion": 1, "view": "overview", "outcome": "complete",
                "evidence": ["assets": []], "narrativeMarkdown": "Market **summary**."
            ],
            [
                "kind": "assetSearch", "schemaVersion": 1, "outcome": "complete_absent",
                "reason": "not_found"
            ],
            [
                "kind": "webDigest", "schemaVersion": 1, "outcome": "complete", "summary": "Latest news",
                "items": [[
                    "headline": "TON update", "summary": "Protocol news",
                    "url": "https://example.com/ton", "publishedAt": "2026-07-30T00:00:00.000Z"
                ]]
            ],
            ["kind": "clientUnsupported", "schemaVersion": 1]
        ]

        let decoded = try fixtures.map(decodeSemanticContent)
        XCTAssertEqual(decoded.count, 7)
        guard case .notice = decoded[0],
              case .walletQuery = decoded[1],
              case .portfolio = decoded[2],
              case .market = decoded[3],
              case .assetSearch = decoded[4],
              case .webDigest = decoded[5],
              case .clientUnsupported = decoded[6] else {
            return XCTFail("Expected the six wire variants and local unsupported placeholder")
        }
    }

    func testDecodesTypedFearGreedSmaRegimeAndToleratesUnknownOptionalFields() throws {
        var fearGreedRegime = fearGreedRegimeObject()
        fearGreedRegime["futureDisplayHint"] = "ignored"
        var source = try XCTUnwrap(fearGreedRegime["source"] as? [String: Any])
        source["futureSourceDetail"] = "ignored"
        fearGreedRegime["source"] = source

        let content = try decodeSemanticContent(marketAnalysisObject(fearGreedRegime: fearGreedRegime))
        guard case .market(.analysis(let outcome, let evidence, let analysis, let optionalRegime)) = content else {
            return XCTFail("Expected market analysis with Fear & Greed regime")
        }
        let regime = try XCTUnwrap(optionalRegime)

        XCTAssertEqual(outcome, .complete)
        XCTAssertEqual(evidence, .object(["schemaVersion": .number(6)]))
        XCTAssertEqual(analysis?.summary, "Classic market analysis remains visible.")
        XCTAssertEqual(regime.schemaVersion, 1)
        XCTAssertEqual(regime.policyVersion, .fearGreedSmaRegimeV1)
        XCTAssertEqual(regime.basis, .closedUtcDaily)
        XCTAssertEqual(regime.asOfDate, "2026-08-09")
        XCTAssertEqual(regime.latestValue, 62)
        XCTAssertEqual(regime.sma30, "54.25000000")
        XCTAssertEqual(regime.sma365, "48.12000000")
        XCTAssertEqual(regime.regime, .riskOn)
        XCTAssertEqual(regime.seriesDigest, String(repeating: "a", count: 64))
        XCTAssertEqual(regime.source.provider, "alternative_me")
        XCTAssertEqual(regime.source.endpoint, "alternative.fng")
        XCTAssertTrue(regime.source.attributionRequired)
        XCTAssertEqual(regime.source.attributionLabel, "Alternative.me")
        XCTAssertEqual(
            regime.source.attributionUrl,
            "https://alternative.me/crypto/fear-and-greed-index/"
        )
    }

    func testMalformedFearGreedSmaRegimeFailsSoftWithoutDroppingMarketAnalysis() throws {
        let invalidFields: [(String, Any)] = [
            ("latestValue", 101),
            ("sma30", "54.25"),
            ("sma365", "100.00000001"),
            ("asOfDate", "2026/02/28"),
            ("asOfDate", "2026-02-31"),
            ("seriesDigest", String(repeating: "A", count: 64)),
            ("source", [
                "provider": "alternative_me",
                "endpoint": "unexpected.fng",
                "attributionRequired": true,
                "attributionLabel": "Alternative.me",
                "attributionUrl": "https://alternative.me/crypto/fear-and-greed-index/"
            ])
        ]

        for (field, invalidValue) in invalidFields {
            var fearGreedRegime = fearGreedRegimeObject()
            fearGreedRegime[field] = invalidValue
            let content = try decodeSemanticContent(
                marketAnalysisObject(fearGreedRegime: fearGreedRegime)
            )
            guard case .market(.analysis(let outcome, let evidence, let analysis, let regime)) = content else {
                return XCTFail("Expected malformed optional regime to preserve market analysis")
            }

            XCTAssertEqual(outcome, .complete, "Unexpected outcome for malformed \(field)")
            XCTAssertEqual(
                evidence,
                .object(["schemaVersion": .number(6)]),
                "Evidence was lost for malformed \(field)"
            )
            XCTAssertEqual(
                analysis?.summary,
                "Classic market analysis remains visible.",
                "Analysis was lost for malformed \(field)"
            )
            XCTAssertNil(regime, "Malformed \(field) should drop only the optional regime")
        }
    }

    @MainActor
    func testDecodesAndRendersQuarantineWalletContentWithoutUnsafeAssetText() throws {
        let content = try decodeSemanticContent([
            "kind": "walletQuery",
            "schemaVersion": 1,
            "queryKind": "transactions",
            "outcome": "partial",
            "hasMore": false,
            "omittedRows": ["count": 7, "accuracy": "lower_bound"],
            "policySummary": [
                "presentation": "quarantine",
                "suspicious": ["count": 1, "accuracy": "lower_bound"]
            ],
            "rows": [[
                "chain": "ton",
                "transactionType": "transfer",
                "status": "completed",
                "timestamp": "2026-07-30T00:00:00.000Z",
                "assetLabelStatus": "redacted_unsafe",
                "quantity": "1"
            ]]
        ])
        guard case .walletQuery(.transactions(_, _, let omittedRows, let policySummary, let rows)) = content else {
            return XCTFail("Expected quarantine wallet transactions")
        }
        XCTAssertEqual(omittedRows?.count, 7)
        XCTAssertEqual(omittedRows?.accuracy, .lowerBound)
        XCTAssertEqual(policySummary?.presentation, .quarantine)
        XCTAssertEqual(policySummary?.suspicious?.accuracy, .lowerBound)
        XCTAssertEqual(rows.first?.assetLabelStatus, .redactedUnsafe)
        XCTAssertNil(rows.first?.assetSymbol)

        let renderedText = [
            AgentV2WalletQueryPresentation.title(
                queryKind: "transactions",
                policySummary: policySummary
            ),
            AgentV2WalletQueryPresentation.warning(policySummary: policySummary),
            AgentV2WalletQueryPresentation.assetLabel(
                symbol: rows.first?.assetSymbol,
                isRedacted: rows.first?.assetLabelStatus == .redactedUnsafe
            ),
            AgentV2WalletQueryPresentation.omittedRowsText(omittedRows)
        ].compactMap { $0 } + AgentV2WalletQueryPresentation.counterTexts(policySummary)
        let renderedCopy = renderedText.joined(separator: " ")
        XCTAssertTrue(renderedCopy.contains(lang("$agent_semantic_spam_transactions")))
        XCTAssertTrue(renderedCopy.contains(lang("$agent_semantic_quarantine_warning")))
        XCTAssertTrue(renderedCopy.contains(lang("$agent_semantic_redacted_asset")))
        XCTAssertTrue(renderedCopy.contains(L10n.agentSemanticSuspiciousMinimum(amount: 1)))
        XCTAssertTrue(renderedCopy.contains(L10n.agentSemanticOmittedRowsMinimum(amount: 7)))
        XCTAssertFalse(renderedCopy.contains("GRAMEVENT.ORG"))
    }

    @MainActor
    func testDecodesAndPresentsWalletAccountOverviews() throws {
        let content = try decodeSemanticContent([
            "kind": "walletQuery",
            "schemaVersion": 1,
            "queryKind": "accounts",
            "outcome": "partial",
            "hasMore": false,
            "futureDisplay": true,
            "rows": [[
                "accountLabel": "Main | **literal**",
                "accessMode": "regular",
                "portfolioTotalStatus": "partial",
                "portfolioTotal": [
                    "value": "42.5",
                    "baseCurrency": "USD",
                    "unpricedCount": 1,
                    "futureRate": "ignored"
                ]
            ], [
                "accountLabel": "Watch",
                "accessMode": "view_only",
                "portfolioTotalStatus": "unavailable"
            ]]
        ])
        guard case .walletQuery(.accounts(let outcome, _, _, let rows)) = content else {
            return XCTFail("Expected wallet account overviews")
        }

        XCTAssertEqual(outcome, .partial)
        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(rows[0].portfolioTotal?.value, "42.5")
        XCTAssertEqual(rows[0].portfolioTotal?.baseCurrency, "USD")
        XCTAssertEqual(rows[0].portfolioTotal?.unpricedCount, 1)
        XCTAssertEqual(rows[1].portfolioTotalStatus, .unavailable)
        XCTAssertNil(rows[1].portfolioTotal)
        XCTAssertEqual(
            AgentV2WalletQueryPresentation.accountAccessMode(rows[0].accessMode),
            lang("$agent_semantic_access_regular")
        )
        XCTAssertEqual(
            AgentV2WalletQueryPresentation.accountAccessMode(rows[1].accessMode),
            lang("$agent_semantic_access_view_only")
        )
        let notices = AgentV2WalletQueryPresentation.accountNotices(outcome: outcome, rows: rows)
        XCTAssertTrue(notices.contains(L10n.agentSemanticWalletsUnpriced(amount: 1)))
        XCTAssertTrue(notices.contains(lang("$agent_semantic_wallets_unavailable")))
    }

    @MainActor
    func testPartialWalletAccountsDoNotInventStaleOrGenericPartialNotices() throws {
        let content = try decodeSemanticContent([
            "kind": "walletQuery",
            "schemaVersion": 1,
            "queryKind": "accounts",
            "outcome": "partial",
            "hasMore": false,
            "rows": [[
                "accountLabel": "Main",
                "accessMode": "regular",
                "portfolioTotalStatus": "complete",
                "portfolioTotal": [
                    "value": "42.5",
                    "baseCurrency": "USD",
                    "unpricedCount": 0
                ]
            ]]
        ])
        guard case .walletQuery(.accounts(let outcome, _, _, let rows)) = content else {
            return XCTFail("Expected wallet account overviews")
        }

        XCTAssertEqual(AgentV2WalletQueryPresentation.accountNotices(outcome: outcome, rows: rows), [])
    }

    @MainActor
    func testAssetSearchPresentationUsesExplicitOutcomeInsteadOfMissingRows() throws {
        let cases: [(String, String?, String?)] = [
            ("complete_absent", "not_found", lang("$agent_semantic_no_results")),
            ("incomplete_unconfirmed", nil, lang("$agent_notice_wallet_unavailable")),
            ("scope_denied", "consent_required", lang("$agent_notice_consent_required")),
            ("scope_denied", "account_scope_not_allowed", lang("$agent_notice_tool_unavailable")),
            ("complete_matches", nil, nil)
        ]
        for (outcome, reason, expectedStatus) in cases {
            var object: [String: Any] = [
                "kind": "assetSearch",
                "schemaVersion": 1,
                "outcome": outcome
            ]
            if let reason { object["reason"] = reason }
            guard case .assetSearch(let content) = try decodeSemanticContent(object) else {
                return XCTFail("Expected asset search content")
            }
            let status = AgentV2AssetSearchPresentation.status(content)
            if let expectedStatus {
                XCTAssertEqual(status, expectedStatus, "Missing status for \(outcome)")
            } else {
                XCTAssertNil(status)
            }
        }
    }

    @MainActor
    func testDecodesAndPresentsHiddenAssetLabelsAsWarnedPlaintext() throws {
        let content = try decodeSemanticContent([
            "kind": "walletQuery",
            "schemaVersion": 1,
            "queryKind": "positions",
            "outcome": "complete",
            "hasMore": false,
            "policySummary": [
                "presentation": "hidden_review",
                "suspicious": ["count": 1, "accuracy": "exact"]
            ],
            "rows": [[
                "chain": "ton",
                "positionKind": "fungible",
                "assetName": "Gram Event",
                "assetSymbol": "GRAM AT GRAMEVENT.ORG",
                "assetLabelStatus": "untrusted_plaintext",
                "quantity": "100"
            ]]
        ])
        guard case .walletQuery(.positions(_, _, _, let policySummary, let rows)) = content else {
            return XCTFail("Expected hidden wallet positions")
        }
        XCTAssertEqual(policySummary?.presentation, .hiddenReview)
        XCTAssertEqual(rows.first?.assetLabelStatus, .untrustedPlaintext)

        let renderedText = [
            AgentV2WalletQueryPresentation.title(
                queryKind: "positions",
                policySummary: policySummary
            ),
            AgentV2WalletQueryPresentation.warning(policySummary: policySummary),
            AgentV2WalletQueryPresentation.assetLabel(
                name: rows.first?.assetName,
                symbol: rows.first?.assetSymbol,
                isRedacted: rows.first?.assetLabelStatus == .redactedUnsafe
            )
        ].compactMap { $0 } + AgentV2WalletQueryPresentation.counterTexts(policySummary)
        let renderedCopy = renderedText.joined(separator: " ")
        XCTAssertTrue(renderedCopy.contains(lang("$agent_semantic_hidden_assets")))
        XCTAssertTrue(renderedCopy.contains(lang("$agent_semantic_hidden_assets_warning")))
        XCTAssertTrue(renderedCopy.contains("Gram Event (GRAM AT GRAMEVENT.ORG)"))
        XCTAssertTrue(renderedCopy.contains(L10n.agentSemanticSuspiciousShown(amount: 1)))
        XCTAssertFalse(renderedCopy.contains(lang("$agent_semantic_redacted_asset")))
    }

    func testUnsupportedSemanticExtensionsUseLocalFallbackAndKnownMalformedContentFailsClosed() throws {
        guard case .clientUnsupported = try decodeSemanticContent([
            "kind": "clientUnsupported", "schemaVersion": 1
        ]) else {
            return XCTFail("Expected local unsupported semantic placeholder")
        }
        guard case .clientUnsupported = try decodeSemanticContent([
            "kind": "futureContent", "schemaVersion": 1
        ]) else {
            return XCTFail("Expected unknown semantic kind fallback")
        }
        guard case .clientUnsupported = try decodeSemanticContent([
            "kind": "notice", "schemaVersion": 2, "code": "empty_result"
        ]) else {
            return XCTFail("Expected unknown semantic version fallback")
        }
        guard case .clientUnsupported = try decodeSemanticContent([
            "kind": "notice", "schemaVersion": 1, "code": "future_notice"
        ]) else {
            return XCTFail("Expected unknown notice code fallback")
        }
        XCTAssertThrowsError(try decodeSemanticContent([
            "kind": "notice",
            "schemaVersion": 1,
            "code": "market_quote",
            "arguments": ["marketQuote": ["status": "resolved"]]
        ]))

        let removedEvent = try JSONSerialization.data(withJSONObject: [
            "type": "agentV2",
            "update": ["kind": "widgetAvailable", "widget": ["kind": "removedWidget"]]
        ])
        XCTAssertThrowsError(try JSONDecoder().decode(ApiAgentV2ClientUpdateEnvelope.self, from: removedEvent))
    }

    func testRunStartedPreservesCanonicalInputMessageId() throws {
        let envelope = try JSONDecoder().decode(
            ApiAgentV2ClientUpdateEnvelope.self,
            from: Data(#"{"type":"agentV2","update":{"kind":"runStarted","clientRunId":"client-1","runId":"run-1","threadId":"thread-1","threadRevision":2,"inputMessageId":"message-1"}}"#.utf8)
        )
        guard case .runStarted(_, _, let inputMessageId) = envelope.update else {
            return XCTFail("Expected run start")
        }

        XCTAssertEqual(inputMessageId, "message-1")
    }

    @MainActor
    func testCoordinatorSubmitsSelectedWalletScopeContinuation() async throws {
        let client = FakeAgentV2Client(defaultThreadId: "thread-1", shouldCompleteRun: true)
        let coordinator = AgentV2Coordinator(client: client)
        await coordinator.loadDefaultThread()
        let started = try JSONDecoder().decode(
            ApiAgentV2ClientUpdateEnvelope.self,
            from: Data(#"""
            {"type":"agentV2","update":{"kind":"messageStarted","clientRunId":"client-1","runId":"run-1","threadId":"thread-1","messageId":"message-1","contentKind":"semantic"}}
            """#.utf8)
        )
        let completed = try JSONDecoder().decode(
            ApiAgentV2ClientUpdateEnvelope.self,
            from: Data(#"""
            {"type":"agentV2","update":{"kind":"messageCompleted","clientRunId":"client-1","runId":"run-1","threadId":"thread-1","messageId":"message-1","finishReason":"complete","walletControls":{"scopeChoices":[{"choiceId":"choice_0000000000000000000000","label":"Savings"}],"expiresAt":"2099-07-31T12:15:00.000Z"}}}
            """#.utf8)
        )
        coordinator.walletCore(event: .agentV2(started.update))
        coordinator.walletCore(event: .agentV2(completed.update))

        coordinator.selectWalletScopeChoice(
            messageId: "message-1",
            choiceId: "choice_0000000000000000000000"
        )
        try await Task.sleep(for: .milliseconds(50))

        let command = try XCTUnwrap(client.startedCommands.first)
        XCTAssertEqual(command.input, .append(text: "Savings"))
        XCTAssertEqual(command.walletScopeSelectionOf?.sourceAssistantMessageId, "message-1")
        XCTAssertEqual(command.walletScopeSelectionOf?.choiceId, "choice_0000000000000000000000")
    }

    func testDecodesHideSpamResolution() throws {
        let resolved = try JSONDecoder().decode(
            ApiAgentV2ResolvedAction.self,
            from: Data(#"{"kind":"hideSpamAssets","slugs":["spam-token"]}"#.utf8)
        )
        XCTAssertEqual(resolved.kind, .hideSpamAssets)
        XCTAssertEqual(resolved.slugs, ["spam-token"])
    }

    func testRejectsUnknownWalletPresentationKinds() {
        XCTAssertThrowsError(try JSONDecoder().decode(
            ApiAgentV2ResolvedAction.self,
            from: Data(#"{"kind":"openArbitraryRoute"}"#.utf8)
        ))
        XCTAssertThrowsError(try JSONDecoder().decode(
            ApiAgentV2ActionPresentation.self,
            from: Data(#"{"kind":"futurePresentation"}"#.utf8)
        ))
    }

    func testActionPresentationRejectsIncompleteSendState() {
        XCTAssertThrowsError(try JSONDecoder().decode(
            ApiAgentV2ActionPresentation.self,
            from: Data(#"{"kind":"send","status":"active"}"#.utf8)
        ))
    }

    func testSendReviewUsesJSONSafeAtomicString() throws {
        let data = Data(#"""
        {
          "kind":"reviewSend",
          "draftId":"draft-1",
          "chain":"ton",
          "review":{
            "tokenSlug":"toncoin",
            "amountAtomic":"1250000000",
            "toAddress":"UQ-safe-fixture",
            "comment":"hello"
          }
        }
        """#.utf8)

        let action = try JSONDecoder().decode(ApiAgentV2ResolvedAction.self, from: data)
        XCTAssertEqual(action.review?.amountAtomic, "1250000000")
        XCTAssertNoThrow(try JSONEncoder().encode(action))
    }

    @MainActor
    func testBuildsBoundedPortfolioChart() throws {
        let data = Data(#"""
        {
          "kind":"portfolio",
          "schemaVersion":1,
          "view":"analysis",
          "outcome":"complete",
          "payload":{
            "id":"portfolio-1",
            "status":"complete",
            "accountScope":"current",
            "baseCurrency":"USD",
            "range":"1d",
            "generatedAt":"2026-07-22T00:00:00.000Z",
            "totalValue":{"value":"110","currency":"USD","asOf":"2026-07-22T00:00:00.000Z"},
            "performance":{
              "chart":{
                "kind":"stacked_net_worth",
                "range":"1d",
                "baseCurrency":"USD",
                "timestamps":[1752969600,1752973200],
                "series":[{
                  "asset":{"slug":"toncoin","chain":"ton","symbol":"TON"},
                  "values":["100","110"]
                }]
              }
            }
          }
        }
        """#.utf8)

        let content = try JSONDecoder().decode(ApiAgentV2SemanticContent.self, from: data)
        guard case .portfolio(.analysis(_, let payload, _)) = content else {
            return XCTFail("Expected portfolio analysis")
        }
        let json = try XCTUnwrap(AgentV2PortfolioChartAdapter.makeJSON(payload))
        XCTAssertTrue(json.contains("1752969600000"))
        XCTAssertTrue(json.contains("\"stacked\":true"))
    }

    private func decodeRunActivityUpdate(threadId: String) throws -> ApiAgentV2ClientUpdate {
        let runId = "run-\(threadId)"
        let data = try JSONSerialization.data(withJSONObject: [
            "type": "agentV2",
            "update": [
                "kind": "runActivityChanged",
                "clientRunId": "client-\(threadId)",
                "runId": runId,
                "threadId": threadId,
                "event": [
                    "type": "run_activity",
                    "protocolVersion": 2,
                    "runId": runId,
                    "sequence": 3,
                    "code": "web.reading_sources",
                    "status": "completed",
                    "detail": ["kind": "source_count", "count": 4]
                ]
            ]
        ])
        return try JSONDecoder().decode(ApiAgentV2ClientUpdateEnvelope.self, from: data).update
    }

    private func decodeSemanticContent(_ object: [String: Any]) throws -> ApiAgentV2SemanticContent {
        try JSONDecoder().decode(
            ApiAgentV2SemanticContent.self,
            from: JSONSerialization.data(withJSONObject: object)
        )
    }

    private func fearGreedRegimeObject(regime: String = "risk_on") -> [String: Any] {
        [
            "schemaVersion": 1,
            "policyVersion": "fear-greed-sma-regime-v1",
            "basis": "closed_utc_daily",
            "asOfDate": "2026-08-09",
            "latestValue": 62,
            "sma30": "54.25000000",
            "sma365": "48.12000000",
            "regime": regime,
            "seriesDigest": String(repeating: "a", count: 64),
            "source": [
                "provider": "alternative_me",
                "endpoint": "alternative.fng",
                "attributionRequired": true,
                "attributionLabel": "Alternative.me",
                "attributionUrl": "https://alternative.me/crypto/fear-and-greed-index/"
            ]
        ]
    }

    private func marketAnalysisObject(fearGreedRegime: [String: Any]) -> [String: Any] {
        [
            "kind": "market",
            "schemaVersion": 1,
            "view": "analysis",
            "outcome": "complete",
            "evidence": ["schemaVersion": 6],
            "analysis": ["summary": "Classic market analysis remains visible."],
            "fearGreedRegime": fearGreedRegime
        ]
    }

    private func decodePersistedMessage(content: [String: Any]) throws -> ApiAgentV2PersistedMessage {
        try JSONDecoder().decode(
            ApiAgentV2PersistedMessage.self,
            from: JSONSerialization.data(withJSONObject: persistedMessageObject(content: content))
        )
    }

    private func persistedMessageObject(
        content: [String: Any],
        messageId: String = "message-1",
        threadId: String = "thread-1"
    ) -> [String: Any] {
        [
            "id": messageId,
            "threadId": threadId,
            "role": "assistant",
            "status": "complete",
            "content": content,
            "createdAt": "2026-07-31T12:00:00.000Z"
        ]
    }
}
