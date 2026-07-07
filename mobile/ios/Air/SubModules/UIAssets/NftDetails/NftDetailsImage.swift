import Kingfisher
import UIKit

struct NftDetailsImage {

    static func noImagePlaceholderImage() -> UIImage {
        UIImage.airBundle("NoNftImage2")
    }

    struct Processed {
        var originalImage: UIImage?
        var previewImage: UIImage?
        var previewCIImage: CIImage?
        var baseColor: UIColor?
    }
    
    enum ProcessedState: CustomStringConvertible {
        case idle
        case loading
        case loaded(NftDetailsImage.Processed)
        case failed(Error)
        
        var description: String {
            switch self {
            case .idle: "<idle>"
            case .loading: "<loading>"
            case .failed: "<loadFailed>"
            case .loaded: "<loaded>"
            }
        }
        
        var isIdle: Bool {
            if case .idle = self { return true }
            return false
        }
        
        var isLoading: Bool {
            if case .loading = self { return true }
            return false
        }

        var isLoaded: Bool {
            if case .loaded = self { return true }
            return false
        }
    }
}

extension KingfisherError {
    var isNotFound: Bool {
        if case .responseError(let reason) = self,
           case .invalidHTTPStatusCode(let response) = reason {
            return response.statusCode == 404
        }
        return false
    }
}
