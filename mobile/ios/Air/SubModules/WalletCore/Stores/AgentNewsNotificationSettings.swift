import Foundation
import Perception
import UIKit
import WalletContext

@Perceptible
@MainActor
public final class AgentNewsNotificationSettings {
    public enum Mode: String, Codable, Sendable {
        case off, digest, news
    }

    public enum Outcome: Equatable, Sendable {
        case ok, permissionDenied, failed
    }

    public static let shared = AgentNewsNotificationSettings()
    private static let storageKey = "agent-mypulse-notifications"

    private struct Applied: Codable, Equatable {
        let mode: Mode
        let userToken: String
        let langCode: String
        let digestHour: Int
        let timeZone: String
    }

    private struct State: Codable {
        var mode: Mode = .off
        var digestHour: Int = 21
        var applied: Applied?
    }

    public private(set) var mode: Mode
    public private(set) var digestHour: Int
    private var applied: Applied?
    private let userDefaults: UserDefaults
    private let getToken: () -> String?
    private let ensureToken: () async throws -> String?
    private let language: () -> String
    private let timeZone: () -> String
    private let apply: (ApiSetNewsNotificationsProps) async throws -> Bool
    private var operation: Task<Outcome, Never>?
    private var resetGeneration = 0
    private var observers: [NSObjectProtocol] = []

    init(
        userDefaults: UserDefaults = .standard,
        getToken: @escaping () -> String? = { AppStorageHelper.pushNotifications?.userToken },
        ensureToken: @escaping () async throws -> String? = { try await ensurePushNotificationToken() },
        language: @escaping () -> String = { LocalizationSupport.shared.langCode },
        timeZone: @escaping () -> String = { TimeZone.current.identifier },
        apply: @escaping (ApiSetNewsNotificationsProps) async throws -> Bool = { try await Api.setNewsNotifications(props: $0).ok }
    ) {
        self.userDefaults = userDefaults
        self.getToken = getToken
        self.ensureToken = ensureToken
        self.language = language
        self.timeZone = timeZone
        self.apply = apply
        let state = userDefaults.data(forKey: Self.storageKey).flatMap { try? JSONDecoder().decode(State.self, from: $0) } ?? State()
        mode = state.mode
        digestHour = state.digestHour
        applied = state.applied
    }

    public func setMode(_ mode: Mode) async -> Outcome {
        let generation = resetGeneration
        return await enqueue { [self] in
            guard generation == resetGeneration else { return .failed }
            let token: String
            do {
                if mode == .off {
                    guard let existing = getToken() ?? applied?.userToken else {
                        self.mode = mode
                        save()
                        return .ok
                    }
                    token = existing
                } else {
                    guard let permitted = try await ensureToken() else { return .permissionDenied }
                    token = permitted
                }
            } catch {
                return .failed
            }
            guard generation == resetGeneration else { return .failed }
            let result = await applyMode(mode, token: token)
            guard generation == resetGeneration else { return .failed }
            if result == .ok {
                self.mode = mode
                save()
            }
            return result
        }.value
    }

    public func setDigestHour(_ hour: Int) async -> Outcome {
        guard (0...23).contains(hour) else { return .failed }
        digestHour = hour
        save()
        return await enqueue { [self] in
            guard mode == .digest else { return .ok }
            guard let token = getToken() else { return .failed }
            return await applyMode(mode, token: token)
        }.value
    }

    public func reapplyIfNeeded() async -> Outcome {
        await enqueue { [self] in
            guard mode != .off || applied?.mode != nil && applied?.mode != .off else { return .ok }
            guard let token = getToken() ?? applied?.userToken else { return .failed }
            guard makeApplied(mode, token: token) != applied else { return .ok }
            return await applyMode(mode, token: token)
        }.value
    }

    public func reset() -> Task<Outcome, Never> {
        resetGeneration += 1
        mode = .off
        save()
        return enqueue { [self] in
            guard let token = getToken() ?? applied?.userToken else { return .ok }
            return await applyMode(.off, token: token)
        }
    }

    func waitForReset(_ resetTask: Task<Outcome, Never>, timeout: Duration) async -> Outcome {
        // A bridge request can ignore cancellation, so the timeout must not join its task
        await withCheckedContinuation { continuation in
            var pending: CheckedContinuation<Outcome, Never>? = continuation
            let timeoutTask = Task { @MainActor in
                do { try await Task.sleep(for: timeout) } catch { return }
                guard let continuation = pending else { return }
                pending = nil
                continuation.resume(returning: .failed)
            }
            Task { @MainActor in
                let result = await resetTask.value
                guard let continuation = pending else { return }
                pending = nil
                timeoutTask.cancel()
                continuation.resume(returning: result)
            }
        }
    }

    public func start() {
        stop()
        for name in [UIApplication.didBecomeActiveNotification, NSLocale.currentLocaleDidChangeNotification, NSNotification.Name.NSSystemTimeZoneDidChange] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in _ = await self?.reapplyIfNeeded() }
            })
        }
        Task { _ = await reapplyIfNeeded() }
    }

    public func stop() {
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        observers = []
    }

    private func enqueue(_ action: @escaping @MainActor () async -> Outcome) -> Task<Outcome, Never> {
        let previous = operation
        let task = Task {
            _ = await previous?.value
            return await action()
        }
        operation = task
        return task
    }

    private func applyMode(_ mode: Mode, token: String) async -> Outcome {
        let candidate = makeApplied(mode, token: token)
        do {
            guard try await apply(.init(
                mode: mode, userToken: token, platform: .ios, langCode: candidate.langCode,
                digestHour: candidate.digestHour, timeZone: candidate.timeZone
            )) else { return .failed }
            applied = candidate
            save()
            return .ok
        } catch {
            return .failed
        }
    }

    private func makeApplied(_ mode: Mode, token: String) -> Applied {
        Applied(mode: mode, userToken: token, langCode: language(), digestHour: digestHour, timeZone: timeZone())
    }

    private func save() {
        let state = State(mode: mode, digestHour: digestHour, applied: applied)
        userDefaults.set(try? JSONEncoder().encode(state), forKey: Self.storageKey)
    }
}
