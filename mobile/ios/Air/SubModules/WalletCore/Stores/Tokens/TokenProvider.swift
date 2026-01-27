
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
    public var token: ApiToken {
        get {
            _token
        }
        set {
            slug = newValue.slug
            _token = newValue
        }
    }
    
    private var _token: ApiToken!
    
    private let tokenStore: _TokenStore
    
    @PerceptionIgnored
    private var observeToken: ObserveToken?
    
    public init(tokenSlug: String) {
        
        @Dependency(\.tokenStore) var tokenStore
        self.tokenStore = tokenStore

        self.slug = tokenSlug
        
        observeToken = observe { [weak self] in
            guard let self else { return }
            if let token = tokenStore[slug] {
                self.token = token
            } else if self._token == nil {
                let chain = getChainBySlug(slug) ?? FALLBACK_CHAIN
                let nativeToken = chain.nativeToken
                self.slug = nativeToken.slug
                self.token = nativeToken
            }
        }
    }
    
    public var wrappedValue: ApiToken {
        get { token }
        set { token = newValue }
    }
    public var projectedValue: TokenProvider { self }
}
