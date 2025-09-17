
import Foundation

public let DEFAULT_TO_AIR = false

// reference: src/config.ts

public let NATIVE_BIOMETRICS_USERNAME = "MyTonWallet"
public let NATIVE_BIOMETRICS_SERVER = "https://mytonwallet.app"

public let PRICELESS_TOKEN_HASHES: Set<String?> = [
  "82566ad72b6568fe7276437d3b0c911aab65ed701c13601941b2917305e81c11", // Stonfi V1
  "ec614ea4aaea3f7768606f1c1632b3374d3de096a1e7c4ba43c8009c487fee9d", // Stonfi V2
  "c0f9d14fbc8e14f0d72cba2214165eee35836ab174130912baf9dbfa43ead562", // Dedust (for example, EQBkh7Mc411WTYF0o085MtwJpYpvGhZOMBphhIFzEpzlVODp)
  "1275095b6da3911292406f4f4386f9e780099b854c6dee9ee2895ddce70927c1", // Dedust (for example, EQCm92zFBkLe_qcFDp7WBvI6JFSDsm4WbDPvZ7xNd7nPL_6M)
  "5d01684bdf1d5c9be2682c4e36074202432628bd3477d77518d66b0976b78cca", // USDT Storm LP (for example, EQAzm06UMMsnFQrNKEubV1myIR-mm2ZOCnoic36frCgD8MLR)
]

public let STAKED_TOKEN_SLUGS: Set<String> = [
  STAKED_TON_SLUG,
  STAKED_MYCOIN_SLUG,
  TON_TSUSDE_SLUG,
]

public let NFT_MARKETPLACE_URL = "https://getgems.io/"
public let NFT_MARKETPLACE_TITLE = "GetGems"

public let MAX_PUSH_NOTIFICATIONS_ACCOUNT_COUNT = 3

public let LIQUID_POOL = "EQD2_4d91M4TVbEBVyBF8J1UwpMJc361LKVCz6bBlffMW05o"
public let MYCOIN_STAKING_POOL = "EQC3roTiRRsoLzfYVK7yVVoIZjTEqAjQU3ju7aQ7HWTVL5o5"

public let ALL_STAKING_POOLS: Set<String> = [
  LIQUID_POOL,
  MYCOIN_STAKING_POOL,
]

public let BURN_ADDRESS = "UQAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAJKZ"

public let TINY_TRANSFER_MAX_COST = 0.01

public let TELEGRAM_GIFTS_SUPER_COLLECTION = "super:telegram-gifts"

public let JVAULT_URL = "https://jvault.xyz"

public let MAX_PRICE_IMPACT_VALUE = 5.0
