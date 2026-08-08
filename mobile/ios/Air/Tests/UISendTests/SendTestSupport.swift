import WalletCore

func makeNft(
    chain: ApiChain,
    address: String
) -> ApiNft {
    var nft = ApiNft.ERROR
    nft.chain = chain
    nft.address = address
    return nft
}
