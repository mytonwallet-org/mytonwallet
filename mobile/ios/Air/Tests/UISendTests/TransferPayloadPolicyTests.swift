import Testing
@testable import UISend
import WalletCore

@Suite("Send Transfer Payload Policy")
struct TransferPayloadPolicyTests {
    @Test
    func `required memo stays visible on a chain without optional comments`() {
        let policy = TransferPayloadPolicy(
            flow: .token,
            chain: .ethereum,
            isMemoRequired: true,
            isHardwareAccount: false,
            hasBinaryPayload: false
        )

        #expect(policy.availability == .required)
        #expect(policy.encryption == .unavailable)
        #expect(
            policy.makeTokenPayload(
                comment: "required memo",
                binaryPayload: nil,
                isMessageEncrypted: true
            ) == .comment(
                text: "required memo",
                shouldEncrypt: false
            )
        )
    }

    @Test
    func `NFT comments never enable encryption`() {
        let policy = TransferPayloadPolicy(
            flow: .nft,
            chain: .ton,
            isMemoRequired: false,
            isHardwareAccount: false,
            hasBinaryPayload: false
        )

        #expect(policy.availability == .optional)
        #expect(policy.encryption == .unavailable)
        #expect(!policy.allowsBinaryPayload)
    }

    @Test
    func `hardware token send disables encrypted comments`() {
        let policy = TransferPayloadPolicy(
            flow: .token,
            chain: .ton,
            isMemoRequired: false,
            isHardwareAccount: true,
            hasBinaryPayload: false
        )

        #expect(policy.encryption == .unavailable)
    }

    @Test
    func `binary token payload is read only and takes precedence`() {
        let policy = TransferPayloadPolicy(
            flow: .token,
            chain: .ton,
            isMemoRequired: false,
            isHardwareAccount: false,
            hasBinaryPayload: true
        )

        let payload = policy.makeTokenPayload(
            comment: "ignored",
            binaryPayload: "base64",
            isMessageEncrypted: true
        )

        #expect(policy.availability == .readOnly)
        #expect(payload == .base64(data: "base64"))
    }

    @Test
    func `binary payload is omitted on an unsupported chain`() {
        let policy = TransferPayloadPolicy(
            flow: .token,
            chain: .ethereum,
            isMemoRequired: false,
            isHardwareAccount: false,
            hasBinaryPayload: true
        )

        let payload = policy.makeTokenPayload(
            comment: "ignored",
            binaryPayload: "base64",
            isMessageEncrypted: false
        )

        #expect(policy.availability == .hidden)
        #expect(!policy.allowsBinaryPayload)
        #expect(payload == nil)
    }

    @Test
    func `encryption flag is applied only when policy allows it`() {
        let available = TransferPayloadPolicy(
            flow: .token,
            chain: .ton,
            isMemoRequired: false,
            isHardwareAccount: false,
            hasBinaryPayload: false
        )
        let required = TransferPayloadPolicy(
            flow: .token,
            chain: .ton,
            isMemoRequired: true,
            isHardwareAccount: false,
            hasBinaryPayload: false
        )

        #expect(
            available.makeTokenPayload(
                comment: "memo",
                binaryPayload: nil,
                isMessageEncrypted: true
            ) == .comment(text: "memo", shouldEncrypt: true)
        )
        #expect(
            required.makeTokenPayload(
                comment: "memo",
                binaryPayload: nil,
                isMessageEncrypted: true
            ) == .comment(text: "memo", shouldEncrypt: false)
        )
    }

    @Test
    func `comment limit is measured in UTF-8 bytes without splitting characters`() {
        let limit = TransferPayloadPolicy.maxCommentBytes
        let emojiCount = limit / 4 + 1
        let comment = String(repeating: "🙂", count: emojiCount)

        let sanitized = TransferPayloadPolicy.sanitizeComment(comment)

        #expect(sanitized == String(repeating: "🙂", count: limit / 4))
        #expect(sanitized.utf8.count <= limit)
        #expect(sanitized.allSatisfy { $0 == "🙂" })
    }
}
