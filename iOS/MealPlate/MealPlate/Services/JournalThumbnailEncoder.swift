import Foundation
import ImageIO
import UIKit

actor JournalThumbnailEncoder {
    func pngData(from composedPNGData: Data, maxPixelSize: Int = 160) -> Data? {
        ImageDownsampler.pngData(
            from: composedPNGData,
            maxPixelSize: maxPixelSize
        )
    }
}
