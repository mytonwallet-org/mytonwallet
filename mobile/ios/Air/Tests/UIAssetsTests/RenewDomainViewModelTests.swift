import Dependencies
import GRDB
import XCTest
@testable import UIAssets
import WalletContext
@testable import WalletCore

@MainActor
final class RenewDomainViewModelTests: XCTestCase {
    func testViewOnlyWalletCannotStartRenewal() async throws {
        for domainCount in [0, 1, 2] {
            let model = try await makeModel(accountType: .view, domainCount: domainCount)
            defer { model.draft.pause() }
            if model.draft.request != nil {
                try await waitForDraft(model)
            }

            XCTAssertEqual(model.nfts.count, domainCount)
            XCTAssertNil(model.draft.request)
            XCTAssertNil(model.fee)
            XCTAssertFalse(model.isButtonLoading)
            XCTAssertFalse(model.canRenew)
            XCTAssertNil(model.makeConfirmationSnapshot())
            XCTAssertNil(model.subtitle)
            XCTAssertEqual(model.errorMessage, lang("Action is not possible on a view-only wallet."))
        }
    }

    func testSigningWalletsCanConfirmRenewalWithLoadedDomains() async throws {
        for accountType in [AccountType.mnemonic, .hardware] {
            for domainCount in [1, 2] {
                let model = try await makeModel(accountType: accountType, domainCount: domainCount)
                defer { model.draft.pause() }
                let request = try XCTUnwrap(model.draft.request)
                XCTAssertEqual(request.accountId, model.account.id)
                XCTAssertEqual(request.nftAddresses, model.nftsToRenew)

                try await waitForDraft(model)

                XCTAssertTrue(model.canRenew)
                XCTAssertFalse(model.isButtonLoading)
                XCTAssertNil(model.errorMessage)
                XCTAssertNotNil(model.subtitle)
                let snapshot = try XCTUnwrap(model.makeConfirmationSnapshot())
                XCTAssertEqual(snapshot.account, model.account)
                XCTAssertEqual(snapshot.nfts.map(\.address), model.nftsToRenew)
            }
        }
    }

    private func waitForDraft(_ model: RenewDomainViewModel) async throws {
        let deadline = ContinuousClock.now + .seconds(3)
        while model.draft.current == nil {
            guard ContinuousClock.now < deadline else {
                XCTFail("Timed out waiting for the renewal draft")
                return
            }
            try await Task.sleep(for: .milliseconds(5))
        }
    }

    private func makeModel(accountType: AccountType, domainCount: Int) async throws -> RenewDomainViewModel {
        let account = MAccount(
            id: "renewal\(UUID().uuidString)-mainnet", title: "Renewal", type: accountType,
            byChain: [.ton: .init(address: "owner")]
        )
        let nfts = try (0..<domainCount).map {
            try JSONDecoder().decode(ApiNft.self, from: Data(
                #"{"name":"example\#($0).ton","address":"domain\#($0)","isOnSale":false}"#.utf8
            ))
        }
        let database = try DatabaseQueue()
        try makeMigrator().migrate(database)
        try await database.write { database in
            try account.insert(database)
            try MAccountDomains(
                accountId: account.id,
                nftsByAddress: Dictionary(uniqueKeysWithValues: nfts.map { ($0.address, $0) }),
                orderedAddresses: nfts.map(\.address)
            ).insert(database)
        }
        let domains = DomainsStore()
        await domains.use(db: database)
        let draft = try JSONDecoder().decode(ApiDnsRenewalDraft.self, from: Data(#"{"realFee":"0"}"#.utf8))
        return withDependencies {
            $0.context = .live
            $0[DomainsStore.self] = domains
        } operation: {
            RenewDomainViewModel(
                accountSource: .constant(account), nftsToRenew: nfts.map(\.address),
                checkDraft: { accountId, requestedNfts in
                    XCTAssertEqual(accountId, account.id)
                    XCTAssertEqual(requestedNfts.map(\.address), nfts.map(\.address))
                    return draft
                }
            )
        }
    }
}
