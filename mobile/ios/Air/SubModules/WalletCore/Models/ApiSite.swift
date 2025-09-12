//
//  MExploreSite.swift
//  WalletCore
//
//  Created by Sina on 6/25/24.
//

import Foundation
import WalletContext


public struct ApiSite: Equatable, Hashable, Codable, Sendable {
    public var url: String
    public var name: String
    public var icon: String
    public var manifestUrl: String?
    public var description: String
    public var canBeRestricted: Bool
    public var isExternal: Bool?
    public var isFeatured: Bool?
    public var categoryId: Int?

    public var extendedIcon: String?
    public var badgeText: String?
    public var withBorder: Bool?
    
    // for testing
    public var test_kicker: String?
    public var test_shortTitle: String { name }
    
}

extension ApiSite {
    public var shouldOpenExternally: Bool {
        isExternal == true || url.starts(with: "https://t.me/")
    }
    
    public var tgUrl: URL? {
        // TODO: convert to tg:// url to open Telegram directly, without Safari
        if url.starts(with: "https://t.me/") {
            return URL(string: url)
        }
        return nil
    }
}

public struct ApiSiteCategory: Equatable, Hashable, Codable, Sendable {
    public var id: Int
    public var name: String
}

extension ApiSiteCategory {
    public var displayName: String {
        lang(name)
    }
}


// MARK: - Sample data

#if DEBUG
public extension ApiSite {
    
    static let sampleFeaturedTelegram = ApiSite(
        url: "https://t.me/",
        name: "Sample name",
        icon: "https://static.mytonwallet.org/explore-icons/mtwcards.webp",
        manifestUrl: "",
        description: "Sample description",
        canBeRestricted: false,
        isExternal: true,
        isFeatured: true,
        categoryId: nil,
        extendedIcon: "https://static.mytonwallet.org/explore-icons/mtwcards.webp",
        badgeText: nil,
        withBorder: nil,
        test_kicker: "NO blink to earn",
    )
    
    static let sampleExploreSites: ApiExploreSitesResult = try! JSONDecoder().decode(ApiExploreSitesResult.self, from: #"{"categories":[{"name":"Games","id":1},{"name":"Entertainment","id":2},{"name":"DeFi","id":3},{"name":"NFT","id":4},{"name":"Utilities","id":5}],"sites":[{"icon":"https:\/\/mytonwallet.s3.eu-central-1.amazonaws.com\/explore-icons\/drft.png","url":"https:\/\/t.me\/drft_party_bot\/game?startapp=mytonwallet","categoryId":1,"name":"DRFT Party","description":"Merge NFT cars & drift to Airdrop!","canBeRestricted":false,"isExternal":true},{"description":"Drag. Race. Win.","name":"The Race","icon":"https:\/\/static.mytonwallet.org\/explore-icons\/race.jpg","categoryId":1,"url":"https:\/\/t.me\/race?start=i-RPAKl","canBeRestricted":false},{"icon":"https:\/\/static.mytonwallet.org\/explore-icons\/bombie.jpg","url":"https:\/\/t.me\/catizenbot","categoryId":1,"name":"Bombie","description":"New action game from the creators of Catizen","canBeRestricted":false,"isExternal":true},{"icon":"https:\/\/static.mytonwallet.org\/explore-icons\/cattea.jpg","url":"https:\/\/t.me\/CatteaAIbot","categoryId":1,"name":"Cattea","description":"It's a drink to earn Meow-ment!","canBeRestricted":false,"isExternal":true},{"icon":"https:\/\/static.mytonwallet.org\/explore-icons\/tinyverse.jpg","url":"https:\/\/t.me\/tverse","categoryId":1,"name":"Tiny Verse","description":"Become a creator of your own galaxy","canBeRestricted":false,"isExternal":true},{"icon":"https:\/\/static.mytonwallet.org\/explore-icons\/totemancer.jpg","url":"https:\/\/t.me\/TotemancerBot\/Play?startapp=refmytonwallet","categoryId":1,"name":"Totemancer","description":"Strategy PvP game: Mint NFT Totems and duel with friends","canBeRestricted":false,"isExternal":true},{"icon":"https:\/\/static.mytonwallet.org\/explore-icons\/boinkers.jpg","url":"https:\/\/t.me\/boinker_bot","categoryId":1,"name":"Boinkers","description":"Parody game to farm memecoin","canBeRestricted":false,"isExternal":true},{"description":"The kit to launch a game on Telegram","name":"TON Play","icon":"https:\/\/mytonwallet.s3.eu-central-1.amazonaws.com\/explore-icons\/ton-play.png","categoryId":1,"url":"https:\/\/tonplay.io\/","canBeRestricted":false},{"icon":"https:\/\/mytonwallet.s3.eu-central-1.amazonaws.com\/explore-icons\/edchess.png","url":"https:\/\/t.me\/edchess_bot\/web3?startapp=ref-link=MyTonWallet","categoryId":2,"name":"EdChess","description":"Play chess, learn and earn TON","canBeRestricted":false,"isExternal":true},{"description":"Best poker room for USDT","name":"TON Poker","icon":"https:\/\/static.mytonwallet.org\/explore-icons\/ton_poker.jpg","categoryId":2,"url":"https:\/\/mtw.tonpoker.online\/","canBeRestricted":true},{"icon":"https:\/\/mytonwallet.s3.eu-central-1.amazonaws.com\/explore-icons\/fanzee.png","url":"https:\/\/t.me\/battlescryptobot\/battles?startapp=myTonWallet","categoryId":2,"name":"Fanzee Battles","description":"Make predictions on major global events and join the AirDrop!","canBeRestricted":false,"isExternal":true},{"icon":"https:\/\/mytonwallet.s3.eu-central-1.amazonaws.com\/explore-icons\/tonmap.png","url":"https:\/\/t.me\/TheTonMapBot\/Map?startapp=f_mytonwallet","categoryId":2,"name":"TON Map","description":"Your space, your ads, your games—on Telegram’s first Web3 Verse","canBeRestricted":false,"isExternal":true},{"description":"Win games, earn USDT","name":"TON Durak","icon":"https:\/\/static.mytonwallet.org\/explore-icons\/ton_durak.png","categoryId":2,"url":"https:\/\/tkapp.tondurakgame.com\/","canBeRestricted":true},{"icon":"https:\/\/static.mytonwallet.org\/explore-icons\/minex.jpg","url":"https:\/\/t.me\/MineXton_bot?start=r_7899403160","categoryId":2,"name":"MineX","description":"Virtual cryptocurrency mining on TON","canBeRestricted":true,"isExternal":true},{"description":"Play poker for free and earn tokens","name":"TG Poker","icon":"https:\/\/static.mytonwallet.org\/explore-icons\/tg_poker.jpg","categoryId":2,"url":"https:\/\/mtw-tgp.tonpoker.online\/","canBeRestricted":true},{"description":"Leveraged DEX to trade everything in Telegram","name":"Storm Trade","icon":"https:\/\/static.mytonwallet.org\/explore-icons\/storm.jpg","categoryId":3,"url":"https:\/\/app.storm.tg\/?ref=wallet&utm_source=wallet_web&utm_medium=wallet&utm_campaign=mainnet_launch","canBeRestricted":true},{"description":"First lending protocol on TON. Earn and borrow on Telegram","name":"EVAA Protocol ","icon":"https:\/\/static.mytonwallet.org\/explore-icons\/evaa.png","categoryId":3,"url":"https:\/\/app.evaa.finance\/?referral=UQANbEi_Ly2RysQr_cSIYTJKxNdLPVBDS3d-gojbPl4IYhju","canBeRestricted":true},{"description":"Up to 15% on USDT and x50 points farming","name":"FIVA","icon":"https:\/\/static.mytonwallet.org\/explore-icons\/fiva.png","categoryId":3,"url":"https:\/\/app.thefiva.com\/?access=MTWLT","canBeRestricted":true},{"icon":"https:\/\/static.mytonwallet.org\/explore-icons\/settleton.jpg","url":"https:\/\/t.me\/settleton_bot","categoryId":3,"name":"SettleTON","description":"Auto-Reinvest with one click","canBeRestricted":true,"isExternal":true},{"icon":"https:\/\/static.mytonwallet.org\/explore-icons\/ton_hedge.jpg","url":"https:\/\/t.me\/ton_hedge_bot","categoryId":3,"name":"TON Hedge","description":"Manage risk with TON’s decentralized options trading","canBeRestricted":true,"isExternal":true},{"icon":"https:\/\/mytonwallet.s3.eu-central-1.amazonaws.com\/explore-icons\/fragment.png","url":"https:\/\/fragment.com\/","categoryId":4,"name":"Fragment","description":"Telegram Premium subscriptions, anonymous numbers, usernames, etc.","manifestUrl":"https:\/\/fragment.com\/tonconnect-manifest.json","canBeRestricted":true},{"description":"Advanced solution for NFT traders","name":"Marketapp","icon":"https:\/\/static.mytonwallet.org\/explore-icons\/marketapp.png","categoryId":4,"url":"https:\/\/marketapp.ws\/?utm_source=mtw&utm_campaign=mtw","canBeRestricted":true},{"description":"Personalize your wallet interface","name":"MyTonWallet Cards NFT","icon":"https:\/\/static.mytonwallet.org\/explore-icons\/mtwcards.webp","categoryId":4,"url":"https:\/\/cards.mytonwallet.io\/","canBeRestricted":false},{"description":"Use your NFTs as collateral to instantly get TON","name":"DAOLama","icon":"https:\/\/static.mytonwallet.org\/explore-icons\/daolama.jpg","categoryId":4,"url":"https:\/\/app.daolama.co\/?ref=D9HjuSIbsU","canBeRestricted":true},{"description":"First NFT marketplace on TON","name":"Getgems","icon":"https:\/\/static.mytonwallet.org\/explore-icons\/getgems.jpg","categoryId":4,"url":"https:\/\/getgems.io\/","canBeRestricted":true},{"description":"Buy, trade, track and search TON domains","name":"WEB3 | webdom","icon":"https:\/\/static.mytonwallet.org\/explore-icons\/webdom.png","categoryId":4,"url":"https:\/\/webdom.market\/","canBeRestricted":true},{"description":"Auction house and marketplace for global digital artists","name":"TON Diamonds","icon":"https:\/\/mytonwallet.s3.eu-central-1.amazonaws.com\/explore-icons\/ton-diamonds.png","categoryId":4,"url":"https:\/\/ton.diamonds\/","canBeRestricted":true},{"icon":"https:\/\/static.mytonwallet.org\/explore-icons\/esim.jpg","url":"https:\/\/t.me\/eSIMhubBot?start=9d8db4662fb5429648e103d1","categoryId":5,"name":"eSim","description":"Whole world in one eSIM","canBeRestricted":false,"isExternal":true},{"description":"Secure your unique TON domain name","name":"TON Domains","icon":"https:\/\/static.mytonwallet.org\/explore-icons\/ton.jpg","categoryId":5,"url":"https:\/\/dns.ton.org","canBeRestricted":false},{"icon":"https:\/\/mytonwallet.s3.eu-central-1.amazonaws.com\/explore-icons\/cryptobot.png","url":"https:\/\/t.me\/send?start=i-YLX91SP","categoryId":5,"name":"Crypto Bot","description":"Buy, sell, store, @send and pay with cryptocurrency right in Telegram","canBeRestricted":true,"isExternal":true},{"icon":"https:\/\/static.mytonwallet.org\/explore-icons\/sticker_store.jpg","url":"https:\/\/t.me\/sticker_bot","categoryId":5,"name":"Sticker Store","description":"First tokenized stickers on Telegram","canBeRestricted":true,"isExternal":true},{"icon":"https:\/\/static.mytonwallet.org\/explore-icons\/ton.jpg","url":"https:\/\/t.me\/tonvpn_bot","categoryId":5,"name":"TON VPN","description":"Browse privately with decentralized VPN","canBeRestricted":true,"isExternal":true},{"description":"Most powerful TON explorer","name":"Tоnscan","icon":"https:\/\/static.mytonwallet.org\/explore-icons\/tonscan.png","categoryId":5,"url":"https:\/\/tonscan.org\/","canBeRestricted":false},{"description":"Discover top TON apps and services","name":"TON App","icon":"https:\/\/static.mytonwallet.org\/explore-icons\/ton_app.png","categoryId":5,"url":"https:\/\/ton.app\/","canBeRestricted":false},{"icon":"https:\/\/static.mytonwallet.org\/explore-icons\/nomis.jpg","url":"https:\/\/t.me\/NomisAppBot\/app?startapp=ref_yArJ6HFTo-","categoryId":5,"name":"Nomis","description":"Build, manage, and leverage your onchain reputation","canBeRestricted":false,"isExternal":true},{"icon":"https:\/\/static.mytonwallet.org\/explore-icons\/ton_dating.jpg","url":"https:\/\/t.me\/tondating","categoryId":5,"name":"TON Dating","description":"Make meaningful connections","canBeRestricted":false,"isExternal":true},{"icon":"https:\/\/static.mytonwallet.org\/explore-icons\/pollo.png","url":"https:\/\/t.me\/pollovotebot\/pollo?startapp=mtw-mtw","categoryId":2,"name":"Pollo","description":"Use opinions to connect with people.","canBeRestricted":false,"isExternal":true},{"description":"Open-source liquid staking on TON","name":"Hipo","icon":"https:\/\/static.mytonwallet.org\/explore-icons\/hipo_dark.png","categoryId":3,"url":"https:\/\/app.hipo.finance\/#\/referrer=UQDUdDT4vLsN7IRcoZOVZg9FGZU5rSb-8alSFGhRLW_0FvT9\/","canBeRestricted":true}]}"#.data(using: .utf8)!)
}

#endif
