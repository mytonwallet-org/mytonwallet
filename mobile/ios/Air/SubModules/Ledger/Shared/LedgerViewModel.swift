
import WalletContext
import SwiftUI

@MainActor
public final class LedgerViewModel: ObservableObject {
    
    public struct Step: Equatable, Identifiable {
        public var id: StepId
        public var status: StepStatus
        
        init(id: StepId, status: StepStatus) {
            self.id = id
            self.status = status
        }
    }
    
    @MainActor @Published internal(set) public var steps: [Step] = []
    @MainActor @Published internal(set) public var showBack: Bool = true
    @MainActor @Published internal(set) public var backEnabled: Bool = true
    @MainActor @Published internal(set) public var showRetry: Bool = false
    @MainActor @Published internal(set) public var retryEnabled: Bool = true
 
    internal(set) public var stop: () -> () = { }
    internal(set) public var restart: () -> () = { }
    internal(set) public var retryCurrentStep: () -> () = { }
    
    nonisolated init() {
    }
}
