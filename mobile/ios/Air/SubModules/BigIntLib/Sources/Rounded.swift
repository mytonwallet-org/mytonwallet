//
//  Rounded.swift
//  MyTonWalletAir
//
//  Created by nikstar on 28.07.2025.
//

/// Powers of 10 up to 1e18
public let POW10: [BigUInt] = [
    0,
    10,
    100,
    1000,
    10000,
    100000,
    1000000,
    10000000,
    100000000,
    1000000000,
    10000000000,
    100000000000,
    1000000000000,
    10000000000000,
    100000000000000,
    1000000000000000,
    10000000000000000,
    100000000000000000,
    1000000000000000000,
]

public extension BigUInt {
    func rounded(digitsToRound: Int, roundUp: Bool) -> BigUInt {
        guard digitsToRound > 0 else { return self }
        let pow10 = _pow10(digitsToRound)
        let rem = self % pow10
        var result = self - rem
        if roundUp {
            let half = pow10 >> 2
            if rem >= half {
                result += pow10
            }
        }
        return result
    }
    
    @inline(__always) private func _pow10(_ exponent: Int) -> BigUInt {
        return exponent < POW10.count ? POW10[exponent] : BigUInt(10).power(exponent)
    }
}

public extension BigInt {
    func rounded(digitsToRound: Int, roundUp: Bool) -> BigInt {
        return BigInt(sign: self.sign, magnitude: self.magnitude.rounded(digitsToRound: digitsToRound, roundUp: roundUp))
    }
}
