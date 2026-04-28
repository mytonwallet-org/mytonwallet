import UIKit
import Kingfisher

/// Central download and processing hub for models.
final class NftDetailsManager: @unchecked Sendable {
    
    typealias ItemModel = NftDetailsItemModel

    /// targetWidth drives image processing dimensions. Setting it to a positive value starts any pending loads.
    /// Changing it to a different bucket (rounded up to the nearest 50 pt) invalidates all results and reprocesses.
    var targetWidth: CGFloat = 0 {
        didSet {
            guard targetWidth != oldValue, targetWidth > 0 else { return }
            let newBucket = WidthBucket(targetWidth)
            let oldBucketValue = oldValue > 0 ? WidthBucket(oldValue).value : 0
            if oldBucketValue > 0 && newBucket.value != oldBucketValue {
                invalidateAll()
            }
            startPendingLoads()
        }
    }
    let models: [ItemModel]
    private(set) var activeModelIndex: Int = 0
    private let modelsIndexMap: [String: Int] // fast search

    @MainActor
    func setActiveModel(_ model: ItemModel) {
        guard let idx = modelsIndexMap[model.id] else {
            assertionFailure()
            return
        }
        activeModelIndex = idx
        reprioritizePendingQueue()
        evictDistantModels(aroundIndex: idx)
    }

    // Incremented on every invalidation; stale async completions check this and bail.
    private var generation = 0
    
    private var downloadTasks: [ObjectIdentifier: DownloadTask] = [:]
    // Model ids waiting to be processed, in priority order (nearest active model first).
    private var pendingModelIds: [String] = []
    // Downloaded raw images keyed by model id, waiting for the processing queue.
    private var pendingRawImages: [String: UIImage] = [:]

    // Isolated HTTP downloads for cover-flow thumbnails; uses shared `ImageCache`. Cancelled when the manager is released.
    let coverFlowThumbnailDownloader: ImageDownloader
    let processedImageCache: ImageCache
    let colorCache = NftDetailsColorCache()

    // True while the serial processingQueue has a running operation.
    private var isProcessing = false

    private let imageProcessor: NftDetailsImageProcessor

    private let processingQueue: OperationQueue = {
        let q = OperationQueue()
        q.name = "NftDetails.imageProcessing"
        q.maxConcurrentOperationCount = 1   // serial — one Metal/CoreImage pass at a time
        q.qualityOfService = .utility
        return q
    }()

    @MainActor
    init(items: [NftDetailsItem]) {
        guard !items.isEmpty else { fatalError("NftDetailsItem array must not be empty") }

        coverFlowThumbnailDownloader = ImageDownloader(name: "NftDetails.coverFlow")
        coverFlowThumbnailDownloader.downloadTimeout = 60
        imageProcessor = NftDetailsImageProcessor()
        models = items.map { .init(item: $0) }
        modelsIndexMap = models.indexById()

        processedImageCache = ImageCache(name: "NftDetails.processed")
        processedImageCache.diskStorage.config.expiration = .days(7)
        processedImageCache.diskStorage.config.sizeLimit = 500 * 1024 * 1024
        processedImageCache.diskStorage.config.pathExtension = "png"
        processedImageCache.diskStorage.config.usesHashedFileName = false

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

    func saveColorCacheIfNeeded() {
        colorCache.saveIfNeeded()
    }

    private func invalidateAll() {
        generation += 1
        processingQueue.cancelAllOperations()
        isProcessing = false
        pendingModelIds.removeAll()
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
            traceModelActivity(model) { "Requested " }
        case .failed:
            traceModelActivity(model) { "Requested after failure" }
        case .loading:
            traceModelActivity(model) { "Requested, but another loading is in progress ⌛️" }
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
            
            await MainActor.run { [weak self] in
                guard let self, self.generation == gen else { return }
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
    }
    
    private struct WidthBucket {
        let value: Int

        // Rounds width up to the nearest 50 pt step so minor view-size fluctuations share one cache bucket. E.g. 370->400, 390->400, 401->450.
        init(_ width: CGFloat) {
           let window = 50
           value = Int((width / CGFloat(window)).rounded(.up)) * window
        }
                
        func origCacheKey(id: String) -> String { "\(id)_\(value)_original" }
        func previewCacheKey(id: String) -> String { "\(id)_\(value)_preview" }
        func bgCacheKey(id: String) -> String { "\(id)_\(value)_bg" }
    }

    private func tryLoadFromDiskCache(model: ItemModel, generation: Int) async -> NftDetailsImage.Processed? {
        let bucket = WidthBucket(targetWidth)
        let modelId = model.id
        
        // Color cache is synchronous (in-memory after initial disk load). Check it before
        // touching disk so we bail cheaply when the entry was never written.
        guard let cachedColor = colorCache.color(forKey: modelId) else { return nil }
        
        async let origResult  = processedImageCache.retrieveImage(forKey: bucket.origCacheKey(id: modelId))
        async let prevResult  = processedImageCache.retrieveImage(forKey: bucket.previewCacheKey(id: modelId))
        async let bgResult    = processedImageCache.retrieveImage(forKey: bucket.bgCacheKey(id: modelId))
        
        let orig = try? await origResult
        let prev = try? await prevResult
        let bgImage = try? await bgResult // this can be null for transparent backgrounds so we wont check the result
        guard generation == self.generation, let orig = orig?.image, let prev = prev?.image else {
            return nil
        }
        
        traceModelActivity(model) { "Restored from cache 🟢" }
        return NftDetailsImage.Processed(
            originalImage: orig,
            previewImage: prev,
            previewCIImage:  imageProcessor.ciImageOptional(from: prev),
            backgroundImage: bgImage?.image,
            backgroundCIImage: imageProcessor.ciImageOptional(from: bgImage?.image),
            baseColor: (cachedColor.alpha ?? 0) > 0 ? cachedColor : nil // (alpha=0) is the sentinel for "processed, no detectable color";
        )
    }
    
    private func getDownloadTaskId(_ model: ItemModel) -> ObjectIdentifier {
        ObjectIdentifier(model)
    }
    
    #if DEBUG
    private let traceEnabled = false
    @inline(__always) private func traceModelActivity(_ model: ItemModel, _ s: () -> String) {
        guard traceEnabled else { return }
        let modelIndex = modelsIndexMap[model.id] ?? -1
        print("[NftDetails] [\(modelIndex)] \(model): \(s())")
    }
    #else
    @inline(__always) private func traceModelActivity(_ model: ItemModel, _ s: () -> String) { }
    #endif

    private func startDownload(url: URL, model: ItemModel, generation: Int) {
        traceModelActivity(model) { "Start download 🟡" }
        let taskId = getDownloadTaskId(model)
        guard downloadTasks[taskId] == nil else {
            traceModelActivity(model) { "Already downloading" }
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
            
            traceModelActivity(model) { "Downloaded" }
            
            DispatchQueue.main.async {
                guard self.generation == generation else { return }
                self.downloadTasks.removeValue(forKey: taskId)
                guard case .loading = model.processedImageState else { return }

                switch result {
                case .success(let value):
                    self.enqueueForProcessing(model: model, rawImage: value.image)
                case .failure:
                    self.applyPlaceholder(model: model, image: NftDetailsImage.errorPlaceholderImage())
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
        
        guard case .loading = model.processedImageState else { return }
        guard !pendingModelIds.contains(modelId), pendingRawImages[modelId] == nil else { return }

        pendingRawImages[modelId] = rawImage
        pendingModelIds.append(modelId)
        reprioritizePendingQueue()
        drainQueue()
    }

    private func reprioritizePendingQueue() {
        guard pendingModelIds.count > 1 else { return }

        let active = activeModelIndex
        pendingModelIds.sort { a, b in
            let ia = modelsIndexMap[a] ?? Int.max
            let ib = modelsIndexMap[b] ?? Int.max
            return abs(ia - active) < abs(ib - active)
        }
    }

    private func drainQueue() {
        guard !isProcessing, targetWidth > 0 else { return }

        while !pendingModelIds.isEmpty {
            let id = pendingModelIds.removeFirst()
            guard let idx = modelsIndexMap[id] else {
                pendingRawImages.removeValue(forKey: id)
                continue
            }
            let model = models[idx]
            guard case .loading = model.processedImageState else {
                pendingRawImages.removeValue(forKey: id)
                continue
            }
            guard let rawImage = pendingRawImages.removeValue(forKey: id) else { continue }

            isProcessing = true
            let width = targetWidth
            let bucket = WidthBucket(width)
            let gen = generation
            let operation = BlockOperation()
            operation.addExecutionBlock { [weak self, weak operation] in
                guard let self, let operation, !operation.isCancelled else { return }
                
                traceModelActivity(model) { "Processing" }
                let processed = self.imageProcessor.loadImage(
                    rawImage,
                    targetWidth: width,
                    simplifiedProcessing: model.simplifiedImageProcessing
                )
                
                guard !operation.isCancelled else { return }
                
                traceModelActivity(model) {"Storing to cache" }
                storeToCache(processed: processed, modelId: id, bucket: bucket)

                DispatchQueue.main.async { [weak self] in
                    guard let self, self.generation == gen else { return }
                    self.isProcessing = false
                    guard case .loading = model.processedImageState else {
                        self.drainQueue()
                        return
                    }
                    traceModelActivity(model) { "Completed full pipeline 🔵" }
                    model.processedImageState = .loaded(processed)
                    model.notify(.processedImageUpdated)
                    self.drainQueue()
                }
            }
            processingQueue.addOperation(operation)
            return
        }
    }

    /// Called on the background processing thread. Both caches are thread-safe.
    private func storeToCache(processed: NftDetailsImage.Processed, modelId: String, bucket: WidthBucket) {
        // Store to disk only. model.processedImageState is the sole in-memory holder, so
        // evicting the model state immediately frees the pixel buffers — no double retention.
        let diskOnly = KingfisherParsedOptionsInfo([.memoryCacheExpiration(.expired)])
        if let orig = processed.originalImage {
            processedImageCache.store(orig, forKey: bucket.origCacheKey(id: modelId), options: diskOnly)
        }
        if let prev = processed.previewImage {
            processedImageCache.store(prev, forKey: bucket.previewCacheKey(id: modelId), options: diskOnly)
        }
        if let bg = processed.backgroundImage {
            processedImageCache.store(bg, forKey: bucket.bgCacheKey(id: modelId), options: diskOnly)
        }
        // Always write the color entry so future lookups can distinguish "processed with no detectable color" (sentinel .clear, alpha=0) from
        // "never processed" (absent key). regionColor only returns colors with alpha >= 120/255, so alpha=0 is an unambiguous sentinel.
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
    /// Evicts all models farther than `keepRadius` positions from `center`. Called on every active-model change so the in-memory footprint stays bounded
    /// at `keepRadius * 2 + 1` processed images regardless of collection size.
    @MainActor
    private func evictDistantModels(aroundIndex center: Int, keepRadius: Int = 5) {
        for (index, m) in models.enumerated() {
            guard abs(index - center) > keepRadius else { continue }
            guard case .loaded = m.processedImageState else { continue }
            releaseImageResources(for: m)
        }
    }

    @MainActor
    private func releaseImageResources(for model: ItemModel) {
        let taskId = getDownloadTaskId(model)
        downloadTasks[taskId]?.cancel()
        downloadTasks.removeValue(forKey: taskId)

        pendingModelIds.removeAll { $0 == model.id }
        pendingRawImages.removeValue(forKey: model.id)

        traceModelActivity(model) { "Evicted 🧹" }
        
        model.processedImageState = .idle
        model.notify(.processedImageUpdated)
    }

    @MainActor
    func releaseImageResourcesOnMemoryWarning() {
        evictDistantModels(aroundIndex: activeModelIndex, keepRadius: 1)
    }
}
