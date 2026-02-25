
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

public let MYTONWALLET_MULTISEND_DAPP_URL = "https://multisend.mytonwallet.io/";

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

public let JSBRIDGE_IDENTIFIER = "jsbridge"

public let SUPPORT_USERNAME = "mysupport"

public let MTW_TIPS_CHANNEL_NAME = "MyTonWalletTips"
public let MTW_TIPS_CHANNEL_NAME_RU = "MyTonWalletTipsRu"

public let HELP_CENTER_URL = "https://help.mytonwallet.io"
public let HELP_CENTER_URL_RU = "https://help.mytonwallet.io/ru"
public let HELP_CENTER_DOMAIN_SCAM_URL = "https://help.mytonwallet.io/intro/scams/.ton-domain-scams"
public let HELP_CENTER_DOMAIN_SCAM_URL_RU = "https://help.mytonwallet.io/ru/baza-znanii/moshennichestvo-i-skamy/moshennichestvo-s-ispolzovaniem-domenov-.ton"
public let HELP_CENTER_SEED_SCAM_URL = "https://help.mytonwallet.io/intro/scams/leaked-seed-phrases"
public let HELP_CENTER_SEED_SCAM_URL_RU = "https://help.mytonwallet.io/ru/baza-znanii/moshennichestvo-i-skamy/slitye-sid-frazy"
public let DOMAIN_SCAM_REGEX = /^[-\w]{26,}\./
public let MTW_CARDS_COLLECTION = "EQCQE2L9hfwx1V8sgmF9keraHx1rNK9VmgR1ctVvINBGykyM"

public let CARD_RATIO: CGFloat = 208/358
public let SMALL_CARD_RATIO: CGFloat = 116/80
public let MEDIUM_CARD_RATIO: CGFloat = 110/75
public let LARGE_CARD_RATIO: CGFloat = 274/176

public var APP_NAME: String { lang("MyTonWallet") }

public var IS_DEBUG_OR_TESTFLIGHT: Bool {
    #if DEBUG
    return true
    #else
    return Bundle.main.appStoreReceiptURL?.lastPathComponent == "sandboxReceipt"
    #endif
}

public let SELF_PROTOCOL = "mtw://"
public let SHORT_UNIVERSAL_URL = "https://my.tt/"
public let SELF_UNIVERSAL_URLS = [SHORT_UNIVERSAL_URL,  "https://go.mytonwallet.org/"]
