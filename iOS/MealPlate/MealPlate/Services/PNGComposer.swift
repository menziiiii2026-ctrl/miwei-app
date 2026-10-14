import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

struct PNGCompositionSpec: Sendable {
    var outputPixels: Int = 2048
    var foodScaleRelativeToPlate: CGFloat = 0.65
}

enum PNGCompositionError: Error {
    case invalidImageData
    case contextCreationFailed
    case encodingFailed
}

struct PNGComposer: Sendable {
    func compose(
        platePNG: Data,
        foodPNG: Data,
        spec: PNGCompositionSpec = .init()
    ) throws -> Data {
        guard let sourcePlate = Self.makeImage(from: platePNG),
              let food = Self.makeImage(from: foodPNG) else {
            throw PNGCompositionError.invalidImageData
        }
        let plate = sourcePlate.croppedToVisibleAlpha() ?? sourcePlate

        let side = spec.outputPixels
        guard let context = CGContext(
            data: nil,
            width: side,
            height: side,
            bitsPerComponent: 8,
            bytesPerRow: side * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw PNGCompositionError.contextCreationFailed
        }

        context.interpolationQuality = .high
        context.clear(CGRect(x: 0, y: 0, width: side, height: side))

        let canvas = CGRect(x: 0, y: 0, width: side, height: side)
        context.draw(plate, in: Self.aspectFitRect(for: plate, inside: canvas))

        let foodSide = CGFloat(side) * spec.foodScaleRelativeToPlate
        let foodBounds = CGRect(
            x: (CGFloat(side) - foodSide) / 2,
            y: (CGFloat(side) - foodSide) / 2,
            width: foodSide,
            height: foodSide
        )
        context.draw(food, in: Self.aspectFitRect(for: food, inside: foodBounds))

        guard let outputImage = context.makeImage() else {
            throw PNGCompositionError.contextCreationFailed
        }

        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            output,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else {
            throw PNGCompositionError.encodingFailed
        }
        CGImageDestinationAddImage(destination, outputImage, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw PNGCompositionError.encodingFailed
        }
        return output as Data
    }

    private static func makeImage(from data: Data) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    private static func aspectFitRect(for image: CGImage, inside bounds: CGRect) -> CGRect {
        let imageSize = CGSize(width: image.width, height: image.height)
        let scale = min(bounds.width / imageSize.width, bounds.height / imageSize.height)
        let size = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        return CGRect(
            x: bounds.midX - size.width / 2,
            y: bounds.midY - size.height / 2,
            width: size.width,
            height: size.height
        )
    }
}
