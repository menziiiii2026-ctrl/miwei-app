import CoreGraphics
import Foundation

struct CollageTemplateTextPlacement: Equatable, Sendable {
    let id: String
    let binding: String
    let defaultText: String?
    let periodValues: [String: String]
    let repeatedLineCount: Int?
    let center: CGPoint
    let normalizedWidth: CGFloat
    let normalizedHeight: CGFloat
    let fontFamily: String
    let fontStyle: String
    let isBold: Bool
    let fontSizeRatio: CGFloat
    let lineHeightMultiple: CGFloat?
    let alignment: String
    let colorHex: String
    let rotationDegrees: Double
    let zIndex: Int
    let maximumLines: Int
    let overflow: String
}

protocol CollageTemplateTextLayoutLoading {
    func textPlacements(for template: CollageTemplateDescriptor) throws -> [CollageTemplateTextPlacement]
}

struct BundledCollageTemplateTextLayoutLoader: CollageTemplateTextLayoutLoading {
    let bundle: Bundle

    init(bundle: Bundle = .main) {
        self.bundle = bundle
    }

    func textPlacements(for template: CollageTemplateDescriptor) throws -> [CollageTemplateTextPlacement] {
        guard let manifestURL = manifestURL(for: template),
              let manifestObject = try JSONSerialization.jsonObject(
                  with: Data(contentsOf: manifestURL, options: .mappedIfSafe)
              ) as? [String: Any],
              let reference = manifestObject["text_layout_ref"] as? String,
              let templateID = Self.templateID(from: reference),
              let layoutsURL = bundle.url(
                  forResource: "template-text-layouts.v1",
                  withExtension: "json",
                  subdirectory: "app-contract"
              ) else {
            return []
        }

        let document = try JSONDecoder().decode(
            TemplateTextLayoutDocument.self,
            from: Data(contentsOf: layoutsURL, options: .mappedIfSafe)
        )
        guard let layout = document.templates[templateID] else { return [] }
        return layout.layers.compactMap { layer -> CollageTemplateTextPlacement? in
            guard layer.frame.count == 4,
                  layout.referenceCanvas.count == 2,
                  layout.referenceCanvas[0] > 0,
                  layout.referenceCanvas[1] > 0,
                  layer.frame[2] >= 0,
                  layer.frame[3] >= 0 else {
                return nil
            }
            let canvasWidth = layout.referenceCanvas[0]
            let canvasHeight = layout.referenceCanvas[1]
            let x = layer.frame[0]
            let y = layer.frame[1]
            let width = layer.frame[2]
            let height = layer.frame[3]
            return CollageTemplateTextPlacement(
                id: layer.id,
                binding: layer.binding,
                defaultText: layer.defaultText,
                periodValues: layer.values ?? [:],
                repeatedLineCount: layer.repeat?.lines,
                center: CGPoint(
                    x: (x + width / 2) / canvasWidth,
                    y: (y + height / 2) / canvasHeight
                ),
                normalizedWidth: width / canvasWidth,
                normalizedHeight: height / canvasHeight,
                fontFamily: layer.font.family,
                fontStyle: layer.font.style,
                isBold: layer.font.isBold
                    ?? (layer.font.style.caseInsensitiveCompare("Bold") == .orderedSame),
                fontSizeRatio: layer.font.size / canvasWidth,
                lineHeightMultiple: layer.lineHeightPercent.map { $0 / 100 },
                alignment: layer.alignment,
                colorHex: layer.color,
                rotationDegrees: layer.rotationDegrees ?? 0,
                zIndex: layer.zIndex,
                maximumLines: max(1, layer.maximumLines),
                overflow: layer.overflow
            )
        }
    }

    private func manifestURL(for template: CollageTemplateDescriptor) -> URL? {
        let relativeURL = URL(fileURLWithPath: template.source)
        return bundle.url(
            forResource: relativeURL.deletingPathExtension().lastPathComponent,
            withExtension: relativeURL.pathExtension,
            subdirectory: "贴纸库/\(relativeURL.deletingLastPathComponent().path)"
        )
    }

    private static func templateID(from reference: String) -> String? {
        guard let range = reference.range(of: "#/templates/") else { return nil }
        let identifier = String(reference[range.upperBound...])
        return identifier.isEmpty ? nil : identifier
    }

    private struct TemplateTextLayoutDocument: Decodable {
        let templates: [String: Template]
    }

    private struct Template: Decodable {
        let referenceCanvas: [Double]
        let layers: [Layer]

        enum CodingKeys: String, CodingKey {
            case referenceCanvas = "reference_canvas_px"
            case layers
        }
    }

    private struct Layer: Decodable {
        let id: String
        let binding: String
        let defaultText: String?
        let values: [String: String]?
        let `repeat`: Repeat?
        let frame: [Double]
        let font: Font
        let alignment: String
        let lineHeightPercent: Double?
        let rotationDegrees: Double?
        let color: String
        let zIndex: Int
        let maximumLines: Int
        let overflow: String

        enum CodingKeys: String, CodingKey {
            case id
            case binding
            case defaultText = "default_text"
            case values
            case `repeat`
            case frame
            case font
            case alignment = "align"
            case lineHeightPercent = "line_height_percent"
            case rotationDegrees = "rotation_deg"
            case color
            case zIndex = "z_index"
            case maximumLines = "max_lines"
            case overflow
        }
    }

    private struct Repeat: Decodable {
        let lines: Int
    }

    private struct Font: Decodable {
        let family: String
        let style: String
        let size: Double
        let isBold: Bool?

        enum CodingKeys: String, CodingKey {
            case family
            case style
            case size = "size_px"
            case isBold = "is_bold"
        }
    }
}
