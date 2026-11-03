import BleTransport
import Testing
import WalletContext
@testable import Ledger

@MainActor
struct LedgerAppConnectionTests {
    @Test(arguments: [
        BleStatusError.userRejected(status: "5501"),
        .appNotAvailableInDevice(status: "6807"),
        .unknown(status: "6700"),
    ])
    func terminalDeviceErrorsDoNotRepeatTheOpenRequest(_ error: BleStatusError) async {
        var attempts = 0
        do {
            try await withRetries(4) {
                attempts += 1
                throw error
            } handleError: {
                try LedgerFlowController.handleAppConnectionError($0)
            }
            Issue.record("Expected the device error")
        } catch let received as BleStatusError {
            #expect(received == error)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
        #expect(attempts == 1)
    }

    @Test
    func lockedDeviceCanSucceedAfterUnlocking() async throws {
        var attempts = 0
        try await withRetries(4) {
            attempts += 1
            if attempts == 1 {
                throw BleStatusError.deviceLocked(status: "5515")
            }
        } handleError: {
            try LedgerFlowController.handleAppConnectionError($0)
        }
        #expect(attempts == 2)
    }

    @Test
    func appInfoErrorsShowAnActionInsteadOfParserDiagnostics() {
        let error = BleStatusError.formatNotSupported(status: "9000")
        #expect(LedgerFlowController.appConnectionErrorMessage(error) == lang("Unlock it and open the TON App"))
        #expect(LedgerFlowController.appConnectionErrorMessage(BleStatusError.deviceLocked(status: "5515")) == lang("Unlock it and open the TON App"))
        #expect(LedgerFlowController.appConnectionErrorMessage(BleStatusError.appNotAvailableInDevice(status: "6807")) == lang("Install the TON App on your Ledger and try again."))
        #expect(LedgerFlowController.appConnectionErrorMessage(BleStatusError.userRejected(status: "5501")) == lang("Canceled by the user"))
        #expect(LedgerFlowController.appConnectionErrorMessage(BleTransportError.readError(description: "disconnected")) == lang("$ledger_connection_broken"))
    }
}
