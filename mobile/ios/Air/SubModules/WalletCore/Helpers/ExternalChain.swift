//
//  ExternalChain.swift
//  MyTonWalletAir
//
//  Created by Sina on 10/16/24.
//

let chainNames = [
    "binance_smart_chain": "Binance Smart Chain",
    "internet_computer": "Internet Computer",
    "ethereum_classic": "Ethereum Classic",
    "bitcoin_cash": "Bitcoin Cash",
    "binance_dex": "Binance Dex",
    "ton": "TON",
    "bitcoin": "Bitcoin",
    "ethereum": "Ethereum",
    "solana": "Solana",
    "tron": "TRON",
    "stellar": "Stellar",
    "doge": "DOGE",
    "eos": "EOS",
    "avalanche": "Avalanche",
    "cardano": "Cardano",
    "monero": "Monero",
    "dash": "Dash",
    "ripple": "Ripple",
    "cosmos": "Cosmos",
    "litecoin": "Litecoin",
    "zcash": "Zcash",
    "polkadot": "Polkadot",
    "iota": "IOTA",
]

public func getChainName(_ chain: ApiChain) -> String {
    chainNames[chain.rawValue] ?? "[Unknown] \(chain.rawValue)"
}
