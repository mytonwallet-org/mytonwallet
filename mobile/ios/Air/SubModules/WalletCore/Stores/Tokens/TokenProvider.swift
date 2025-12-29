
import UIKit
import SwiftUI
import WalletContext
import Perception
import Dependencies
import SwiftNavigation

/// Provides token for `tokenSlug`. If token with that slug is deleted, falls back to native token.
@propertyWrapper @Perceptible
public final class TokenProvider {
    
    public var slug: String
    public private(set) var token: ApiToken!
    
    @PerceptionIgnored
    @Dependency(\.tokenStore) private var tokenStore
    
    @PerceptionIgnored
    private var observeToken: ObserveToken?
    
    /// Providing accountId == nil will track currentAccountId
    public init(tokenSlug: String) {
        
        self.slug = tokenSlug
        
        observeToken = observe { [weak self] in
            guard let self else { return }
            if let token = tokenStore[slug] {
                self.token = token
            } else {
                let chain = getChainBySlug(slug) ?? FALLBACK_CHAIN
                let nativeToken = chain.nativeToken
                self.slug = nativeToken.slug
                self.token = nativeToken
            }
        }
    }
    
    public var wrappedValue: ApiToken { token }
    public var projectedValue: TokenProvider { self }
}
