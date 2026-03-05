import Foundation
import Network

@MainActor
public final class Reachability {
    public typealias NetworkReachable = @MainActor (Reachability) -> Void
    public typealias NetworkUnreachable = @MainActor (Reachability) -> Void

    public enum Connection: CustomStringConvertible, Sendable {
        case unavailable
        case wifi
        case cellular

        public var description: String {
            switch self {
            case .unavailable:
                "unavailable"
            case .wifi:
                "wifi"
            case .cellular:
                "cellular"
            }
        }
    }

    public var whenReachable: NetworkReachable?
    public var whenUnreachable: NetworkUnreachable?

    public var allowsCellularConnection = true

    public var connection: Connection {
        currentConnection
    }

    private let monitorQueue = DispatchQueue(label: "org.mytonwallet.reachability")
    private var monitor: NWPathMonitor?
    private var currentConnection: Connection = .unavailable
    private var notifierRunning = false

    public init() {}

    isolated deinit {
        stopNotifier()
    }

    public func startNotifier() {
        guard notifierRunning == false else { return }

        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor [weak self] in
                self?.updateConnection(path: path)
            }
        }

        self.monitor = monitor
        self.notifierRunning = true
        monitor.start(queue: monitorQueue)

        // Emit initial state for current path as soon as monitoring starts.
        updateConnection(path: monitor.currentPath, forceNotify: true)
    }

    public func stopNotifier() {
        guard notifierRunning else { return }
        monitor?.cancel()
        monitor = nil
        notifierRunning = false
    }

    private func updateConnection(path: NWPath, forceNotify: Bool = false) {
        let newConnection = Self.resolveConnection(path: path, allowsCellularConnection: allowsCellularConnection)
        guard forceNotify || newConnection != currentConnection else { return }
        currentConnection = newConnection
        notifyReachabilityChanged()
    }

    private func notifyReachabilityChanged() {
        if connection == .unavailable {
            whenUnreachable?(self)
        } else {
            whenReachable?(self)
        }
    }

    private static func resolveConnection(path: NWPath, allowsCellularConnection: Bool) -> Connection {
        guard path.status == .satisfied else {
            return .unavailable
        }
        if path.usesInterfaceType(.wifi) || path.usesInterfaceType(.wiredEthernet) {
            return .wifi
        }
        if path.usesInterfaceType(.cellular) {
            return allowsCellularConnection ? .cellular : .unavailable
        }
        // Unknown but reachable interface (for example, loopback/other).
        return .wifi
    }
}
