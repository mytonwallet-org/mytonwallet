import Foundation
import WalletCore

actor MintCardVideoCache {
    static let shared = MintCardVideoCache()

    typealias Download = @Sendable (URL) async throws -> Data
    private let directory: URL
    private let download: Download
    private var requests: [ApiMtwCardType: Task<URL?, Never>] = [:]

    init(directory: URL = URL.cachesDirectory.appending(path: "air/mint-cards-v1", directoryHint: .isDirectory),
         download: @escaping Download = MintCardVideoCache.downloadVideo) {
        self.directory = directory
        self.download = download
    }

    func fileURL(for type: ApiMtwCardType, priority: TaskPriority = .userInitiated) async -> URL? {
        let file = directory.appendingPathComponent("\(type.rawValue).mp4")
        let modified = try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
        if let modified, Date().timeIntervalSince(modified) < 24 * 60 * 60 { return file }
        if let request = requests[type] { return await request.value }
        guard let source = MintCardTypeInfo.ordered.first(where: { $0.type == type })?.videoURL else { return nil }
        let request = Task.detached(priority: priority) { [directory, download] () -> URL? in
            do {
                let data = try await download(source)
                guard !data.isEmpty else { throw URLError(.zeroByteResource) }
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                try data.write(to: file, options: .atomic)
                return file
            } catch {
                // An older cached movie is preferable to an empty hero when offline.
                return FileManager.default.fileExists(atPath: file.path) ? file : nil
            }
        }
        requests[type] = request
        let result = await request.value
        requests[type] = nil
        return result
    }

    func preloadNeighbors(of page: Int) async {
        await withTaskGroup(of: Void.self) { group in
            for offset in [-1, 1] {
                let type = MintCardTypeInfo.at(page: page + offset).type
                group.addTask { _ = await self.fileURL(for: type, priority: .utility) }
            }
        }
    }

    private static func downloadVideo(_ url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let response = response as? HTTPURLResponse, response.statusCode == 200,
              response.mimeType == "video/mp4" else { throw URLError(.badServerResponse) }
        return data
    }
}
