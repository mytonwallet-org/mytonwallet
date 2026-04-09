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

    private let modelsIndexMap: [String: Int] // fast search
    
    let models: [ItemModel]
    private(set) var activeModelIndex: Int = 0

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
        processedImageCache.diskStorage.config.expiration = .days(10)

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
        guard model.processedImageState.isIdle else { return }

        // Mark loading, then probe disk cache asynchronously.
        model.processedImageState = .loading
        model.notify(.processedImageUpdated)

        let gen = generation
        tryLoadFromDiskCache(model: model, generation: gen) { [weak self] processed in
            guard let self, self.generation == gen else { return }
            guard case .loading = model.processedImageState else { return }

            if let processed {
                model.processedImageState = .loaded(processed)
                model.notify(.processedImageUpdated)
                return
            }

            guard let url = model.item.imageUrl else {
                // No URL — show placeholder without processing or caching; re-applied on every load.
                self.applyPlaceholder(model: model, image: NftDetailsImage.noImagePlaceholderImage())
                return
            }

            // 3. Disk miss — start Kingfisher download.
            self.startDownload(url: url, model: model, modelId: ObjectIdentifier(model), generation: gen)
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

    private func tryLoadFromDiskCache(model: ItemModel, generation: Int, completion: @escaping @Sendable (NftDetailsImage.Processed?) -> Void) {
        let bucket = WidthBucket(targetWidth)

        // Color cache is synchronous (in-memory after initial disk load). Check it before
        // touching disk so we bail cheaply when the entry was never written.
        guard colorCache.color(forKey: model.id) != nil else { completion(nil); return }

        // Sequential lookups: bail immediately on the first miss (the common case on first run
        // or after a bucket change), which is faster than launching all three in parallel.
        processedImageCache.retrieveImage(forKey: bucket.origCacheKey(id: model.id)) { [weak self] origResult in
            guard let self, self.generation == generation else { return }
            guard case .success(let r) = origResult, let orig = r.image else { completion(nil); return }

            self.processedImageCache.retrieveImage(forKey: bucket.previewCacheKey(id: model.id)) { [weak self] prevResult in
                guard let self, self.generation == generation else { return }
                guard case .success(let r) = prevResult, let prev = r.image else { completion(nil); return }

                self.processedImageCache.retrieveImage(forKey: bucket.bgCacheKey(id: model.id)) { [weak self] bgResult in
                    guard let self, self.generation == generation else { return }
                    guard case .success(let r) = bgResult, let bgImage = r.image else { completion(nil); return }

                    completion(self.buildProcessed(orig: orig, prev: prev, bg: bgImage, modelId: model.id))
                }
            }
        }
    }

    private func buildProcessed(orig: UIImage, prev: UIImage, bg: UIImage, modelId: String) -> NftDetailsImage.Processed {
        var processed = NftDetailsImage.Processed()
        processed.originalImage = orig
        processed.previewImage = prev
        processed.backgroundPattern = bg.cgImage.map { CIImage(cgImage: $0) }
        
        // UIColor.clear (alpha=0) is the sentinel for "processed, no detectable color";
        // treat it as nil so callers don't try to use a transparent color.
        let cached = colorCache.color(forKey: modelId)
        processed.baseColor = (cached.flatMap { $0.cgColor.alpha > 0 ? $0 : nil })
        return processed
    }

    private func startDownload(url: URL, model: ItemModel, modelId: ObjectIdentifier, generation: Int) {
        guard downloadTasks[modelId] == nil else { return }

        let task = KingfisherManager.shared.retrieveImage(with: url, options: [
            .memoryCacheExpiration(.expired),
            .requestModifier(AnyModifier { request in
                var r = request
                r.timeoutInterval = 60
                return r
            })
        ]) { [weak self] result in
            guard let self else { return }
            DispatchQueue.main.async {
                guard self.generation == generation else { return }
                self.downloadTasks.removeValue(forKey: modelId)
                guard case .loading = model.processedImageState else { return }

                switch result {
                case .success(let value):
                    self.enqueueForProcessing(model: model, rawImage: value.image)
                case .failure:
                    // Show error placeholder without processing or caching; forces a fresh
                    // network request on every subsequent load attempt.
                    self.applyPlaceholder(model: model, image: NftDetailsImage.errorPlaceholderImage())
                }
            }
        }
        if let task { downloadTasks[modelId] = task }
    }

    // Sets a minimal .loaded state with a placeholder image, bypassing the processing queue and
    // both caches entirely. After eviction the model returns to .idle and re-downloads/re-applies fresh.
    private func applyPlaceholder(model: ItemModel, image: UIImage) {
        guard case .loading = model.processedImageState else { return }
        var processed = NftDetailsImage.Processed()
        processed.originalImage = image
        processed.previewImage = image
        model.processedImageState = .loaded(processed)
        model.notify(.processedImageUpdated)
    }

    private func enqueueForProcessing(model: ItemModel, rawImage: UIImage) {
        guard case .loading = model.processedImageState else { return }
        guard !pendingModelIds.contains(model.id), pendingRawImages[model.id] == nil else { return }

        pendingRawImages[model.id] = rawImage
        pendingModelIds.append(model.id)
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

                let processed = self.imageProcessor.loadImage(
                    rawImage,
                    targetWidth: width,
                    simplifiedProcessing: model.simplifiedImageProcessing
                )

                guard !operation.isCancelled else { return }

                self.storeToCache(processed: processed, modelId: id, bucket: bucket)

                DispatchQueue.main.async { [weak self] in
                    guard let self, self.generation == gen else { return }
                    self.isProcessing = false
                    guard case .loading = model.processedImageState else {
                        self.drainQueue()
                        return
                    }
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
        if let bg = processed.backgroundPattern,
           let cgImage = imageProcessor.ciContext.createCGImage(bg, from: bg.extent, format: .RGBA8, colorSpace: CGColorSpaceCreateDeviceRGB()) {
            processedImageCache.store(UIImage(cgImage: cgImage), forKey: bucket.bgCacheKey(id: modelId), options: diskOnly)
        }
        // Always write the color entry so future lookups can distinguish "processed with no detectable color" (sentinel .clear, alpha=0) from
        // "never processed" (absent key). regionColor only returns colors with alpha >= 120/255, so alpha=0 is an unambiguous sentinel.
        colorCache.setColor(processed.baseColor ?? .clear, forKey: modelId)
    }
}

// MARK: - NftDetailsItemModelDelegate

extension NftDetailsManager: @MainActor NftDetailsItemModelDelegate {
    func modelDidRequestImage(_ model: ItemModel) {
        if targetWidth > 0 {
            startLoad(for: model)
        }
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
        let id = ObjectIdentifier(model)
        downloadTasks[id]?.cancel()
        downloadTasks.removeValue(forKey: id)

        pendingModelIds.removeAll { $0 == model.id }
        pendingRawImages.removeValue(forKey: model.id)

        model.processedImageState = .idle
        model.notify(.processedImageUpdated)
    }

    @MainActor
    func releaseImageResourcesOnMemoryWarning() {
        evictDistantModels(aroundIndex: activeModelIndex, keepRadius: 1)
    }
}
