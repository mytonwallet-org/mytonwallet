//
//  BigIntUtils.swift
//  MyTonWalletAir
//
//  Created by Sina on 1/5/25.
//

@_exported import BigInt

extension BigInt {

    public func doubleAbsRepresentation(decimals: Int) -> Double {
        var str = "\(abs(self))"
        while str.count < decimals + 1 {
            str.insert("0", at: str.startIndex)
        }
        str.insert(contentsOf: ".", at: str.index(str.endIndex, offsetBy: -decimals))
        return Double(str)!
    }
}
