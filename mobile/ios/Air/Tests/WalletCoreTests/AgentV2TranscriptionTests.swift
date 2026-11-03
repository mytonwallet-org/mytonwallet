import Foundation
import Testing
@testable import WalletCore

@Suite("Agent V2 transcription")
struct AgentV2TranscriptionTests {
    @Test
    func transcriptionErrorsDecodeThroughTheSDKOperationEnvelope() throws {
        let codes: [(String, ApiAgentV2ErrorCode)] = [
            ("recording_too_large", .recordingTooLarge),
            ("audio_unreadable", .audioUnreadable),
            ("transcription_unavailable", .transcriptionUnavailable),
        ]
        for (wireCode, expectedCode) in codes {
            let data = Data("""
            {"ok":false,"error":{"code":"\(wireCode)","retryable":false}}
            """.utf8)
            let result = try JSONDecoder().decode(
                ApiAgentV2MutationResult<ApiAgentV2TranscriptionResponse>.self,
                from: data
            )
            #expect(!result.ok)
            #expect(result.error?.code == expectedCode)
        }
    }

    @Test
    func transcriptionResponseDecodesBothWireOutcomes() throws {
        let transcribed = try JSONDecoder().decode(
            ApiAgentV2MutationResult<ApiAgentV2TranscriptionResponse>.self,
            from: Data("""
            {"ok":true,"value":{"protocolVersion":3,"outcome":"transcribed","text":"Send ten TON"}}
            """.utf8)
        )
        #expect(transcribed.value?.protocolVersion == 3)
        #expect(transcribed.value?.outcome == .transcribed)
        #expect(transcribed.value?.text == "Send ten TON")

        let noSpeech = try JSONDecoder().decode(
            ApiAgentV2MutationResult<ApiAgentV2TranscriptionResponse>.self,
            from: Data("""
            {"ok":true,"value":{"protocolVersion":3,"outcome":"no_speech"}}
            """.utf8)
        )
        #expect(noSpeech.value?.outcome == .noSpeech)
        #expect(noSpeech.value?.text == nil)
    }
}
