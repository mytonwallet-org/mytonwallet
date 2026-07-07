import Foundation
import WalletContext

public enum SdkError: Error, Sendable {
    case message(ApiAnyDisplayError)
    case apiReturnedError(error: String, displayError: ApiAnyDisplayError?, data: String?)
    case sdkNotReady(methodName: String, reason: String)
    case javaScriptException(SdkJavaScriptException)
    case decoding(SdkDecodingError)
    case invalidResponse(methodName: String, reason: String, data: String?)
    case unexpected(SdkUnexpectedError)

    public static func apiReturnedError(error: String, context payload: Any?) -> SdkError {
        .apiReturnedError(error: error, displayError: ApiAnyDisplayError.from(error), data: context(from: payload))
    }

    public static func apiReturnedError(error: String, data: String?) -> SdkError {
        .apiReturnedError(error: error, displayError: ApiAnyDisplayError.from(error), data: data)
    }

    public static func unexpected(message: String, context payload: Any? = nil) -> SdkError {
        return .unexpected(SdkUnexpectedError(
            message: message,
            context: context(from: payload)
        ))
    }

    static func returnedError(from dataString: String?) -> SdkError? {
        guard let dataString,
              let errorValue = try? JSONDecoder().decode(SdkReturnedError.self, fromString: dataString)
        else {
            return nil
        }
        return .apiReturnedError(error: errorValue.error, data: dataString)
    }

    static func tryToParseStringAsErrorAndThrow(dataString: String?) throws {
        if let error = returnedError(from: dataString) {
            throw error
        }
    }

    static func context(from payload: Any?) -> String? {
        guard let payload else { return nil }
        if let string = payload as? String {
            return string
        }
        if JSONSerialization.isValidJSONObject(payload),
           let data = try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]),
           let string = String(data: data, encoding: .utf8) {
            return string
        }
        return String(describing: payload)
    }

    public var backendMessage: String? {
        switch self {
        case .message(let message):
            return message.rawValue
        case .apiReturnedError(let error, _, _):
            return error
        case .javaScriptException(let exception):
            return exception.message
        case .sdkNotReady(_, let reason):
            return reason
        case .decoding(let error):
            return error.underlyingDescription
        case .invalidResponse(_, let reason, _):
            return reason
        case .unexpected(let error):
            return error.message
        }
    }
}

public struct SdkJavaScriptException: Error, Sendable {
    public let methodName: String
    public let name: String?
    public let message: String
    public let stack: String?
    public let data: String?

    public init(methodName: String, exceptionMessage: String) {
        self.methodName = methodName
        self.data = exceptionMessage

        if let payload = try? JSONDecoder().decode(SdkJavaScriptExceptionPayload.self, fromString: exceptionMessage) {
            self.name = payload.name
            self.message = payload.message
            self.stack = payload.stack
        } else if let message = try? JSONDecoder().decode(String.self, fromString: exceptionMessage) {
            self.name = nil
            self.message = message
            self.stack = nil
        } else {
            self.name = nil
            self.message = exceptionMessage
            self.stack = nil
        }
    }

    public var knownDisplayError: ApiAnyDisplayError? {
        ApiAnyDisplayError.from(message)
    }
}

private struct SdkJavaScriptExceptionPayload: Decodable {
    var message: String
    var name: String?
    var stack: String?
}

public struct SdkDecodingError: Error, Sendable {
    public let methodName: String
    public let responseType: String
    public let underlyingDescription: String
    public let data: String?

    public init(methodName: String, responseType: String, underlyingError: Error, data: String?) {
        self.methodName = methodName
        self.responseType = responseType
        self.underlyingDescription = String(describing: underlyingError)
        self.data = data
    }
}

public struct SdkUnexpectedError: Error, Sendable {
    public let message: String
    public let context: String?
}

public struct SdkReturnedError: Decodable, Sendable {
    public var error: String
}

extension SdkError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .message(let message):
            return message.toLocalized
        case .apiReturnedError(let error, let displayError, _):
            return displayError?.toLocalized ?? ApiAnyDisplayError.localizedFallback(forRawValue: error) ?? error
        case .sdkNotReady:
            return lang("SDK is not ready. Please try again.")
        case .javaScriptException(let exception):
            return exception.knownDisplayError?.toLocalized
                ?? ApiAnyDisplayError.localizedFallback(forRawValue: exception.message)
                ?? exception.message
        case .decoding:
            return lang("Unexpected")
        case .invalidResponse:
            return lang("Unexpected")
        case .unexpected:
            return lang("Unexpected")
        }
    }
}
