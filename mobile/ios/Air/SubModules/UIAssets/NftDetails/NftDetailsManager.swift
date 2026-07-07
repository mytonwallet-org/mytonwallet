import UIKit
import Kingfisher

@MainActor
final class NftDetailsManager {
    
    typealias ItemModel = NftDetailsItemModel

    /// `targetWidth` drives image processing dimensions. Setting it to a positive value starts any pending loads.
    /// Changing it to a different bucket (rounded up to the nearest 50 pt) invalidates all results and reprocesses.
    var targetWidth: CGFloat = 0 {
        didSet {
            guard targetWidth != oldValue, targetWidth > 0 else { return }
            let newBucket = WidthBucket(targetWidth)
            let oldBucket = WidthBucket(oldValue)
            if oldBucket.value > 0 && newBucket != oldBucket {
                invalidateAll()
            }
            startPendingLoads()
        }
    }
    
    private(set) var models: [ItemModel]
    
    private(set) var activeModelIndex: Int = 0
    
    func setActiveModel(_ model: ItemModel) {
        let idx = model.index
        activeModelIndex = idx
        reprioritizePendingQueue()
        evictDistantModels(aroundIndex: idx)
    }

    @discardableResult
    func removeModel(id: String) -> [ItemModel] {
        guard let removeIdx = models.firstIndex(where: { $0.id == id }) else {
            return models
        }
        let model = models[removeIdx]

        // Cancel/clean all in-flight state for the removed model.
        // Any background processing operation still in flight will no-op: its completion guards on
        // `case .loading`, and `cleanupModel` resets the removed model to `.idle`.
        cleanupModel(model)

        // Remove and reindex the survivors so positional math (offsets, prefetch, eviction) stays valid.
        // The pending queue holds model references, so it needs no remapping here.
        models.remove(at: removeIdx)
        for (i, m) in models.enumerated() { m.index = i }

        // Keep the active index pointing at the same active model: shift it down if an earlier item
        // was removed, then clamp to the new bounds.
        if removeIdx < activeModelIndex { activeModelIndex -= 1 }
        activeModelIndex = models.isEmpty ? 0 : min(max(0, activeModelIndex), models.count - 1)

        return models
    }

    /// Rebuilds the model list to match `newItems`, preserving existing model instances (and their
    /// image-pipeline state) by id while creating fresh models for newly inserted ids. Models that
    /// are no longer present have their in-flight work cancelled. Order follows `newItems`.
    @discardableResult
    func reconcile(toItems newItems: [NftDetailsItem]) -> [ItemModel] {
        let existingById = Dictionary(models.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let newIds = Set(newItems.map(\.id))

        // Cancel/clean in-flight work for models that are leaving.
        for model in models where !newIds.contains(model.id) {
            cleanupModel(model)
        }

        // Remember the currently active model so we can keep it focused after reindexing.
        let activeId = models.indices.contains(activeModelIndex) ? models[activeModelIndex].id : nil

        var newModels: [ItemModel] = []
        newModels.reserveCapacity(newItems.count)
        for (i, item) in newItems.enumerated() {
            if let existing = existingById[item.id] {
                existing.index = i
                newModels.append(existing)
            } else {
                let model = ItemModel(item: item, index: i)
                model.delegate = self
                model.displayStateProvider = displayStateProvider
                newModels.append(model)
            }
        }
        models = newModels

        if let activeId, let idx = models.firstIndex(where: { $0.id == activeId }) {
            activeModelIndex = idx
        } else {
            activeModelIndex = models.isEmpty ? 0 : min(max(0, activeModelIndex), models.count - 1)
        }

        return models
    }

    /// Cancels downloads / pending processing for a model and resets it to `.idle` so any in-flight
    /// background operation no-ops on completion.
    private func cleanupModel(_ model: ItemModel) {
        let taskId = getDownloadTaskId(model)
        downloadTasks[taskId]?.cancel()
        downloadTasks.removeValue(forKey: taskId)
        pendingRawImages.removeValue(forKey: model.id)
        pendingModels.removeAll { $0 === model }
        model.processedImageState = .idle
    }

    private var generation = 0
    private var downloadTasks: [ObjectIdentifier: DownloadTask] = [:]
    private var pendingModels: [ItemModel] = []
    private var pendingRawImages: [String: UIImage] = [:]

    let coverFlowThumbnailDownloader: ImageDownloader
    let processedImageCache: ImageCache
    let colorCache = NftDetailsColorCache()
    let colorResolver: NftDetailsColorResolver

    @MainActor private weak var displayStateProvider: NftDetailsDisplayStateProviding?

    private let imageProcessor: NftDetailsImageProcessor
    private var isImageQueueProcessing = false
    private let imageProcessingQueue: OperationQueue = {
        let q = OperationQueue()
        q.name = "NftDetails.imageProcessing"
        q.maxConcurrentOperationCount = 1   // serial — one Metal/CoreImage pass at a time
        q.qualityOfService = .utility
        return q
    }()

    init(items: [NftDetailsItem]) {
        guard !items.isEmpty else { fatalError("NftDetailsItem array must not be empty") }

        coverFlowThumbnailDownloader = ImageDownloader(name: "NftDetails.coverFlow")
        coverFlowThumbnailDownloader.downloadTimeout = 60

        colorResolver = NftDetailsColorResolver(colorCache: colorCache)
        
        imageProcessor = NftDetailsImageProcessor()
        
        processedImageCache = ImageCache(name: "NftDetails.processed")
        processedImageCache.diskStorage.config.expiration = .days(7)
        processedImageCache.diskStorage.config.sizeLimit = 500 * 1024 * 1024
        processedImageCache.diskStorage.config.pathExtension = "png"
        processedImageCache.diskStorage.config.usesHashedFileName = false

        models = items.enumerated().map { .init(item: $0.1, index: $0.0) }
        models.forEach { $0.delegate = self }

        #if DEBUG
        do {
            let colorCache = self.colorCache
            let cache = self.processedImageCache
            Task.detached(priority: .background) {
                let url = cache.diskStorage.directoryURL
                cache.calculateDiskStorageSize { result in
                    var items: [String] = [""]
                    
                    let size = (try? result.get()).map { "\($0 / 1024) KB" } ?? "unknown"
                    items.append("Images: \(url.path) (\(size))")
                    
                    let colorStats = colorCache.debugStats()
                    items.append("Colors: \(colorStats.fileURL) (\(colorStats.keyCount) colors)")
                    print("[NftDetails] Cache {\(items.joined(separator: "\n  "))\n}")
                }
            }
        }
        #endif
    }

    deinit {
        coverFlowThumbnailDownloader.cancelAll()
    }

    func setDisplayStateProvider(_ provider: NftDetailsDisplayStateProviding) {
        displayStateProvider = provider
        models.forEach { $0.displayStateProvider = provider }
    }

    func notifyDisplayStateChanged() {
        models.forEach { $0.notify(.displayStateChanged) }
    }
    
    private func invalidateAll() {
        generation += 1
        imageProcessingQueue.cancelAllOperations()
        isImageQueueProcessing = false
        pendingModels.removeAll()
        pendingRawImages.removeAll()

        for (_, task) in downloadTasks { task.cancel() }
        downloadTasks.removeAll()

        for model in models {
            model.processedImageState = .idle
            model.notify(.processedImageUpdated)
        }
    }

    private func startPendingLoads() {
        let active = activeModelIndex
        let sorted = models.enumerated()
            .filter { $0.element.subcriberCountForEvent(.processedImageUpdated) > 0 }
            .sorted { abs($0.offset - active) < abs($1.offset - active) }
            .map(\.element)
        for model in sorted {
            startLoad(for: model)
        }
    }

    // Pipeline entry point: model state (in-memory) -> disk cache -> download -> serial process.
    // If the model is already .loaded, the isIdle guard below is the fast path — no work done.
    private func startLoad(for model: ItemModel) {
        
        guard targetWidth > 0 else { return }
        
        switch model.processedImageState {
        case .idle:
            traceModelActivity(model, "Requested ")
        case .failed:
            traceModelActivity(model, "Requested after failure")
        case .loading:
            traceModelActivity(model, "Requested, but another loading is in progress ⌛️")
            return
        case .loaded:
            return
        }

        // Mark loading, then probe disk cache asynchronously.
        model.processedImageState = .loading
        model.notify(.processedImageUpdated)
        let gen = generation
        Task { [weak self] in
            guard let self else { return }

            let processed = await self.tryLoadFromDiskCache(model: model, generation: gen)

            guard self.generation == gen else { return }
            guard case .loading = model.processedImageState else { return }

            if let processed {
                model.processedImageState = .loaded(processed)
                model.notify(.processedImageUpdated)
                return
            }

            // No URL — show placeholder without processing or caching; re-applied on every load.
            guard let url = model.item.imageUrl else {
                self.applyPlaceholder(model: model, image: NftDetailsImage.noImagePlaceholderImage())
                return
            }

            // Disk miss — start Kingfisher download.
            self.startDownload(url: url, model: model, generation: gen)
        }
    }
    
    private struct WidthBucket: Equatable {
        let value: Int

        // Rounds width up to the nearest 50 pt step so minor view-size fluctuations share one cache bucket. E.g. 370->400, 390->400, 401->450.
        init(_ width: CGFloat) {
           let window = 50
           value = Int((width / CGFloat(window)).rounded(.up)) * window
        }
                
        func origCacheKey(id: String) -> String { "\(id)_\(value)_original" }
        func previewCacheKey(id: String) -> String { "\(id)_\(value)_preview" }
    }

    private func tryLoadFromDiskCache(model: ItemModel, generation: Int) async -> NftDetailsImage.Processed? {
        let bucket = WidthBucket(targetWidth)
        let modelId = model.id
        
        let m = NftDetailsPerformance.beginMeasure("kf_load_from_cache", threshold: 40, tag: model.shortDescription)
        defer { NftDetailsPerformance.endMeasure(m) }
        
        let (hasColor, baseColor) = colorCache.color(forKey: modelId)
        guard hasColor else { return nil }
        
        async let origResult  = processedImageCache.retrieveImage(forKey: bucket.origCacheKey(id: modelId))
        async let prevResult  = processedImageCache.retrieveImage(forKey: bucket.previewCacheKey(id: modelId))
        
        let orig = try? await origResult
        let prev = try? await prevResult
        guard generation == self.generation, let orig = orig?.image, let prev = prev?.image else {
            return nil
        }
        
        traceModelActivity(model, "Restored from cache 🟢")
        return NftDetailsImage.Processed(
            originalImage: orig,
            previewImage: prev,
            previewCIImage: imageProcessor.ciImageOptional(from: prev),
            baseColor: baseColor,
        )
    }
    
    private func getDownloadTaskId(_ model: ItemModel) -> ObjectIdentifier {
        ObjectIdentifier(model)
    }
        
    private func startDownload(url: URL, model: ItemModel, generation: Int) {
        traceModelActivity(model, "Start download 🟡")
        let taskId = getDownloadTaskId(model)
        guard downloadTasks[taskId] == nil else {
            traceModelActivity(model, "Already downloading")
            return
        }

        let task = KingfisherManager.shared.retrieveImage(with: url, options: [
            .cacheMemoryOnly,
            .memoryCacheExpiration(.expired),
            .requestModifier(AnyModifier { request in
                var r = request
                r.timeoutInterval = 60
                return r
            })
        ]) { [weak self] result in
            guard let self else { return }
            
            traceModelActivity(model, "Downloaded")
            
            DispatchQueue.main.async {
                guard self.generation == generation else { return }
                self.downloadTasks.removeValue(forKey: taskId)
                guard case .loading = model.processedImageState else { return }

                switch result {
                case .success(let value):
                    self.enqueueForProcessing(model: model, rawImage: value.image)
                case .failure:
                    let image = NftDetailsImage.noImagePlaceholderImage()
                    self.applyPlaceholder(model: model, image: image)
                }
            }
        }
        if let task {
            downloadTasks[taskId] = task
        }
    }

    private func applyPlaceholder(model: ItemModel, image: UIImage) {
        guard case .loading = model.processedImageState else { return }
        var processed = NftDetailsImage.Processed()
        processed.originalImage = image
        processed.previewImage = image
        processed.previewCIImage = imageProcessor.ciImageOptional(from: image)
        model.processedImageState = .loaded(processed)
        model.notify(.processedImageUpdated)
    }

    private func enqueueForProcessing(model: ItemModel, rawImage: UIImage) {
        let modelId = model.id

        guard !pendingModels.contains(where: { $0 === model }), pendingRawImages[modelId] == nil else { return }

        pendingRawImages[modelId] = rawImage
        pendingModels.append(model)
        reprioritizePendingQueue()
        drainQueue()
    }

    private func reprioritizePendingQueue() {
        guard pendingModels.count > 1 else { return }

        let active = activeModelIndex
        pendingModels.sort { a, b in
            return abs(a.index - active) < abs(b.index - active)
        }
    }

    private func drainQueue() {
        guard !isImageQueueProcessing, targetWidth > 0 else { return }

        while !pendingModels.isEmpty {
            let model = pendingModels.removeFirst()
            let id = model.id
            guard case .loading = model.processedImageState else {
                pendingRawImages.removeValue(forKey: id)
                continue
            }
            guard let rawImage = pendingRawImages.removeValue(forKey: id) else { continue }

            isImageQueueProcessing = true
            let width = targetWidth
            let bucket = WidthBucket(width)
            let gen = generation
            let processor = imageProcessor
            let pCache = processedImageCache
            let cCache = colorCache
            let operation = BlockOperation()
            operation.addExecutionBlock { [weak self, weak operation] in
                guard let operation else { return }
                
                guard !operation.isCancelled else { return }
                traceModelActivity(model, "Processing")
                let processed = processor.loadImage(
                    rawImage,
                    targetWidth: width,
                    simplifiedProcessing: model.simplifiedImageProcessing
                )
                
                guard !operation.isCancelled else { return }
                traceModelActivity(model, "Storing to cache")
                Self.storeToCache(processed: processed, modelId: id, bucket: bucket, imageCache: pCache, colorCache: cCache)

                guard !operation.isCancelled else { return }
                DispatchQueue.main.async { [weak self] in
                    guard let self, self.generation == gen else { return }
                    self.isImageQueueProcessing = false
                    guard case .loading = model.processedImageState else {
                        self.drainQueue()
                        return
                    }
                    traceModelActivity(model, "Completed full pipeline 🔵")
                    model.processedImageState = .loaded(processed)
                    model.notify(.processedImageUpdated)
                    self.drainQueue()
                }
            }
            imageProcessingQueue.addOperation(operation)
            break
        }
    }

    /// Called on the background processing thread. Both caches are thread-safe.
    nonisolated private static func storeToCache(processed: NftDetailsImage.Processed, modelId: String, bucket: WidthBucket,
                                                 imageCache: ImageCache, colorCache: NftDetailsColorCache) {
        // Store to disk only. model.processedImageState is the sole in-memory holder, so
        // evicting the model state immediately frees the pixel buffers — no double retention.
        let diskOnly = KingfisherParsedOptionsInfo([.memoryCacheExpiration(.expired)])
        if let orig = processed.originalImage {
            imageCache.store(orig, forKey: bucket.origCacheKey(id: modelId), options: diskOnly)
        }
        if let prev = processed.previewImage {
            imageCache.store(prev, forKey: bucket.previewCacheKey(id: modelId), options: diskOnly)
        }
        // Always write the color entry so future lookups can distinguish "processed with no detectable color"
        // (sentinel .clear, alpha=0) from "never processed" (absent key). imageProcessor.regionColor only
        // returns colors with alpha >= 120/255, so alpha=0 is an unambiguous sentinel.
        colorCache.setColor(processed.baseColor ?? .clear, forKey: modelId)
    }
}

// MARK: - NftDetailsItemModelDelegate

extension NftDetailsManager: @MainActor NftDetailsItemModelDelegate {
    func modelDidRequestImage(_ model: ItemModel) {
        startLoad(for: model)
    }
}

// MARK: - Memory Management

extension NftDetailsManager {
    private func evictDistantModels(aroundIndex center: Int, keepRadius: Int = 5) {
        for (index, m) in models.enumerated() {
            guard abs(index - center) > keepRadius else { continue }
            guard case .loaded = m.processedImageState else { continue }
            releaseImageResources(for: m)
        }
    }

    private func releaseImageResources(for model: ItemModel) {
        let taskId = getDownloadTaskId(model)
        downloadTasks[taskId]?.cancel()
        downloadTasks.removeValue(forKey: taskId)

        pendingModels.removeAll { $0 === model }
        pendingRawImages.removeValue(forKey: model.id)

        traceModelActivity(model, "Evicted 🧹")
        
        model.processedImageState = .idle
        model.notify(.processedImageUpdated)
    }

    func releaseImageResourcesOnMemoryWarning() {
        evictDistantModels(aroundIndex: activeModelIndex, keepRadius: 1)
    }
}

#if DEBUG
private let traceEnabled = false

@inline(__always) nonisolated private func traceModelActivity(_ model: NftDetailsItemModel, _ s: @autoclosure () -> String) {
    guard traceEnabled else { return }
    print("[NftDetails] \(model): \(s())")
}
#else
@inline(__always) nonisolated private func traceModelActivity(_ model: NftDetailsItemModel, _ s: @autoclosure () -> String) { }
#endif
