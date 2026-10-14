import Foundation
import ImageIO
import UniformTypeIdentifiers

enum CaptureImageNormalizationError: LocalizedError {
    case unsupportedImage
    case conversionFailed

    var errorDescription: String? {
        switch self {
        case .unsupportedImage:
            "无法读取这张照片，请选择其他照片"
        case .conversionFailed:
            "照片格式转换失败，请重试"
        }
    }
}

/// Converts camera and photo-library input, including HEIC, into one upload format.
actor CaptureImageNormalizer {
    private let maximumPixelDimension: Int
    private let jpegQuality: Double

    init(maximumPixelDimension: Int = 2_560, jpegQuality: Double = 0.9) {
        self.maximumPixelDimension = maximumPixelDimension
        self.jpegQuality = jpegQuality
    }

    func normalizeToJPEG(_ data: Data) throws -> Data {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions) else {
            throw CaptureImageNormalizationError.unsupportedImage
        }

        let thumbnailOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maximumPixelDimension,
            kCGImageSourceShouldCacheImmediately: true
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(
            source,
            0,
            thumbnailOptions as CFDictionary
        ) else {
            throw CaptureImageNormalizationError.conversionFailed
        }

        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            output,
            UTType.jpeg.identifier as CFString,
            1,
            nil
        ) else {
            throw CaptureImageNormalizationError.conversionFailed
        }

        let properties = [
            kCGImageDestinationLossyCompressionQuality: jpegQuality
        ] as CFDictionary
        CGImageDestinationAddImage(destination, image, properties)
        guard CGImageDestinationFinalize(destination) else {
            throw CaptureImageNormalizationError.conversionFailed
        }

        return output as Data
    }
}
