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
    let attributes: [Attribute]?
    let collection: Collection?
    let tonDomain: TonDomain?

    private let thumbnailUrlString: String?
    private let imageUrlString: String?
    private let lottieUrlString: String?

    var imageUrl: URL? {
        guard let urlString = imageUrlString?.nilIfEmpty, let url = URL(string: urlString) else { return nil }
        return url
    }
    
    var coverflowImageUrl: URL? {
        guard let urlString = thumbnailUrlString?.nilIfEmpty, let url = URL(string: urlString) else { return nil }
        return url
    }
    
    var lottieUrl: URL? {
        guard let s = lottieUrlString?.nilIfEmpty, let url = URL(string: s) else { return nil }
        return url
    }

    init(id: String, name: String, description: String?, thumbnailUrl: String?, imageUrl: String?,
         lottieUrl: String?, attributes: [Attribute]?, collection: Collection?, tonDomain: TonDomain?) {
        self.id = id
        self.name = name
        self.description = description
        self.thumbnailUrlString = thumbnailUrl
        self.imageUrlString = imageUrl
        self.lottieUrlString = lottieUrl
        self.attributes = attributes
        self.collection = collection
        self.tonDomain = tonDomain
    }
}

extension NftDetailsItem.TonDomain {
    var expirationText: String {
        if expirationDays < 0 {
            return lang("Expired")
        } else {
            let daysText = lang("$in_days", arg1: expirationDays)
            return lang("$one_domain_expires %days%", arg1: daysText)
        }
    }
}

protocol NftDetailsItemModelDelegate: AnyObject {
    func modelDidRequestImage(_  model: NftDetailsItemModel)
}

class NftDetailsItemModel: Identifiable, Equatable, @unchecked Sendable, CustomStringConvertible {

    enum Action: CaseIterable { case wear, send, share, more, showCollection, renewDomain }

    init(item: NftDetailsItem) {
        self.item = item
    }

    let item: NftDetailsItem
    var id: String { item.id }
    var name: String { item.name }
    
    /// A flag to not use blurring and overlays for image processing: Lottie will spoil it all.
    var simplifiedImageProcessing: Bool { item.lottieUrl != nil }

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
    
    var description: String {  return "<Model '\(name)' \(processedImageState)>" }

    static func == (lhs: NftDetailsItemModel, rhs: NftDetailsItemModel) -> Bool { lhs === rhs } // Reference equality only
    
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

    private var observers: [Event: [Int: () -> Void]] = [:]
    @MainActor private static var observerIdCounters: [Event: Int] = [:]

    @MainActor
    func addObserver(for event: Event, onChange: @escaping () -> Void) -> Int {
        let token = Self.observerIdCounters[event, default: 0] + 1
        Self.observerIdCounters[event] = token
        observers[event, default: [:]][token] = onChange
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

    /// Prepare a fast lookup dictionary `[id → index]`
    func indexById() -> [String: Int] {
        var map = [String: Int](minimumCapacity: count)
        for (i, model) in enumerated() { map[model.id] = i }
        return map
    }
}
