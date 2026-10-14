import CoreGraphics
import Foundation

struct CollageTemplatePlacement: Equatable, Sendable {
    let center: CGPoint
    let width: CGFloat
    let normalizedHeight: CGFloat?
    let rotationDegrees: Double
}

struct CollageTemplateFixedDecoration: Equatable, Sendable {
    let id: String
    let kind: String
    let assetReference: String?
    let assetFilePath: String?
    let drawable: CollageTemplateDrawable?
    let center: CGPoint
    let normalizedWidth: CGFloat
    let normalizedHeight: CGFloat
    let strokeWidthRatio: CGFloat?
    let rotationDegrees: Double
    let opacity: Double
    let zIndex: Int
    let colorHex: String
    let colorBindingScope: String?
    let editable: Bool
    let deletable: Bool
}

struct CollageTemplateDrawable: Equatable, Sendable {
    struct Stroke: Equatable, Sendable {
        let colorHex: String?
        let widthRatio: CGFloat
        let dashPattern: [CGFloat]
    }

    struct StrokeLayer: Equatable, Sendable {
        let colorHex: String
        let widthRatio: CGFloat
        let opacity: Double
    }

    struct InnerBacker: Equatable, Sendable {
        let frame: CGRect
        let colorHex: String
    }

    let shape: String?
    let fillHex: String?
    let cornerRadiusRatio: CGFloat
    let stroke: Stroke?
    let strokeLayers: [StrokeLayer]
    let curve: String?
    let innerBacker: InnerBacker?
}

protocol CollageTemplateManifestLoading {
    func subjectPlacements(
        for template: CollageTemplateDescriptor,
        foodCount: Int
    ) throws -> [CollageTemplatePlacement]
}

struct BundledCollageTemplateManifestLoader: CollageTemplateManifestLoading {
    let bundle: Bundle

    init(bundle: Bundle = .main) {
        self.bundle = bundle
    }

    func subjectPlacements(
        for template: CollageTemplateDescriptor,
        foodCount: Int
    ) throws -> [CollageTemplatePlacement] {
        guard foodCount > 0 else { return [] }
        guard let url = manifestURL(for: template),
              let object = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any] else {
            return Self.fallbackPlacements(templateCode: template.code, foodCount: foodCount)
        }

        let photoWindow = Self.photoWindow(from: object["photo_window"])
        var placements = Self.arrayPlacements(
            from: object["subjects"],
            defaultWindow: photoWindow
        )
        if placements.isEmpty {
            placements = Self.arrayPlacements(
                from: object["subject_windows"],
                defaultWindow: nil
            )
        }
        if placements.isEmpty,
           let subject = object["subject"] as? [String: Any],
           let center = Self.point(from: subject["center"]) {
            let width = Self.number(subject["plate_only_width_to_canvas_width"])
                ?? Self.midpoint(subject["plate_only_width_range"])
                ?? 0.55
            placements = [
                CollageTemplatePlacement(
                    center: center,
                    width: CGFloat(width),
                    normalizedHeight: nil,
                    rotationDegrees: 0
                )
            ]
        }

        if placements.isEmpty {
            placements = Self.fallbackPlacements(templateCode: template.code, foodCount: foodCount)
        }
        let clipWindows = Self.subjectClipWindows(from: object)
        if !clipWindows.isEmpty {
            placements = placements.enumerated().map { index, placement in
                guard clipWindows.indices.contains(index) else { return placement }
                let clip = clipWindows[index]
                return CollageTemplatePlacement(
                    center: clip.center,
                    width: clip.width,
                    normalizedHeight: clip.height,
                    rotationDegrees: placement.rotationDegrees
                )
            }
        }
        if placements.count < foodCount {
            let supplemental = Self.collectionPlacements(foodCount: foodCount)
            placements.append(contentsOf: supplemental.dropFirst(placements.count))
        }
        return Array(placements.prefix(foodCount))
    }

    func fixedDecorations(
        for template: CollageTemplateDescriptor,
        accentColorHex: String?
    ) throws -> [CollageTemplateFixedDecoration] {
        guard let url = manifestURL(for: template),
              let object = try JSONSerialization.jsonObject(
                with: Data(contentsOf: url, options: .mappedIfSafe)
              ) as? [String: Any],
              let container = object["fixed_decoration_layers"] as? [String: Any],
              let layers = container["layers"] as? [[String: Any]] else {
            return []
        }
        let canvas = Self.canvasSize(
            container["reference_canvas_px"] ?? object["reference_canvas_px"]
        )
        guard canvas.width > 0, canvas.height > 0 else { return [] }
        let stack = Self.layerStack(from: object["layer_stack"])

        return layers.compactMap { layer in
            guard let id = layer["id"] as? String,
                  let kind = (layer["type"] ?? layer["kind"]) as? String,
                  let frame = layer["frame_px"] as? [NSNumber],
                  frame.count == 4 else { return nil }
            if let appearance = layer["appearance"] as? [String: Any],
               appearance["default_visible"] as? Bool == false {
                return nil
            }
            let x = frame[0].doubleValue
            let y = frame[1].doubleValue
            let width = frame[2].doubleValue
            let height = frame[3].doubleValue
            guard width > 0, height > 0 else { return nil }
            let fallback = layer["fallback_color"] as? String ?? "#FFD326"
            let resolvedColor = layer["color_binding"] as? String == "intent.mood.accent_color"
                ? (Self.validHex(accentColorHex) ?? fallback)
                : fallback
            let assetReference = layer["asset_ref"] as? String
            return CollageTemplateFixedDecoration(
                id: id,
                kind: kind,
                assetReference: assetReference,
                assetFilePath: assetReference.flatMap {
                    Self.assetFilePath(reference: $0, relativeTo: url)
                },
                drawable: Self.drawable(
                    from: layer["drawable"],
                    decorationFrame: CGRect(x: x, y: y, width: width, height: height),
                    canvas: canvas
                ),
                center: CGPoint(
                    x: (x + width / 2) / canvas.width,
                    y: (y + height / 2) / canvas.height
                ),
                normalizedWidth: width / canvas.width,
                normalizedHeight: height / canvas.height,
                strokeWidthRatio: Self.number(layer["stroke_width_px"]).map {
                    CGFloat($0 / canvas.width)
                },
                rotationDegrees: Self.number(layer["rotation_deg"]) ?? 0,
                opacity: Self.number(layer["opacity"]) ?? 1,
                zIndex: stack[id] ?? Int(Self.number(layer["z_index"]) ?? 0),
                colorHex: resolvedColor,
                colorBindingScope: layer["color_binding_scope"] as? String,
                editable: layer["editable"] as? Bool ?? false,
                deletable: layer["deletable"] as? Bool ?? false
            )
        }
    }

    func layerZIndexes(for template: CollageTemplateDescriptor) throws -> [String: Int] {
        guard let object = try manifestObject(for: template) else { return [:] }
        return Self.layerStack(from: object["layer_stack"])
    }

    func subjectLayerIDs(for template: CollageTemplateDescriptor) throws -> [String] {
        guard let object = try manifestObject(for: template),
              let entries = object["layer_stack"] as? [[String: Any]] else { return [] }
        return entries.compactMap { entry -> (String, Int)? in
            guard entry["kind"] as? String == "subject",
                  let id = entry["id"] as? String,
                  let zIndex = Self.number(entry["z_index"]) else { return nil }
            return (id, Int(zIndex))
        }
        .sorted { $0.1 < $1.1 }
        .map(\.0)
    }

    private func manifestObject(for template: CollageTemplateDescriptor) throws -> [String: Any]? {
        guard let url = manifestURL(for: template) else { return nil }
        return try JSONSerialization.jsonObject(
            with: Data(contentsOf: url, options: .mappedIfSafe)
        ) as? [String: Any]
    }

    private func manifestURL(for template: CollageTemplateDescriptor) -> URL? {
        let relativeURL = URL(fileURLWithPath: template.source)
        let directory = relativeURL.deletingLastPathComponent().path
        let fileName = relativeURL.deletingPathExtension().lastPathComponent
        return bundle.url(
            forResource: fileName,
            withExtension: relativeURL.pathExtension,
            subdirectory: "贴纸库/\(directory)"
        )
    }

    private static func assetFilePath(reference: String, relativeTo manifestURL: URL) -> String? {
        let url = manifestURL.deletingLastPathComponent()
            .appending(path: reference)
            .standardizedFileURL
        return FileManager.default.fileExists(atPath: url.path) ? url.path : nil
    }

    private static func subjectClipWindows(from object: [String: Any]) -> [ClipWindow] {
        guard let canvas = optionalCanvasSize(object["reference_canvas_px"]),
              let container = object["fixed_decoration_layers"] as? [String: Any],
              let layers = container["layers"] as? [[String: Any]] else { return [] }
        return layers.compactMap { layer in
            guard (layer["type"] as? String) == "subject_clip_window",
                  let frame = layer["frame_px"] as? [NSNumber], frame.count == 4 else {
                return nil
            }
            let x = frame[0].doubleValue
            let y = frame[1].doubleValue
            let width = frame[2].doubleValue
            let height = frame[3].doubleValue
            guard width > 0, height > 0 else { return nil }
            return ClipWindow(
                center: CGPoint(
                    x: (x + width / 2) / canvas.width,
                    y: (y + height / 2) / canvas.height
                ),
                width: width / canvas.width,
                height: height / canvas.height
            )
        }
    }

    private static func drawable(
        from value: Any?,
        decorationFrame: CGRect,
        canvas: CGSize
    ) -> CollageTemplateDrawable? {
        guard let object = value as? [String: Any] else { return nil }
        let stroke: CollageTemplateDrawable.Stroke?
        if let value = object["stroke"] as? [String: Any] {
            stroke = .init(
                colorHex: value["color"] as? String,
                widthRatio: CGFloat((number(value["width_px"]) ?? 0) / canvas.width),
                dashPattern: (value["dash_pattern_px"] as? [NSNumber] ?? []).map {
                    CGFloat($0.doubleValue / canvas.width)
                }
            )
        } else {
            stroke = nil
        }
        let strokeLayers = (object["stroke_layers"] as? [[String: Any]] ?? []).compactMap {
            layer -> CollageTemplateDrawable.StrokeLayer? in
            guard let color = layer["color"] as? String else { return nil }
            return .init(
                colorHex: color,
                widthRatio: CGFloat((number(layer["width_px"]) ?? 0) / canvas.width),
                opacity: number(layer["opacity"]) ?? 1
            )
        }
        let innerBacker: CollageTemplateDrawable.InnerBacker?
        if let value = object["inner_backer"] as? [String: Any],
           let frame = value["frame_px"] as? [NSNumber], frame.count == 4,
           let fill = value["fill"] as? String,
           decorationFrame.width > 0, decorationFrame.height > 0 {
            innerBacker = .init(
                frame: CGRect(
                    x: (frame[0].doubleValue - decorationFrame.minX) / decorationFrame.width,
                    y: (frame[1].doubleValue - decorationFrame.minY) / decorationFrame.height,
                    width: frame[2].doubleValue / decorationFrame.width,
                    height: frame[3].doubleValue / decorationFrame.height
                ),
                colorHex: fill
            )
        } else {
            innerBacker = nil
        }
        return CollageTemplateDrawable(
            shape: object["shape"] as? String,
            fillHex: object["fill"] as? String,
            cornerRadiusRatio: CGFloat(
                (number(object["corner_radius_px"]) ?? 0) / max(decorationFrame.width, 1)
            ),
            stroke: stroke,
            strokeLayers: strokeLayers,
            curve: object["curve"] as? String,
            innerBacker: innerBacker
        )
    }

    private static func arrayPlacements(
        from value: Any?,
        defaultWindow: PhotoWindow?
    ) -> [CollageTemplatePlacement] {
        guard let subjects = value as? [[String: Any]] else { return [] }
        return subjects.compactMap { subject in
            guard let center = point(from: subject["anchor"] ?? subject["center"]) else {
                return nil
            }
            let width = number(subject["width_ratio"])
                ?? number(subject["diameter_ratio"])
                ?? number(subject["dish_diameter_ratio"])
                ?? number(subject["window_width"])
                ?? midpoint(subject["width_range"])
                ?? 0.32
            let rotation = number(subject["rotation_deg"])
                ?? midpoint(subject["rotation_range_deg"])
                ?? 0
            let normalizedHeight: CGFloat?
            if let window = subject["window"] as? [NSNumber], window.count >= 2 {
                normalizedHeight = CGFloat(window[1].doubleValue)
            } else if let defaultWindow, defaultWindow.clipsContent {
                // Subject widths are normalized to canvas width while Y/height are
                // normalized to canvas height. The editor canvas is always 3:4.
                normalizedHeight = CGFloat(
                    width * defaultWindow.heightToWidth * (3.0 / 4.0)
                )
            } else {
                normalizedHeight = nil
            }
            return CollageTemplatePlacement(
                center: center,
                width: CGFloat(width),
                normalizedHeight: normalizedHeight,
                rotationDegrees: rotation
            )
        }
    }

    private static func photoWindow(from value: Any?) -> PhotoWindow? {
        guard let object = value as? [String: Any] else { return nil }
        let ratio = (object["ratio"] as? String).flatMap(parseRatio) ?? (3.0 / 2.0)
        return PhotoWindow(
            heightToWidth: 1 / ratio,
            clipsContent: (object["clip_subject"] as? Bool) == true
        )
    }

    private static func parseRatio(_ value: String) -> Double? {
        let parts = value.split(separator: ":").compactMap { Double($0) }
        guard parts.count == 2, parts[0] > 0, parts[1] > 0 else { return nil }
        return parts[0] / parts[1]
    }

    private static func point(from value: Any?) -> CGPoint? {
        if let values = value as? [NSNumber], values.count >= 2 {
            return CGPoint(x: values[0].doubleValue, y: values[1].doubleValue)
        }
        if let object = value as? [String: Any],
           let x = number(object["x"]),
           let y = number(object["y"]) {
            return CGPoint(x: x, y: y)
        }
        return nil
    }

    private static func midpoint(_ value: Any?) -> Double? {
        guard let values = value as? [NSNumber], values.count >= 2 else { return nil }
        return (values[0].doubleValue + values[1].doubleValue) / 2
    }

    private static func number(_ value: Any?) -> Double? {
        (value as? NSNumber)?.doubleValue
    }

    private static func canvasSize(_ value: Any?) -> CGSize {
        guard let values = value as? [NSNumber], values.count >= 2 else { return .zero }
        return CGSize(width: values[0].doubleValue, height: values[1].doubleValue)
    }

    private static func optionalCanvasSize(_ value: Any?) -> CGSize? {
        let size = canvasSize(value)
        return size.width > 0 && size.height > 0 ? size : nil
    }

    private static func layerStack(from value: Any?) -> [String: Int] {
        guard let entries = value as? [[String: Any]] else { return [:] }
        return entries.reduce(into: [:]) { result, entry in
            guard let id = entry["id"] as? String,
                  let zIndex = number(entry["z_index"]) else { return }
            result[id] = Int(zIndex)
        }
    }

    private static func validHex(_ value: String?) -> String? {
        guard let value, value.wholeMatch(of: /^#[0-9A-Fa-f]{6}$/) != nil else {
            return nil
        }
        return value
    }

    private static func fallbackPlacements(
        templateCode: String,
        foodCount: Int
    ) -> [CollageTemplatePlacement] {
        switch templateCode {
        case "1_模板1":
            return [.init(center: CGPoint(x: 0.513, y: 0.573), width: 0.87, normalizedHeight: nil, rotationDegrees: 0)]
        case "1_模板2":
            return [.init(center: CGPoint(x: 0.5, y: 0.5), width: 0.54, normalizedHeight: nil, rotationDegrees: 0)]
        case "1_模板3":
            return [.init(center: CGPoint(x: 0.5, y: 0.67), width: 0.45, normalizedHeight: nil, rotationDegrees: 0)]
        default:
            return collectionPlacements(foodCount: foodCount)
        }
    }

    private static func collectionPlacements(foodCount: Int) -> [CollageTemplatePlacement] {
        guard foodCount > 1 else {
            return [.init(center: CGPoint(x: 0.5, y: 0.5), width: 0.58, normalizedHeight: nil, rotationDegrees: 0)]
        }
        return (0..<foodCount).map { index in
            let angle = Double(index) / Double(foodCount) * .pi * 2 - .pi / 2
            return CollageTemplatePlacement(
                center: CGPoint(
                    x: 0.5 + CGFloat(cos(angle)) * 0.29,
                    y: 0.5 + CGFloat(sin(angle)) * 0.31
                ),
                width: foodCount <= 3 ? 0.34 : 0.24,
                normalizedHeight: nil,
                rotationDegrees: Double((index % 5) * 4 - 8)
            )
        }
    }

    private struct PhotoWindow {
        let heightToWidth: Double
        let clipsContent: Bool
    }


    private struct ClipWindow {
        let center: CGPoint
        let width: CGFloat
        let height: CGFloat
    }
}
