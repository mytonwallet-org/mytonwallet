import Foundation
import Testing
import WalletContext
import WalletCore

struct PerpsNetworkErrorTests {
    @Test(arguments: [
        "Load failed", "Failed to fetch", "NetworkError when attempting to fetch resource.", "Request timed out.",
        "POST https://example.com/perps/estimate | attempts=1 | Load failed",
        "GET https://example.com/perps/assets | attempts=3 | Request timed out.",
    ])
    func showConnectionMessageForTransportFailures(message: String) throws {
        let expected = lang("Please make sure your internet connection is working and try again.")
        #expect(PerpsFormatting.error(try makeError(message: message, name: "TypeError")) == expected)
        #expect(PerpsFormatting.error(SdkError.apiReturnedError(error: message, data: nil)) == expected)
        #expect(PerpsFormatting.errorMessage(message) == expected)
    }

    @Test(arguments: ["NetworkError", "TimeoutError"])
    func recognizeTransportExceptionNames(name: String) throws {
        let error = try makeError(message: "The request could not complete", name: name)
        #expect(PerpsFormatting.error(error) == lang("Please make sure your internet connection is working and try again."))
    }

    @Test(arguments: [
        ("PerpsUnavailable", "Error", "PerpsUnavailable"),
        ("PerpsTradingUnavailable", "Error", "PerpsTradingUnavailable"),
        ("PerpsInsufficientUsdc", "Error", "PerpsInsufficientUsdc"),
        ("undefined is not an object", "TypeError", "PerpsUnavailable"),
        ("The operation was aborted", "AbortError", "PerpsUnavailable"),
        ("HTTP Error 503", "ApiServerError", "PerpsUnavailable"),
        ("POST https://example.com/perps/estimate | attempts=3 | status=503 | Load failed", "ApiServerError", "PerpsUnavailable"),
    ])
    func preserveServiceAndBusinessErrors(message: String, name: String, expectedKey: String) throws {
        #expect(PerpsFormatting.error(try makeError(message: message, name: name)) == lang(expectedKey))
        #expect(PerpsFormatting.errorMessage(message) == lang(expectedKey))
    }

    private func makeError(message: String, name: String) throws -> SdkError {
        let payload = try JSONSerialization.data(withJSONObject: ["message": message, "name": name])
        return .javaScriptException(.init(methodName: "perpsGetFundingRequirements",
                                         exceptionMessage: String(decoding: payload, as: UTF8.self)))
    }
}
