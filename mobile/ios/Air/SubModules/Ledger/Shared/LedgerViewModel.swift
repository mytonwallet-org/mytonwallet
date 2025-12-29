
import WalletContext
import SwiftUI
import Perception

@MainActor
@Perceptible
public final class LedgerViewModel {
    
    public struct Step: Equatable, Identifiable {
        public var id: StepId
        public var status: StepStatus
        
        init(id: StepId, status: StepStatus) {
            self.id = id
            self.status = status
        }
    }
    
    internal(set) public var steps: [Step] = []
    internal(set) public var showBack: Bool = true
    internal(set) public var backEnabled: Bool = true
    internal(set) public var showRetry: Bool = false
    internal(set) public var retryEnabled: Bool = true
 
    @PerceptionIgnored
    internal(set) public var stop: () -> () = { }
    @PerceptionIgnored
    internal(set) public var restart: () -> () = { }
    @PerceptionIgnored
    internal(set) public var retryCurrentStep: () -> () = { }
    
    nonisolated init() {
    }
}
