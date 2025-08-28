
import BleTransport
import Foundation


enum APDUHelpers {
    private static let LEDGER_SYSTEM: UInt8 = 0xB0
    static let LEDGER_CLA: UInt8 = 0xE0
    static let INS_VERSION: UInt8 = 0x03
    static let INS_ADDRESS: UInt8 = 0x05
    static let INS_SIGN_TX: UInt8 = 0x06
    static let INS_PROOF: UInt8 = 0x08
    static let INS_SIGN_DATA: UInt8 = 0x09
    
    static func currentApp() -> APDU {
        let bytes: [UInt8] = [
            LEDGER_SYSTEM,
            0x01,
            0x00,
            0x00,
            0x00
        ]
        return APDU(data: bytes)
    }
    
    static func getPublicKey(isTestnet: Bool, workChain: Int, index: Int) -> APDU {
        let paths = getLedgerAccountPath(isTestnet: isTestnet, workChain: Int32(workChain), index: Int32(index))
        var buffer: [UInt8] = [
            LEDGER_CLA,
            INS_ADDRESS,
            0x00,
            0x00,
            UInt8(1 + paths.count * 4)
        ]
        
        buffer.append(UInt8(paths.count))
        for path in paths {
            let hardenedPath = UInt32(bitPattern: path) + 0x80000000
            let bytes = withUnsafeBytes(of: hardenedPath.bigEndian) { Array($0) }
            buffer.append(contentsOf: bytes)
        }
        
        return APDU(data: buffer)
    }
    
    static func getLedgerAccountPath(isTestnet: Bool, workChain: Int32, index: Int32) -> [Int32] {
        [44, 607, isTestnet ? 1 : 0, workChain, index, 0]
    }
    
    static func decode(hex: String) -> [UInt8] {
        return stride(from: 0, to: hex.count, by: 2).map {
            let startIndex = hex.index(hex.startIndex, offsetBy: $0)
            let endIndex = hex.index(startIndex, offsetBy: 2)
            return UInt8(hex[startIndex..<endIndex], radix: 16) ?? 0
        }
    }
    
    static func decodeReadable(_ hex: String) -> [String] {
        let bytes = stride(from: 0, to: hex.count, by: 2).map {
            let startIndex = hex.index(hex.startIndex, offsetBy: $0)
            let endIndex = hex.index(startIndex, offsetBy: 2)
            return UInt8(hex[startIndex..<endIndex], radix: 16) ?? 0
        }
        
        var parts: [String] = []
        var current = ""
        
        for byte in bytes {
            let ch = Character(UnicodeScalar(byte))
            if ch.isASCII && ch >= " " && ch <= "~" {
                current.append(ch)
            } else {
                if !current.isEmpty {
                    parts.append(current)
                    current = ""
                }
            }
        }
        
        if !current.isEmpty {
            parts.append(current)
        }
        
        return parts
    }
}
