import Foundation

/// Keeps hot-path reads in memory while observing writes from UIKit, AppStorage, and other processes.
public final class CachedUserDefault<Value: Sendable>: NSObject, Sendable {
    // Foundation documents UserDefaults as thread-safe; retain it only for KVO registration/teardown.
    nonisolated(unsafe) private let defaults: UserDefaults
    private let key: String
    private let decode: @Sendable (Any?) -> Value
    private let state: UnfairLock<Value>

    public init(
        key: String,
        defaultValue: Value,
        defaults: UserDefaults = .standard,
        decode: @escaping @Sendable (Any?) -> Value
    ) {
        self.defaults = defaults
        self.key = key
        self.decode = decode
        self.state = UnfairLock(initialState: defaultValue)
        super.init()
        defaults.addObserver(self, forKeyPath: key, options: [.initial, .new], context: nil)
    }

    deinit {
        defaults.removeObserver(self, forKeyPath: key)
    }

    public var value: Value { state.withLock { $0 } }

    public override func observeValue(
        forKeyPath keyPath: String?,
        of object: Any?,
        change: [NSKeyValueChangeKey: Any]?,
        context: UnsafeMutableRawPointer?
    ) {
        guard keyPath == key else {
            super.observeValue(forKeyPath: keyPath, of: object, change: change, context: context)
            return
        }
        let value = decode(change?[.newKey])
        state.withLock { $0 = value }
    }
}

public extension CachedUserDefault where Value == Bool {
    convenience init(key: String, defaults: UserDefaults = .standard) {
        self.init(key: key, defaultValue: false, defaults: defaults) {
            ($0 as? NSNumber)?.boolValue ?? ($0 as? NSString)?.boolValue ?? false
        }
    }
}
