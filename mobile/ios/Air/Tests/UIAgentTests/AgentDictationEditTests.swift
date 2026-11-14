import ContextMenuKit
import XCTest
import UIKit
@testable import UIAgent
import WalletContext
import WalletCore
import WalletResources

@MainActor
final class AgentDictationEditTests: XCTestCase {
    func testTranscriptDoesNotOpenPreviouslyClosedKeyboard() async throws {
        _ = WalletResourcesBundle.bundle.load()
        let backend = DictationEditTestBackend()
        let model = AgentModel(backend: backend)
        let scheduler = AgentDictationTestScheduler()
        let recorder = AgentDictationTestRecorder()
        var isRecordingReady = false
        let transcript = "Dictated without opening the keyboard"
        let dictation = AgentDictationController(
            scheduler: scheduler,
            requestPermission: { true },
            makeRecorder: { recorder },
            transcribe: { _ in .init(outcome: .transcribed, text: transcript) },
            haptic: { isRecordingReady = true },
            observeLifecycle: false
        )
        defer { dictation.cancel() }
        let controller = AgentVC(model: model, dictationController: dictation)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 375, height: 812))
        window.rootViewController = UINavigationController(rootViewController: controller)
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        window.layoutIfNeeded()
        let composer = try XCTUnwrap(descendants(of: controller.view).compactMap { $0 as? AgentComposerView }.first)
        XCTAssertFalse(composer.isTextInputActive)

        dictation.startHandsFree()
        for _ in 0..<100 where !isRecordingReady { await Task.yield() }
        XCTAssertTrue(isRecordingReady)
        XCTAssertFalse(composer.isTextInputActive)
        scheduler.advance(by: 0.8)
        dictation.finish()
        // The transcript comes in word by word
        for _ in 0..<300 where composer.draftText != transcript { try await Task.sleep(for: .milliseconds(10)) }

        XCTAssertEqual(composer.draftText, transcript)
        XCTAssertFalse(composer.isTextInputActive)
        XCTAssertTrue(backend.sentTexts.isEmpty)
    }

    func testEditingMessageDiscardsPendingTranscriptAndSendsEditedDraft() async throws {
        _ = WalletResourcesBundle.bundle.load()
        let backend = DictationEditTestBackend()
        let model = AgentModel(backend: backend)
        let message = AgentMessage(role: .user, text: "Earlier question", isStreaming: false)
        backend.context?.replaceTimeline(with: [.message(message)], animated: false)
        let recorder = AgentDictationTestRecorder()
        let scheduler = AgentDictationTestScheduler()
        var recordingStarts = 0
        var transcription: CheckedContinuation<ApiAgentV2TranscriptionResponse, Error>?
        let dictation = AgentDictationController(
            scheduler: scheduler,
            requestPermission: { true },
            makeRecorder: {
                recordingStarts += 1
                return recorder
            },
            transcribe: { _ in
                try await withCheckedThrowingContinuation { transcription = $0 }
            },
            haptic: {},
            observeLifecycle: false
        )
        let controller = AgentVC(model: model, dictationController: dictation)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 402, height: 874))
        window.rootViewController = UINavigationController(rootViewController: controller)
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        let collectionView = try XCTUnwrap(descendants(of: controller.view).compactMap { $0 as? UICollectionView }.first)
        let composer = try XCTUnwrap(descendants(of: controller.view).compactMap { $0 as? AgentComposerView }.first)
        for _ in 0..<100 where collectionView.visibleCells.isEmpty {
            controller.view.layoutIfNeeded()
            await Task.yield()
        }
        let cell = try XCTUnwrap(collectionView.visibleCells.compactMap { $0 as? AgentMessageCell }.first)
        let configuration = try XCTUnwrap(cell.contextMenuConfigurationProvider?())
        let editAction = try XCTUnwrap(configuration.rootPage.items.compactMap { item -> ContextMenuAction? in
            guard case .action(let action) = item, action.title == lang("Edit") else { return nil }
            return action
        }.first)

        dictation.startHandsFree()
        for _ in 0..<100 where recordingStarts == 0 { await Task.yield() }
        XCTAssertEqual(recordingStarts, 1)
        scheduler.advance(by: 0.8)
        dictation.finish()
        for _ in 0..<100 where transcription == nil { await Task.yield() }
        let pendingTranscription = try XCTUnwrap(transcription)
        XCTAssertEqual(dictation.state.phase, .recognizing)

        editAction.handler?()
        XCTAssertEqual(dictation.state.phase, .idle)
        XCTAssertEqual(composer.draftText, message.text)
        pendingTranscription.resume(returning: .init(outcome: .transcribed, text: "Late dictation"))
        for _ in 0..<100 { await Task.yield() }

        XCTAssertEqual(composer.draftText, message.text)
        composer.onSend?()
        XCTAssertEqual(backend.sentTexts, [message.text])
        XCTAssertEqual(backend.editedMessageIDs, [message.id])
        XCTAssertEqual(backend.context?.message(for: message.id)?.text, message.text)
    }

    func testDictatingEmptyEditedDraftKeepsOriginalMessageID() async throws {
        _ = WalletResourcesBundle.bundle.load()
        let backend = DictationEditTestBackend()
        let model = AgentModel(backend: backend)
        let message = AgentMessage(role: .user, text: "Earlier question", isStreaming: false)
        backend.context?.replaceTimeline(with: [.message(message)], animated: false)
        let recorder = AgentDictationTestRecorder()
        let scheduler = AgentDictationTestScheduler()
        var recordingStarts = 0
        let transcript = "Dictated replacement"
        let dictation = AgentDictationController(
            scheduler: scheduler,
            requestPermission: { true },
            makeRecorder: {
                recordingStarts += 1
                return recorder
            },
            transcribe: { _ in .init(outcome: .transcribed, text: transcript) },
            haptic: {},
            observeLifecycle: false
        )
        let controller = AgentVC(model: model, dictationController: dictation)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 402, height: 874))
        window.rootViewController = UINavigationController(rootViewController: controller)
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        let collectionView = try XCTUnwrap(descendants(of: controller.view).compactMap { $0 as? UICollectionView }.first)
        let composer = try XCTUnwrap(descendants(of: controller.view).compactMap { $0 as? AgentComposerView }.first)
        let textView = try XCTUnwrap(descendants(of: composer).compactMap { $0 as? UITextView }.first)
        for _ in 0..<100 where collectionView.visibleCells.isEmpty {
            controller.view.layoutIfNeeded()
            await Task.yield()
        }
        let cell = try XCTUnwrap(collectionView.visibleCells.compactMap { $0 as? AgentMessageCell }.first)
        let configuration = try XCTUnwrap(cell.contextMenuConfigurationProvider?())
        let editAction = try XCTUnwrap(configuration.rootPage.items.compactMap { item -> ContextMenuAction? in
            guard case .action(let action) = item, action.title == lang("Edit") else { return nil }
            return action
        }.first)

        editAction.handler?()
        XCTAssertEqual(composer.draftText, message.text)
        XCTAssertTrue(textView.isFirstResponder)
        textView.selectedRange = NSRange(location: 0, length: message.text.utf16.count)
        textView.deleteBackward()
        XCTAssertEqual(composer.draftText, "")
        XCTAssertTrue(textView.isFirstResponder)

        dictation.touchBegan()
        scheduler.advance(by: 0.22)
        for _ in 0..<100 where recordingStarts == 0 { await Task.yield() }
        XCTAssertEqual(recordingStarts, 1)
        XCTAssertEqual(dictation.state.phase, .holding)
        XCTAssertTrue(textView.isFirstResponder)
        scheduler.advance(by: 0.8)
        dictation.touchEnded()
        // Released, a held recording's transcript goes at once, here as the edit of the message
        for _ in 0..<300 where backend.sentTexts.isEmpty { try await Task.sleep(for: .milliseconds(10)) }

        XCTAssertEqual(composer.draftText ?? "", "")
        XCTAssertFalse(textView.isFirstResponder, "The keyboard goes with the transcript, as with a question typed")
        XCTAssertEqual(backend.sentTexts, [transcript])
        XCTAssertEqual(backend.editedMessageIDs, [message.id])
        XCTAssertEqual(backend.context?.message(for: message.id)?.text, transcript)
        let userMessageIDs = model.itemIDs.compactMap { backend.context?.message(for: $0) }
            .filter { $0.role == .user }.map(\.id)
        XCTAssertEqual(userMessageIDs, [message.id])
    }

    func testOpeningMessageMenuCancelsRecordingWithoutTranscription() async throws {
        _ = WalletResourcesBundle.bundle.load()
        let backend = DictationEditTestBackend()
        let model = AgentModel(backend: backend)
        let message = AgentMessage(role: .user, text: "Earlier question", isStreaming: false)
        backend.context?.replaceTimeline(with: [.message(message)], animated: false)
        let recorder = AgentDictationTestRecorder()
        let scheduler = AgentDictationTestScheduler()
        var isRecordingReady = false
        var requestCount = 0
        let dictation = AgentDictationController(
            scheduler: scheduler,
            requestPermission: { true },
            makeRecorder: { recorder },
            transcribe: { _ in
                requestCount += 1
                return .init(outcome: .transcribed, text: "Unexpected transcript")
            },
            haptic: { isRecordingReady = true },
            observeLifecycle: false
        )
        defer { dictation.cancel() }
        let controller = AgentVC(model: model, dictationController: dictation)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 402, height: 874))
        window.rootViewController = UINavigationController(rootViewController: controller)
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        let collectionView = try XCTUnwrap(descendants(of: controller.view).compactMap { $0 as? UICollectionView }.first)
        for _ in 0..<100 where collectionView.visibleCells.isEmpty {
            controller.view.layoutIfNeeded()
            await Task.yield()
        }
        let cell = try XCTUnwrap(collectionView.visibleCells.compactMap { $0 as? AgentMessageCell }.first)

        dictation.startHandsFree()
        for _ in 0..<100 where !isRecordingReady { await Task.yield() }
        XCTAssertTrue(isRecordingReady)
        scheduler.advance(by: 0.8)
        XCTAssertNotNil(cell.contextMenuConfigurationProvider?())

        XCTAssertEqual(dictation.state.phase, .idle)
        XCTAssertEqual(recorder.cancelCount, 1)
        scheduler.advance(by: 60)
        for _ in 0..<100 { await Task.yield() }
        XCTAssertEqual(requestCount, 0)
    }

    func testEmptyEditedDraftLeavesEditModeAfterUnfocusedDictationWithoutTranscript() async throws {
        _ = WalletResourcesBundle.bundle.load()
        for ending in ["cancel", "tooShort", "noSpeech", "recorderError", "recognitionError"] {
            let backend = DictationEditTestBackend()
            let model = AgentModel(backend: backend)
            let message = AgentMessage(role: .user, text: "Earlier question", isStreaming: false)
            backend.context?.replaceTimeline(with: [.message(message)], animated: false)
            let recorder = AgentDictationTestRecorder()
            if ending == "noSpeech" { recorder.averagePowerValue = -80 }
            let scheduler = AgentDictationTestScheduler()
            var isRecordingReady = false
            let dictation = AgentDictationController(
                scheduler: scheduler,
                requestPermission: { true },
                makeRecorder: { recorder },
                transcribe: { _ in throw NSError(domain: "DictationEditTests", code: 1) },
                haptic: { isRecordingReady = true },
                observeLifecycle: false
            )
            defer { dictation.cancel() }
            let controller = AgentVC(model: model, dictationController: dictation)
            let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 402, height: 874))
            window.rootViewController = UINavigationController(rootViewController: controller)
            window.makeKeyAndVisible()
            defer { window.isHidden = true }
            let collectionView = try XCTUnwrap(descendants(of: controller.view).compactMap { $0 as? UICollectionView }.first)
            let composer = try XCTUnwrap(descendants(of: controller.view).compactMap { $0 as? AgentComposerView }.first)
            let textView = try XCTUnwrap(descendants(of: composer).compactMap { $0 as? UITextView }.first)
            for _ in 0..<100 where collectionView.visibleCells.isEmpty {
                controller.view.layoutIfNeeded()
                await Task.yield()
            }
            let cell = try XCTUnwrap(collectionView.visibleCells.compactMap { $0 as? AgentMessageCell }.first)
            let configuration = try XCTUnwrap(cell.contextMenuConfigurationProvider?())
            let editAction = try XCTUnwrap(configuration.rootPage.items.compactMap { item -> ContextMenuAction? in
                guard case .action(let action) = item, action.title == lang("Edit") else { return nil }
                return action
            }.first)
            editAction.handler?()
            XCTAssertTrue(textView.isFirstResponder, ending)
            textView.selectedRange = NSRange(location: 0, length: message.text.utf16.count)
            textView.deleteBackward()
            XCTAssertEqual(composer.draftText, "", ending)

            dictation.touchBegan()
            scheduler.advance(by: 0.22)
            for _ in 0..<100 where !isRecordingReady { await Task.yield() }
            XCTAssertTrue(isRecordingReady, ending)
            XCTAssertEqual(dictation.state.phase, .holding, ending)
            textView.resignFirstResponder()
            XCTAssertFalse(textView.isFirstResponder, ending)
            scheduler.advance(by: ending == "tooShort" ? 0.1 : 0.8)
            switch ending {
            case "cancel": dictation.cancel()
            case "recorderError": recorder.onFailure?()
            default: dictation.touchEnded()
            }
            for _ in 0..<100 where dictation.state.phase != .idle && dictation.state.phase != .failed {
                await Task.yield()
            }
            // Only an explicit cancellation skips the failure indicator
            XCTAssertEqual(dictation.state.phase, ending == "cancel" ? .idle : .failed, ending)
            scheduler.advance(by: AgentDictationController.failureDuration)
            XCTAssertEqual(dictation.state.phase, .idle, ending)
            XCTAssertEqual(composer.draftText, "", ending)
            XCTAssertFalse(textView.isFirstResponder, ending)

            composer.setDraftText("A new question", focus: true)
            composer.onSend?()
            XCTAssertEqual(backend.sentTexts, ["A new question"], ending)
            XCTAssertEqual(backend.editedMessageIDs, [nil], ending)
            XCTAssertEqual(backend.context?.message(for: message.id)?.text, message.text, ending)
            XCTAssertEqual(model.itemIDs.compactMap { backend.context?.message(for: $0) }
                .filter { $0.role == .user }.count, 2, ending)
        }
    }

    private func descendants(of view: UIView) -> [UIView] {
        view.subviews.flatMap { [$0] + descendants(of: $0) }
    }
}

@MainActor
private final class DictationEditTestBackend: AgentBackend {
    var context: AgentBackendContext?
    var sentTexts: [String] = []
    var editedMessageIDs: [AgentItemID?] = []

    func attach(to context: AgentBackendContext) { self.context = context }
    func detach() { context = nil }
    func loadHints(animated: Bool) {}
    func prepareForEditing(_ editContext: AgentBackendEditContext) {}
    func didSendUserMessage(
        _ text: String,
        userMessageID: AgentItemID,
        source: AgentBackendSendSource,
        editContext: AgentBackendEditContext?
    ) {
        sentTexts.append(text)
        editedMessageIDs.append(editContext?.messageID)
    }
    func clearConversation() {}
}
