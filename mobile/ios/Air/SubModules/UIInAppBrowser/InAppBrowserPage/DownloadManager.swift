import ObjectiveC
import UIKit
import UIComponents
import WebKit
import WalletContext

private var log = Log("DownloadManager")

final class DownloadManager: NSObject, UIDocumentPickerDelegate {
    private weak var presentingViewController: UIViewController?
    private var downloads: [SingleDownload] = []
    private var activeNetworkFetchCount = 0
    private var overlayView: UIView?
    
    init(presentingViewController: UIViewController) {
        self.presentingViewController = presentingViewController
        super.init()
    }
    
    func handleNavigationResponse(_ navigationResponse: WKNavigationResponse, webView: WKWebView) -> Bool {
        guard let url = navigationResponse.response.url, let fileInfo = shouldDownload(for: url, navigationResponse: navigationResponse) else {
            return false
        }
        
        let download = SingleDownload(delegate: self)
        downloads.append(download)
        download.start(from: url, to: fileInfo, webView: webView)
        return true
    }
    
    private func matchFile(_ urlString: String, _ mimeType: String?, ext: String?, mimeTypes: [String]) -> Bool {
        if let mimeType {
            return mimeTypes.contains(mimeType)
        }
        if let ext {
            return urlString.lowercased().hasSuffix(ext)
        }
        return false
    }
    
    private func suggestedFilename(_ navigationResponse: WKNavigationResponse, _ url: URL, _ defaultFileName: String) -> String {
        var result: String?
        
        if let httpResponse = navigationResponse.response as? HTTPURLResponse,
           let disposition = httpResponse.value(forHTTPHeaderField: "Content-Disposition"),
           let filenameRange = disposition.range(of: "filename="),
           let rest = disposition[filenameRange.upperBound...].split(separator: ";").first {
            var name = rest.trimmingCharacters(in: .whitespaces)
            if name.hasPrefix("\"") && name.hasSuffix("\"") {
                name = String(name.dropFirst().dropLast())
            }
            result = name.nilIfEmpty
        }
        
        if result == nil {
            result = url.lastPathComponent.nilIfEmpty
        }
        
        // Sanitize the filename to prevent potential security issues
        let invalidChars = CharacterSet(charactersIn: "/\\:*?\"<>|")
        result = result?.components(separatedBy: invalidChars).joined(separator: "_")
        
        return result ?? defaultFileName
    }
    
    private func shouldDownload(for url: URL, navigationResponse: WKNavigationResponse) -> DestinationFileInfo? {
        guard let urlString = navigationResponse.response.url?.absoluteString.lowercased().nilIfEmpty else {
            assertionFailure()
            return nil
        }
        let mimeType = (navigationResponse.response.mimeType ?? "").lowercased().nilIfEmpty
        
        // CSV
        if matchFile(urlString, mimeType, ext: ".csv", mimeTypes: ["text/csv", "application/csv"]) {
            return .init(fileName: suggestedFilename(navigationResponse, url, "data.csv"))
        }
        
        return nil
    }
    
    private func removeDownload(_ download: SingleDownload) {
        downloads.removeAll { $0 === download }
    }
    
    private func showOverlayIfNeeded() {
        guard activeNetworkFetchCount > 0, overlayView == nil, let vc = presentingViewController else { return }
        
        let overlay = UIView()
        overlay.backgroundColor = UIColor.black.withAlphaComponent(0.2)
        overlay.isUserInteractionEnabled = false
        overlay.alpha = 0
        overlay.translatesAutoresizingMaskIntoConstraints = false
        
        let indicator = WActivityIndicator()
        indicator.tintColor = .white
        overlay.addSubview(indicator)
        
        vc.view.addSubview(overlay)
        NSLayoutConstraint.activate([
            overlay.topAnchor.constraint(equalTo: vc.view.topAnchor),
            overlay.leadingAnchor.constraint(equalTo: vc.view.leadingAnchor),
            overlay.trailingAnchor.constraint(equalTo: vc.view.trailingAnchor),
            overlay.bottomAnchor.constraint(equalTo: vc.view.bottomAnchor),
            indicator.centerXAnchor.constraint(equalTo: overlay.centerXAnchor),
            indicator.centerYAnchor.constraint(equalTo: overlay.centerYAnchor)
        ])
        overlayView = overlay
        indicator.startAnimating(animated: false)
        UIView.animate(withDuration: 0.25) {
            overlay.alpha = 1
        }
    }
    
    private func hideOverlayIfNeeded() {
        guard activeNetworkFetchCount == 0, let overlay = overlayView else { return }
        overlayView = nil
        UIView.animate(withDuration: 0.25, animations: {
            overlay.alpha = 0
        }) { _ in
            overlay.removeFromSuperview()
        }
    }
    
    private func presentDocumentPicker(for fileUrl: URL, onDismiss: @escaping () -> Void) {
        guard let vc = presentingViewController else {
            onDismiss()
            return
        }
        let documentPicker = UIDocumentPickerViewController(forExporting: [fileUrl], asCopy: true)
        documentPicker.delegate = self
        objc_setAssociatedObject(documentPicker, &documentPickerCompletionKey, onDismiss, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        if let popover = documentPicker.popoverPresentationController {
            popover.sourceView = vc.view
            popover.sourceRect = CGRect(x: vc.view.bounds.midX, y: vc.view.bounds.midY, width: 0, height: 0)
            popover.permittedArrowDirections = []
        }
        vc.present(documentPicker, animated: true)
    }
    
    // MARK: - UIDocumentPickerDelegate
    
    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        (objc_getAssociatedObject(controller, &documentPickerCompletionKey) as? () -> Void)?()
        objc_setAssociatedObject(controller, &documentPickerCompletionKey, nil, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    }
    
    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        (objc_getAssociatedObject(controller, &documentPickerCompletionKey) as? () -> Void)?()
        objc_setAssociatedObject(controller, &documentPickerCompletionKey, nil, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    }
}

extension DownloadManager: SingleDownloadDelegate {
    fileprivate func singleDownloadDidStartNetworkFetch(_ download: SingleDownload) {
        activeNetworkFetchCount += 1
        showOverlayIfNeeded()
    }

    fileprivate func singleDownloadDidFinishNetworkFetch(_ download: SingleDownload) {
        activeNetworkFetchCount = max(0, activeNetworkFetchCount - 1)
        hideOverlayIfNeeded()
    }

    fileprivate func singleDownload(_ download: SingleDownload, fileReadyAt url: URL, completion: @escaping () -> Void) {
        presentDocumentPicker(for: url, onDismiss: completion)
    }

    fileprivate func singleDownload(_ download: SingleDownload, didCompleteWith error: Error?) {
        removeDownload(download)
    }
}

private var documentPickerCompletionKey: UInt8 = 0

private struct DestinationFileInfo {
    var fileName: String
}

// MARK: - Single Download

private protocol SingleDownloadDelegate: AnyObject {
    func singleDownloadDidStartNetworkFetch(_ download: SingleDownload)
    func singleDownloadDidFinishNetworkFetch(_ download: SingleDownload)
    func singleDownload(_ download: SingleDownload, fileReadyAt url: URL, completion: @escaping () -> Void)
    func singleDownload(_ download: SingleDownload, didCompleteWith error: Error?)
}

private final class SingleDownload {
    private weak var delegate: SingleDownloadDelegate?
    private var downloadedFileUrl: URL?

    init(delegate: SingleDownloadDelegate) {
        self.delegate = delegate
    }

    deinit {
        removeTempDirectory()
    }

    func start(from url: URL, to: DestinationFileInfo, webView: WKWebView) {
        let fileName = to.fileName
        webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { [weak self] cookies in
            guard let self else { return }
            let config = URLSessionConfiguration.default
            let storage = HTTPCookieStorage.shared
            storage.cookieAcceptPolicy = .always
            cookies.forEach { storage.setCookie($0) }
            config.httpCookieStorage = storage

            let session = URLSession(configuration: config)
            let task = session.downloadTask(with: url) { [weak self] localURL, _, error in
                Task { @MainActor in
                    guard let self else { return }
                    self.delegate?.singleDownloadDidFinishNetworkFetch(self)

                    if let error {
                        self.handleError(error)
                        return
                    }
                    guard let localURL else {
                        self.handleError(NSError(domain: "DownloadManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "No local URL"]))
                        return
                    }

                    // Save to a temporary unique-named directory keeping the original file name unchanged
                    let tempDir = FileManager.default.temporaryDirectory
                    let downloadDir = tempDir.appendingPathComponent(UUID().uuidString)
                    do {
                        try FileManager.default.createDirectory(at: downloadDir, withIntermediateDirectories: false)
                    } catch {
                        self.handleError(error)
                        return
                    }
                    let destUrl = downloadDir.appendingPathComponent(fileName)
                    do {
                        try FileManager.default.moveItem(at: localURL, to: destUrl)
                        self.downloadedFileUrl = destUrl
                        self.delegate?.singleDownload(self, fileReadyAt: destUrl) { [weak self] in
                            guard let self else { return }
                            self.removeTempDirectory()
                            self.delegate?.singleDownload(self, didCompleteWith: nil)
                        }
                    } catch {
                        try? FileManager.default.removeItem(at: downloadDir)
                        self.handleError(error)
                    }
                }
            }
            self.delegate?.singleDownloadDidStartNetworkFetch(self)
            task.resume()
        }
    }

    private func handleError(_ error: Error) {
        log.error("Download failed: \(error)")
        self.delegate?.singleDownload(self, didCompleteWith: error)
    }

    private func removeTempDirectory() {
        if let fileUrl = downloadedFileUrl {
            let dirUrl = fileUrl.deletingLastPathComponent()
            try? FileManager.default.removeItem(at: dirUrl)
            downloadedFileUrl = nil
        }
    }
}
