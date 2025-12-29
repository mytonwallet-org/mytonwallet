
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
        case .getLedgerDeviceModel(callback: let callback):
            Task { await handleGetLedgerDeviceModel(callback: callback) }
        default:
            break
        }
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

    private func handleGetLedgerDeviceModel(callback: @Sendable (ApiLedgerDeviceModel?) async -> ()) async {
        do {
            let transport = try (self.bleTransport as? BleTransport).orThrow()
            let uuid = try transport.currentConnectedService()
            let name = connectedIdentifier?.name.nilIfEmpty
            let model = switch uuid {
            case "13D63400-2C97-0004-0000-4C6564676572":
                ApiLedgerDeviceModel(id: "nanoX", productName: name ?? "Ledger Nano X")
            case "13d63400-2c97-6004-0000-4c6564676572":
                ApiLedgerDeviceModel(id: "stax", productName: name ?? "Ledger Stax")
            case "13d63400-2c97-3004-0000-4c6564676572":
                ApiLedgerDeviceModel(id: "europa", productName: name ?? "Ledger Flex")
            default:
                ApiLedgerDeviceModel(id: "nanoX", productName: name ?? "Unknown model")
            }
            await callback(model); return
        } catch {
            await callback(nil); return
        }
    }
}

