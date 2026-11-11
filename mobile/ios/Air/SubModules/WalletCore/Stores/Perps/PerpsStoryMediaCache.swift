import CryptoKit
import Foundation

/// Keeps the Perps onboarding clips and their previews on disk, so stories open without waiting for the network.
public actor PerpsStoryMediaCache {
    public static let shared = PerpsStoryMediaCache()

    public enum Kind: Sendable {
        case preview, video

        var mimeType: String {
            switch self {
            case .preview: "image/webp"
            case .video: "video/mp4"
            }
        }
    }

    public typealias Download = @Sendable (URL, Kind) async throws -> Data
    private let directory: URL
    private let download: Download
    private var requests: [URL: Task<URL?, Never>] = [:]
    private var prefetchGeneration = UUID()

    public init(directory: URL = URL.cachesDirectory.appending(path: "air/perps-stories-v1", directoryHint: .isDirectory),
                download: @escaping Download = PerpsStoryMediaCache.downloadFile) {
        self.directory = directory
        self.download = download
    }

    /// Only the latest prefetch may schedule more clips or prune files; completion requires every file on disk
    @discardableResult
    public func prefetch(_ stories: [ApiPerpsOnboardingStory]) async -> Bool {
        let generation = UUID()
        prefetchGeneration = generation
        await withTaskGroup(of: Void.self) { group in
            for story in stories {
                group.addTask { _ = await self.file(for: story.preview, kind: .preview) }
            }
        }
        for story in stories {
            guard prefetchGeneration == generation else { return false }
            _ = await file(for: story.url, kind: .video)
        }
        guard prefetchGeneration == generation else { return false }
        removeFiles(except: Set(stories.flatMap { [fileURL(for: $0.preview), fileURL(for: $0.url)] }))
        return stories.allSatisfy { cachedFile(for: $0.preview) != nil && cachedFile(for: $0.url) != nil }
    }

    public func file(for url: URL, kind: Kind) async -> URL? {
        let file = fileURL(for: url)
        if FileManager.default.fileExists(atPath: file.path) { return file }
        if let request = requests[url] { return await request.value }
        let request = Task.detached(priority: .utility) { [directory, download] () -> URL? in
            do {
                let data = try await download(url, kind)
                guard !data.isEmpty else { throw URLError(.zeroByteResource) }
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                try data.write(to: file, options: .atomic)
                return file
            } catch {
                return nil
            }
        }
        requests[url] = request
        let result = await request.value
        requests[url] = nil
        return result
    }

    /// A file iOS purged from Caches reads as not downloaded.
    public nonisolated func cachedFile(for url: URL) -> URL? {
        let file = fileURL(for: url)
        return FileManager.default.fileExists(atPath: file.path) ? file : nil
    }

    // Every clip lives under a content-hashed URL, so a file is valid for as long as its URL is current.
    nonisolated func fileURL(for url: URL) -> URL {
        let digest = SHA256.hash(data: Data(url.absoluteString.utf8)).prefix(16).map { String(format: "%02x", $0) }.joined()
        return directory.appendingPathComponent(digest).appendingPathExtension(url.pathExtension)
    }

    private func removeFiles(except kept: Set<URL>) {
        let keptNames = Set(kept.map(\.lastPathComponent))
        guard let files = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else { return }
        for file in files where !keptNames.contains(file.lastPathComponent) {
            try? FileManager.default.removeItem(at: file)
        }
    }

    public static func downloadFile(_ url: URL, kind: Kind) async throws -> Data {
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.allowsConstrainedNetworkAccess = kind == .preview
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let response = response as? HTTPURLResponse, response.statusCode == 200,
              response.mimeType == kind.mimeType else { throw URLError(.badServerResponse) }
        return data
    }
}
