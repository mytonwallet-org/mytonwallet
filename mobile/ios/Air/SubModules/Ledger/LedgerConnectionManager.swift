
import CoreBluetooth
import Foundation
@preconcurrency import BleTransport
import WalletCore
import WalletContext

private let log = Log("LedgerConnectionManager")

public typealias LedgerIdentifier = PeripheralIdentifier


public final class LedgerConnectionManager: WalletCoreData.EventsObserver, @unchecked Swift.Sendable {
    
    public static let shared = LedgerConnectionManager()
    
    public var bleTransport: any BleTransportProtocol { BleTransport.shared }
    public var connectedIdentifier: PeripheralIdentifier?
    private var ledgerInfo: LedgerAppInfo?
    
    var bluetoothState: CBManagerState?
    var bluetoothAvailability: Bool?
    
    private init() {
        bleTransport.notifyDisconnected(completion: handleBleDisconnected)
        bleTransport.bluetoothStateCallback { state in
            self.bluetoothState = state
        }
        bleTransport.bluetoothAvailabilityCallback { availability in
            self.bluetoothAvailability = availability
        }
        WalletCoreData.add(eventObserver: self)
    }
    
    public func walletCore(event: WalletCoreData.Event) {
        switch event {
        case .exchangeWithLedger(let apdu, callback: let callback):
            Task { await handleWriteToLedger(apdu, callback: callback) }
        case .isLedgerJettonIdSupported(callback: let callback):
            Task { await handleIsLedgerJettonIdSupported(callback: callback) }
        case .isLedgerUnsafeSupported(callback: let callback):
            Task { await handleIsLedgerUnsafeSupported(callback: callback) }
        default:
            break
        }
    }
    
    public func scan() async throws -> AsyncThrowingStream<[PeripheralInfo], any Error> {
        bleTransport.scan(duration: 30)
    }
    
    public func connect(toPeripheralID id: PeripheralIdentifier) async throws -> PeripheralIdentifier {
        try await bleTransport.connect(toPeripheralID: id, disconnectedCallback: handleBleDisconnected)
    }
    
    public func scanAndConnectToFirst(timeout: Double) async throws -> PeripheralIdentifier {
        if !bleTransport.isConnected {
            let id = try await bleTransport.create(scanDuration: timeout, disconnectedCallback: handleBleDisconnected)
            self.connectedIdentifier = id
            return id
        }
        return try self.connectedIdentifier.orThrow("No connected identifier")
    }
    
    public func connectToTonApp(peripheralID id: PeripheralIdentifier) async throws -> LedgerAppInfo {
        try await bleTransport.openAppIfNeeded("TON")
        let appInfo = try await bleTransport.getAppAndVersion()
        let ledgerInfo = LedgerAppInfo(version: appInfo.version)
        self.ledgerInfo = ledgerInfo
        return ledgerInfo
    }
    
    public func getPublicKey(walletIndex: Int) async throws -> [UInt8] {
        let string = try await bleTransport.exchange(apdu: APDUHelpers.getPublicKey(isTestnet: false, workChain: 0, index: walletIndex))
        let prefix = String(string.dropLast(4))
        let publicKey = APDUHelpers.decode(hex: prefix)
        return publicKey
    }
    
    private func handleBleDisconnected() {
        log.info("disconnected")
    }
    
    private func handleWriteToLedger(_ apdu: String, callback: @Sendable (String?) async -> ()) async {
        do {
            let string = try await bleTransport.exchange(apdu: APDU(raw: apdu))
            await callback(string)
        } catch {
            log.error("\(error, .public)")
            await callback(nil)
        }
    }
    
    private func handleIsLedgerJettonIdSupported(callback: @Sendable (Bool?) async -> ()) async {
        if let ledgerInfo {
            await callback(ledgerInfo.isJettonIdSupported)
        } else {
            await callback(nil)
        }
    }
    
    private func handleIsLedgerUnsafeSupported(callback: @Sendable (Bool?) async -> ()) async {
        if let ledgerInfo {
            await callback(ledgerInfo.isUnsafeSupported)
        } else {
            await callback(nil)
        }
    }
}

