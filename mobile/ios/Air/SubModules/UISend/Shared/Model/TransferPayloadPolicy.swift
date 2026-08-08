import WalletCore

enum TransferPayloadFlow: Equatable, Sendable {
    case token
    case nft
}

enum TransferPayloadAvailability: Equatable, Sendable {
    case hidden
    case optional
    case required
    case readOnly

    var isVisible: Bool {
        self != .hidden
    }
}

enum TransferEncryptionPolicy: Equatable, Sendable {
    case unavailable
    case available
}

struct TransferPayloadPolicy: Equatable, Sendable {
    static let maxCommentBytes = 5_000

    let flow: TransferPayloadFlow
    let availability: TransferPayloadAvailability
    let encryption: TransferEncryptionPolicy
    let allowsBinaryPayload: Bool

    init(
        flow: TransferPayloadFlow,
        chain: ApiChain,
        isMemoRequired: Bool,
        isHardwareAccount: Bool,
        hasBinaryPayload: Bool
    ) {
        self.flow = flow
        self.allowsBinaryPayload =
            flow == .token && chain.isTransferPayloadSupported

        if allowsBinaryPayload && hasBinaryPayload {
            availability = .readOnly
        } else if isMemoRequired {
            availability = .required
        } else if chain.isTransferPayloadSupported {
            availability = .optional
        } else {
            availability = .hidden
        }

        encryption = flow == .token
            && !isMemoRequired
            && chain.isEncryptedCommentSupported
            && !isHardwareAccount
            ? .available
            : .unavailable
    }

    func makeTokenPayload(
        comment: String,
        binaryPayload: String?,
        isMessageEncrypted: Bool
    ) -> AnyTransferPayload? {
        guard flow == .token else { return nil }
        if allowsBinaryPayload, let binaryPayload = binaryPayload?.nilIfEmpty {
            return .base64(data: binaryPayload)
        }
        guard availability != .hidden,
              let comment = preparedComment(comment) else {
            return nil
        }
        return .comment(
            text: comment,
            shouldEncrypt: isMessageEncrypted && encryption == .available
        )
    }

    func preparedComment(_ comment: String) -> String? {
        guard availability != .hidden && availability != .readOnly else {
            return nil
        }
        return Self.sanitizeComment(comment).nilIfEmpty
    }

    static func sanitizeComment(_ comment: String) -> String {
        guard comment.utf8.count > maxCommentBytes else {
            return comment
        }

        var endIndex = comment.startIndex
        var byteCount = 0
        for character in comment {
            let characterByteCount = String(character).utf8.count
            guard byteCount + characterByteCount <= maxCommentBytes else {
                break
            }
            byteCount += characterByteCount
            endIndex = comment.index(endIndex, offsetBy: 1)
        }
        return String(comment[..<endIndex])
    }
}
