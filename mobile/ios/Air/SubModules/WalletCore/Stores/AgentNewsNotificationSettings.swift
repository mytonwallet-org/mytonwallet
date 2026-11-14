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
    /// The digest's minutes the server sends it at
    public static let digestMinutes = [0, 15, 30, 45]
    private static let storageKey = "agent-mypulse-notifications"

    fileprivate struct Applied: Codable, Equatable {
        let mode: Mode
        let userToken: String
        let langCode: String
        let digestHour: Int
        let digestMinute: Int
        let timeZone: String
    }

    fileprivate struct State: Codable {
        var mode: Mode = .off
        var digestHour: Int = 21
        var digestMinute: Int = 0
        var newsFeedView: String?
        var applied: Applied?
    }

    public private(set) var mode: Mode
    public private(set) var digestHour: Int
    public private(set) var digestMinute: Int
    public private(set) var newsFeedView: ApiAgentV2NewsFeedView
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
        digestMinute = state.digestMinute
        newsFeedView = state.newsFeedView.flatMap(ApiAgentV2NewsFeedView.init(rawValue:)) ?? .all
        applied = state.applied
    }

    public func setNewsFeedView(_ view: ApiAgentV2NewsFeedView) {
        newsFeedView = view
        save()
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

    public func setDigestTime(hour: Int, minute: Int) async -> Outcome {
        guard (0...23).contains(hour), Self.digestMinutes.contains(minute) else { return .failed }
        digestHour = hour
        digestMinute = minute
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
                digestHour: candidate.digestHour, digestMinute: candidate.digestMinute, timeZone: candidate.timeZone
            )) else { return .failed }
            applied = candidate
            save()
            return .ok
        } catch {
            return .failed
        }
    }

    private func makeApplied(_ mode: Mode, token: String) -> Applied {
        Applied(
            mode: mode, userToken: token, langCode: language(), digestHour: digestHour, digestMinute: digestMinute, timeZone: timeZone()
        )
    }

    private func save() {
        let state = State(
            mode: mode, digestHour: digestHour, digestMinute: digestMinute, newsFeedView: newsFeedView.rawValue, applied: applied
        )
        userDefaults.set(try? JSONEncoder().encode(state), forKey: Self.storageKey)
    }
}

// A state saved before the digest took minutes has no minute, which is 0
extension AgentNewsNotificationSettings.Applied {
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            mode: try container.decode(AgentNewsNotificationSettings.Mode.self, forKey: .mode),
            userToken: try container.decode(String.self, forKey: .userToken),
            langCode: try container.decode(String.self, forKey: .langCode),
            digestHour: try container.decode(Int.self, forKey: .digestHour),
            digestMinute: try container.decodeIfPresent(Int.self, forKey: .digestMinute) ?? 0,
            timeZone: try container.decode(String.self, forKey: .timeZone)
        )
    }
}

extension AgentNewsNotificationSettings.State {
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            mode: try container.decode(AgentNewsNotificationSettings.Mode.self, forKey: .mode),
            digestHour: try container.decode(Int.self, forKey: .digestHour),
            digestMinute: try container.decodeIfPresent(Int.self, forKey: .digestMinute) ?? 0,
            newsFeedView: try container.decodeIfPresent(String.self, forKey: .newsFeedView),
            applied: try container.decodeIfPresent(AgentNewsNotificationSettings.Applied.self, forKey: .applied)
        )
    }
}
