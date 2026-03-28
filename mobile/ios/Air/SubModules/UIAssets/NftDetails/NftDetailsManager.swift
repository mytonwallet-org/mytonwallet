import UIKit
import Kingfisher

/// Central download and processing hub for models.
final class NftDetailsManager: @unchecked Sendable {
    let models: [NftDetailsItemModel]
    
    private var subscriptionCheckingCounter = 0
    private var downloadTasks: [ObjectIdentifier: DownloadTask] = [:]
    private let imageProcessor: NftDetailsImageProcessor
    private var processingOperations: [ObjectIdentifier: Operation] = [:]
    private let processingQueue: OperationQueue = {
        let q = OperationQueue()
        q.name = "NftDetailsManager.processing"
        q.maxConcurrentOperationCount = 3
        q.qualityOfService = .userInitiated
        return q
    }()

    /// targetWidth drives image processing dimensions. Setting it to a positive value starts any pending loads.
    /// Changing it to a different positive value invalidates all results and reprocesses.
    var targetWidth: CGFloat = 0 {
        didSet {
            guard targetWidth != oldValue, targetWidth > 0 else { return }
            if oldValue > 0 {
                invalidateAll()
            }
            startPendingLoads()
        }
    }

    @MainActor
    init(items: [NftDetailsItem]) {
        guard !items.isEmpty else { fatalError("NftDetailsItem array must not be empty") }
        
        self.imageProcessor = NftDetailsImageProcessor()
        self.models = items.map { .init(item: $0) }
        models.forEach { $0.delegate = self }
    }

    private func invalidateAll() {
        processingQueue.cancelAllOperations()
        processingOperations.removeAll()

        for (_, task) in downloadTasks { task.cancel() }
        downloadTasks.removeAll()

        for model in models {
            model.processedImageState = .idle
            model.notify(.processedImageUpdated)
        }
    }

    private func startPendingLoads() {
        for model in models {
            if model.subcriberCountForEvent(.processedImageUpdated) > 0 {
                startLoad(for: model)
            }
        }
    }
        
    /// Pipeline: loading → Kingfisher (memory/disk cache) → process → loaded. Duplicate fetches are cheap when cached.
    private func startLoad(for model: NftDetailsItemModel) {
        guard let urlString = model.item.thumbnailUrl, let url = URL(string: urlString) else { return }

        if case .loaded = model.processedImageState { return }

        let modelId = ObjectIdentifier(model)
        guard downloadTasks[modelId] == nil, processingOperations[modelId] == nil else {
            return
        }
        
        model.processedImageState = .loading
        model.notify(.processedImageUpdated)
        let task = KingfisherManager.shared.retrieveImage(with: url) { [weak self] result in
            guard let self else { return }
            
            DispatchQueue.main.async {
                self.downloadTasks.removeValue(forKey: modelId)
                let image: UIImage
                switch result {
                case .success(let value):
                    image = value.image
                case .failure:
                    image = NftDetailsImage.errorPlaceholderImage()
                }
                self.enqueueProcessing(rawImage: image, model: model, modelId: modelId)
            }
        }

        if let task {
            downloadTasks[modelId] = task
        }
    }

    private func enqueueProcessing(rawImage: UIImage, model: NftDetailsItemModel, modelId: ObjectIdentifier) {
        guard targetWidth > 0 else { return }

        if processingOperations[modelId] != nil { return }
        if case .loaded = model.processedImageState { return }

        let width = targetWidth
        let operation = BlockOperation()
        operation.addExecutionBlock { [weak self, weak operation] in
            guard let self, let operation, !operation.isCancelled else { return }

            let processed = self.imageProcessor.loadImage(
                rawImage,
                targetWidth: width,
                simplifiedProcessing: model.simplifiedImageProcessing
            )
            
            guard !operation.isCancelled else { return }

            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.processingOperations.removeValue(forKey: modelId)
                guard case .loading = model.processedImageState else { return }
                model.processedImageState = .loaded(processed)
                model.notify(.processedImageUpdated)
            }
        }

        processingOperations[modelId] = operation
        processingQueue.addOperation(operation)
    }
}

extension NftDetailsManager: @MainActor NftDetailsItemModelDelegate {
    func modelDidRequestImage(_  model: NftDetailsItemModel) {
        if targetWidth > 0 {
            startLoad(for: model)
        }
    }
    
    @MainActor
    func modelDidAddSubscription(_  model: NftDetailsItemModel, to event: NftDetailsItemModel.Event) {
        // We currently interested in cleaning for images only. Track a counter to check it from time to time
        guard event == .processedImageUpdated else { return }
        subscriptionCheckingCounter += 1
        guard subscriptionCheckingCounter > 10 else { return }
        subscriptionCheckingCounter = 0
                        
        let items: [(NftDetailsItemModel, Int)] = models.compactMap { model in
            guard case .loaded = model.processedImageState else { return nil }
            let lastToken = model.lastSubcriptionTokenForEvent(.processedImageUpdated) ?? 0
            return (model, lastToken)
        }.sorted { a, b in b.1 < a.1 }
        
        let itemsToLeft = 10
        items.dropFirst(itemsToLeft).enumerated().forEach { _, e in
            releaseImageResources(for: e.0)
        }
    }
}

extension NftDetailsManager {
    @MainActor
    private func releaseImageResources(for model: NftDetailsItemModel) {
        let id = ObjectIdentifier(model)
        downloadTasks[id]?.cancel()
        downloadTasks.removeValue(forKey: id)
        processingOperations[id]?.cancel()
        processingOperations.removeValue(forKey: id)

        model.processedImageState = .idle
        model.notify(.processedImageUpdated)
    }

    @MainActor
    func releaseImageResources(keepingModelsAround model: NftDetailsItemModel) {
        let modelIndex = models.findIndexById(model.id) ?? Int.max
        for (index, model) in models.enumerated() {
            if index < modelIndex - 1 || index > modelIndex + 1 {
                releaseImageResources(for: model)
            }
        }
    }
}
