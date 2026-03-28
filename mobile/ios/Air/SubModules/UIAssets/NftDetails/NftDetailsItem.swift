import UIKit
import WalletContext

class NftDetailsItem: @unchecked Sendable {
    
    struct Attribute {
        let traitType: String
        let value: String
    }

    struct Collection {
        let name: String
    }
    
    struct TonDomain {
        let expirationDays: Int // < 0 means "expired"
        let canRenew: Bool
    }

    let id: String
    let name: String
    let description: String?
    let thumbnailUrl: String?
    let lottieUrl: String?
    let attributes: [Attribute]?
    let collection: Collection?
    let tonDomain: TonDomain?

    init(id: String, name: String, description: String?, thumbnailUrl: String?,
         lottieUrl: String?, attributes: [Attribute]?,
         collection: Collection?, tonDomain: TonDomain?) {
        self.id = id
        self.name = name
        self.description = description
        self.thumbnailUrl = thumbnailUrl
        self.attributes = attributes
        self.collection = collection
        self.tonDomain = tonDomain
        self.lottieUrl = lottieUrl
    }
}

extension NftDetailsItem.TonDomain {
    var expirationText: String {
        if expirationDays < 0 {
            return lang("Expired")
        } else {
            let daysText = lang("$in_days", arg1: expirationDays)
            return lang("$expires_in %days%", arg1: 1).replacingOccurrences(of: "1", with: daysText) // 1 is the number of domains, not days
        }
    }
}

protocol NftDetailsItemModelDelegate: AnyObject {
    func modelDidRequestImage(_  model: NftDetailsItemModel)
    func modelDidAddSubscription(_  model: NftDetailsItemModel, to event: NftDetailsItemModel.Event)
}

class NftDetailsItemModel: Identifiable, @unchecked Sendable, CustomStringConvertible {

    enum Action: CaseIterable { case wear, send, share, more }

    init(item: NftDetailsItem) {
        self.item = item
    }

    let item: NftDetailsItem

    var id: String { item.id }
    
    var name: String { item.name }
    
    var lottieUrl: URL? {
        guard let s = item.lottieUrl?.nilIfEmpty, let url = URL(string: s) else { return nil }
        return url
    }
    
    /// A flag to not use blurring and overlays for image processing: Lottie will spoil it all.
    var simplifiedImageProcessing: Bool { lottieUrl != nil }

    var processedImageState: NftDetailsImage.ProcessedState = .idle

    var isSelected: Bool = false {
        didSet {
            if isSelected != oldValue {
                notify(.selectionStatusChanged)
            }
        }
    }

    weak var delegate: NftDetailsItemModelDelegate?

    func requestImage() {
        delegate?.modelDidRequestImage(self)
    }
    
    var description: String {
        return "<Model '\(name)' \(processedImageState)>"
    }

    // MARK: - Event Subscription

    enum Event: Hashable {
        case processedImageUpdated
        case selectionStatusChanged
    }
    
    @MainActor
    class Subscription {
        let model: NftDetailsItemModel
        let event: Event
        let token: Int
        let tag: String
        
        init(model: NftDetailsItemModel, event: Event, tag: String, onChange: @escaping () -> Void) {
            self.event = event
            self.model = model
            self.tag = tag
            self.token = model.addObserver(for: event, onChange: onChange)
        }
        
        deinit {
            let model = model
            let token = token
            let event = event
            Task { @MainActor in
                model.removeObserver(token, for: event)
            }
        }
    }
    
    func subcriberCountForEvent(_ event: Event) -> Int {
        guard let subscriptions = observers[event] else { return 0 }
        return subscriptions.count
    }

    func lastSubcriptionTokenForEvent(_ event: Event) -> Int? {
        guard let subscriptions = observers[event] else { return nil }
        return subscriptions.keys.max()
    }
    
    private var observers: [Event: [Int: () -> Void]] = [:]
    @MainActor private static var observerIdCounters: [Event: Int] = [:]

    @MainActor
    func addObserver(for event: Event, onChange: @escaping () -> Void) -> Int {
        let token = Self.observerIdCounters[event, default: 0] + 1
        Self.observerIdCounters[event] = token
        observers[event, default: [:]][token] = onChange
        delegate?.modelDidAddSubscription(self, to: event)
        return token
    }

    @MainActor
    func removeObserver(_ token: Int, for event: Event) {
        observers[event]?[token] = nil
    }

    func notify(_ event: Event) {
        observers[event]?.values.forEach { $0() }
    }
}

extension Array where Element == NftDetailsItemModel {
    func findById(_ id: String) -> Element? {
        first { $0.id == id }
    }
    
    func getById(_ id: String) -> Element {
        guard let result = findById(id) else {
            fatalError("Unable to find NFT model for id: \(id)")
        }
        return result
    }
    
    func findIndexById(_ id: String) -> Int? {
        firstIndex(where: { $0.id == id })
    }
}
