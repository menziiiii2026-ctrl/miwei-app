import Observation
import SwiftUI
import UIKit

enum JournalCollagePeriod: String, Identifiable, Sendable {
    case today
    case week

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .today: "今日"
        case .week: "本周"
        }
    }

    func dateInterval(containing date: Date = .now) -> DateInterval? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "zh_CN")
        calendar.timeZone = .current
        calendar.firstWeekday = 2

        switch self {
        case .today:
            let start = calendar.startOfDay(for: date)
            guard let end = calendar.date(byAdding: .day, value: 1, to: start) else {
                return nil
            }
            return DateInterval(start: start, end: end)
        case .week:
            return calendar.dateInterval(of: .weekOfYear, for: date)
        }
    }
}

enum CollageLayerKind: String, Codable, Equatable, Sendable {
    case subject
    case overlay
    case outline
    case sticker
    case text
}

enum CollageEditorPanel: Equatable {
    case background
    case sticker
}

enum CollageTextFont: String, CaseIterable, Codable, Identifiable, Sendable {
    case lingHui
    case waWa
    case americanTypewriter
    case arialBlack
    case bmYeonsung
    case gb18030Bitmap
    case heiti
    case georgia
    case comingSoon

    static let editorFonts: [Self] = [
        .lingHui, .waWa, .americanTypewriter, .arialBlack,
        .bmYeonsung, .gb18030Bitmap, .heiti
    ]

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .lingHui: "Long Cang"
        case .waWa: "Ma Shan Zheng"
        case .americanTypewriter: "打字机"
        case .arialBlack: "Bungee"
        case .bmYeonsung: "Nanum Pen"
        case .gb18030Bitmap: "缝合像素"
        case .heiti: "系统黑体"
        case .georgia: "Georgia"
        case .comingSoon: "Coming Soon"
        }
    }

    func font(size: CGFloat, isBold: Bool, isItalic: Bool = false) -> Font {
        let name = postScriptName(isBold: isBold, isItalic: isItalic)
        let result = Font.custom(name, size: size, relativeTo: .title3)
        return isBold && nativeBoldName == nil ? result.weight(.bold) : result
    }

    /// Template typography is measured in the same fixed canvas pixels as its
    /// source JSON, so it must not pick up the device's Dynamic Type scale.
    func canvasFont(size: CGFloat, isBold: Bool, isItalic: Bool = false) -> Font {
        let name = postScriptName(isBold: isBold, isItalic: isItalic)
        let result = Font.custom(name, size: size)
        return isBold && nativeBoldName == nil ? result.weight(.bold) : result
    }

    func uiFont(size: CGFloat, isBold: Bool, isItalic: Bool = false) -> UIFont {
        let name = postScriptName(isBold: isBold, isItalic: isItalic)
        let base = UIFont(name: name, size: size) ?? .systemFont(ofSize: size)
        guard isBold, nativeBoldName == nil,
              let descriptor = base.fontDescriptor.withSymbolicTraits(.traitBold) else {
            return base
        }
        return UIFont(descriptor: descriptor, size: size)
    }

    private func postScriptName(isBold: Bool, isItalic: Bool) -> String {
        if self == .georgia, isItalic {
            return isBold ? "Georgia-BoldItalic" : "Georgia-Italic"
        }
        if isBold, let nativeBoldName {
            return nativeBoldName
        }
        return regularName
    }

    private var regularName: String {
        switch self {
        case .lingHui: "LongCang-Regular"
        case .waWa: "MaShanZheng-Regular"
        case .americanTypewriter: "CourierPrime-Regular"
        case .arialBlack: "Bungee-Regular"
        case .bmYeonsung: "NanumPen-Regular"
        case .gb18030Bitmap: "Fusion-Pixel-12px-Prop-zh-Hans-Regular"
        case .heiti: "PingFangSC-Regular"
        case .georgia: "Georgia"
        case .comingSoon: "ComingSoon-Regular"
        }
    }

    private var nativeBoldName: String? {
        switch self {
        case .americanTypewriter: "CourierPrime-Bold"
        case .heiti: "PingFangSC-Semibold"
        default: nil
        }
    }
}

enum CollageTextAlignment: String, CaseIterable, Codable, Identifiable, Sendable {
    case leading
    case center
    case trailing

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .leading: "左"
        case .center: "中"
        case .trailing: "右"
        }
    }

    var accessibilityName: String {
        switch self {
        case .leading: "左对齐"
        case .center: "居中对齐"
        case .trailing: "右对齐"
        }
    }

    var textAlignment: TextAlignment {
        switch self {
        case .leading: .leading
        case .center: .center
        case .trailing: .trailing
        }
    }

    var alignment: Alignment {
        switch self {
        case .leading: .leading
        case .center: .center
        case .trailing: .trailing
        }
    }
}

enum CollageTextOverflow: String, Codable, Equatable, Sendable {
    case clip
    case wrap
    case scaleDown = "scale_down"
}

struct CollageColorValue: Codable, Hashable, Identifiable, Sendable {
    let name: String
    let red: Double
    let green: Double
    let blue: Double
    let opacity: Double

    var id: String {
        "\(name)-\(Int(red * 255))-\(Int(green * 255))-\(Int(blue * 255))-\(Int(opacity * 255))"
    }

    var color: Color {
        Color(.sRGB, red: red, green: green, blue: blue, opacity: opacity)
    }

    var uiColor: UIColor {
        UIColor(red: red, green: green, blue: blue, alpha: opacity)
    }

    init(
        name: String,
        red: Double,
        green: Double,
        blue: Double,
        opacity: Double = 1
    ) {
        self.name = name
        self.red = red
        self.green = green
        self.blue = blue
        self.opacity = opacity
    }

    init(color: Color, name: String = "自定义") {
        let uiColor = UIColor(color)
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 1

        if !uiColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha) {
            var white: CGFloat = 0
            uiColor.getWhite(&white, alpha: &alpha)
            red = white
            green = white
            blue = white
        }

        self.init(
            name: name,
            red: Double(red),
            green: Double(green),
            blue: Double(blue),
            opacity: Double(alpha)
        )
    }

    static let black = Self(name: "黑色", red: 0, green: 0, blue: 0)
    static let white = Self(name: "白色", red: 1, green: 1, blue: 1)
    static let brown = Self(name: "深棕", red: 119 / 255, green: 77 / 255, blue: 77 / 255)
    static let rose = Self(name: "灰玫瑰", red: 168 / 255, green: 136 / 255, blue: 154 / 255)
    static let cream = Self(name: "奶油", red: 248 / 255, green: 247 / 255, blue: 242 / 255)
    static let apricot = Self(name: "杏色", red: 239 / 255, green: 219 / 255, blue: 161 / 255)
    static let red = Self(name: "红色", red: 217 / 255, green: 87 / 255, blue: 87 / 255)
    static let coral = Self(name: "珊瑚", red: 233 / 255, green: 135 / 255, blue: 120 / 255)
    static let orange = Self(name: "橙色", red: 229 / 255, green: 155 / 255, blue: 91 / 255)
    static let yellow = Self(name: "黄色", red: 229 / 255, green: 201 / 255, blue: 91 / 255)
    static let olive = Self(name: "橄榄", red: 154 / 255, green: 166 / 255, blue: 107 / 255)
    static let green = Self(name: "绿色", red: 95 / 255, green: 141 / 255, blue: 107 / 255)
    static let mint = Self(name: "薄荷", red: 119 / 255, green: 169 / 255, blue: 154 / 255)
    static let cyan = Self(name: "青色", red: 102 / 255, green: 165 / 255, blue: 182 / 255)
    static let blue = Self(name: "蓝色", red: 102 / 255, green: 138 / 255, blue: 182 / 255)
    static let indigo = Self(name: "靛蓝", red: 111 / 255, green: 111 / 255, blue: 168 / 255)
    static let purple = Self(name: "紫色", red: 155 / 255, green: 114 / 255, blue: 163 / 255)
    static let pink = Self(name: "粉色", red: 213 / 255, green: 143 / 255, blue: 169 / 255)

    static let presets: [Self] = [
        .black, .white, .brown, .rose, .cream, .apricot,
        .red, .coral, .orange, .yellow, .olive, .green,
        .mint, .cyan, .blue, .indigo, .purple, .pink
    ]
}

struct CollageBackgroundOption: Identifiable {
    let id: String
    let image: UIImage
}

struct CollageStickerOption: Identifiable {
    let id: String
    let image: UIImage
}

@Observable
@MainActor
final class CollageBackgroundSlot: Identifiable {
    let id: UUID
    var sourceID: String?
    var image: UIImage?
    var offset: CGSize
    var scale: CGFloat
    var opacity: Double

    init(
        id: UUID = UUID(),
        sourceID: String? = nil,
        image: UIImage? = nil,
        offset: CGSize = .zero,
        scale: CGFloat = 1,
        opacity: Double = 1
    ) {
        self.id = id
        self.sourceID = sourceID
        self.image = image
        self.offset = offset
        self.scale = scale
        self.opacity = opacity
    }
}

@Observable
@MainActor
final class CollageLayer: Identifiable {
    let id: UUID
    let kind: CollageLayerKind
    var image: UIImage?
    var assetReference: String?
    var text: String
    var center: CGPoint
    var normalizedWidth: CGFloat
    var normalizedHeight: CGFloat?
    var scale: CGFloat
    var contentScale: CGFloat
    var contentOffset: CGSize
    var rotation: Angle
    var opacity: Double
    var zIndex: Int
    var isEditable: Bool
    var isDeletable: Bool
    var textFont: CollageTextFont
    var isTextBold: Bool
    var isTextItalic: Bool
    var textAlignment: CollageTextAlignment
    var textColor: CollageColorValue
    var textBackground: CollageColorValue?
    var textFrameHeight: CGFloat?
    var textFontSizeRatio: CGFloat?
    var textLineHeightMultiple: CGFloat?
    var textMaximumLines: Int?
    var textOverflow: CollageTextOverflow?

    init(
        id: UUID = UUID(),
        kind: CollageLayerKind,
        image: UIImage? = nil,
        assetReference: String? = nil,
        text: String = "",
        center: CGPoint,
        normalizedWidth: CGFloat,
        normalizedHeight: CGFloat? = nil,
        scale: CGFloat = 1,
        contentScale: CGFloat = 1,
        contentOffset: CGSize = .zero,
        rotation: Angle = .zero,
        opacity: Double = 1,
        zIndex: Int,
        isEditable: Bool = true,
        isDeletable: Bool = true,
        textFont: CollageTextFont = .lingHui,
        isTextBold: Bool = false,
        isTextItalic: Bool = false,
        textAlignment: CollageTextAlignment = .center,
        textColor: CollageColorValue = .brown,
        textBackground: CollageColorValue? = nil,
        textFrameHeight: CGFloat? = nil,
        textFontSizeRatio: CGFloat? = nil,
        textLineHeightMultiple: CGFloat? = nil,
        textMaximumLines: Int? = nil,
        textOverflow: CollageTextOverflow? = nil
    ) {
        self.id = id
        self.kind = kind
        self.image = image
        self.assetReference = assetReference
        self.text = text
        self.center = center
        self.normalizedWidth = normalizedWidth
        self.normalizedHeight = normalizedHeight
        self.scale = scale
        self.contentScale = contentScale
        self.contentOffset = contentOffset
        self.rotation = rotation
        self.opacity = opacity
        self.zIndex = zIndex
        self.isEditable = isEditable
        self.isDeletable = isDeletable
        self.textFont = textFont
        self.isTextBold = isTextBold
        self.isTextItalic = isTextItalic
        self.textAlignment = textAlignment
        self.textColor = textColor
        self.textBackground = textBackground
        self.textFrameHeight = textFrameHeight
        self.textFontSizeRatio = textFontSizeRatio
        self.textLineHeightMultiple = textLineHeightMultiple
        self.textMaximumLines = textMaximumLines
        self.textOverflow = textOverflow
    }

    func interactionFrame(in canvasSize: CGSize) -> CGRect {
        let size = displaySize(in: canvasSize)
        let displayedCenter = displayCenter(in: canvasSize)
        return CGRect(
            x: displayedCenter.x * canvasSize.width - size.width / 2,
            y: displayedCenter.y * canvasSize.height - size.height / 2,
            width: size.width,
            height: size.height
        )
    }

    /// Returns the visual centre. Template text retains the Figma frame's
    /// leading/trailing anchor when its runtime text needs a wider frame.
    func displayCenter(in canvasSize: CGSize) -> CGPoint {
        guard kind == .text,
              textFrameHeight != nil,
              canvasSize.width > 0 else {
            return center
        }

        let baseWidth = normalizedWidth * canvasSize.width * scale
        let expandedWidth = displaySize(in: canvasSize).width
        let halfExpansion = max(0, expandedWidth - baseWidth) / 2
        guard halfExpansion > 0 else { return center }

        let localHorizontalShift: CGFloat
        switch textAlignment {
        case .leading:
            localHorizontalShift = halfExpansion
        case .trailing:
            localHorizontalShift = -halfExpansion
        case .center:
            localHorizontalShift = 0
        }
        let radians = rotation.radians
        return CGPoint(
            x: min(
                max(
                    center.x + localHorizontalShift * cos(radians) / canvasSize.width,
                    0
                ),
                1
            ),
            y: min(
                max(
                    center.y + localHorizontalShift * sin(radians) / canvasSize.height,
                    0
                ),
                1
            )
        )
    }

    func displaySize(in canvasSize: CGSize) -> CGSize {
        let imageWidth = normalizedWidth * canvasSize.width * scale
        guard kind == .text else {
            if let normalizedHeight {
                return CGSize(
                    width: imageWidth,
                    height: normalizedHeight * canvasSize.height * scale
                )
            }
            let imageHeight: CGFloat
            if let image, image.size.width > 0 {
                imageHeight = imageWidth * image.size.height / image.size.width
            } else {
                imageHeight = max(44, 46 * scale)
            }
            return CGSize(width: imageWidth, height: imageHeight)
        }

        if let textFrameHeight {
            let baseWidth = normalizedWidth * canvasSize.width * scale
            let resolvedWidth = templateTextWidth(in: canvasSize, baseWidth: baseWidth)
            return CGSize(
                width: resolvedWidth,
                height: templateTextHeight(
                    in: canvasSize,
                    width: resolvedWidth,
                    baseHeight: textFrameHeight * canvasSize.height * scale
                )
            )
        }

        let fontSize = max(10, canvasSize.width * 0.053 * scale)
        let font = textFont.uiFont(
            size: fontSize,
            isBold: isTextBold,
            isItalic: isTextItalic
        )
        let measured = (text as NSString).boundingRect(
            with: CGSize(width: canvasSize.width * 0.82, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: font],
            context: nil
        ).integral.size

        return CGSize(
            width: min(max(44, measured.width + 20), canvasSize.width * 0.87),
            height: max(32, measured.height + 12)
        )
    }

    private func templateTextWidth(in canvasSize: CGSize, baseWidth: CGFloat) -> CGFloat {
        guard textOverflow != .wrap,
              canvasSize.width > 0 else {
            return baseWidth
        }

        let fontSize = max(1, (textFontSizeRatio ?? 0.053) * canvasSize.width * scale)
        let font = textFont.uiFont(
            size: fontSize,
            isBold: isTextBold,
            isItalic: isTextItalic
        )
        let measuredWidth = ceil(
            (text as NSString).boundingRect(
                with: CGSize(
                    width: CGFloat.greatestFiniteMagnitude,
                    height: CGFloat.greatestFiniteMagnitude
                ),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                attributes: [.font: font],
                context: nil
            ).width
        )
        let desiredWidth = max(baseWidth, measuredWidth + max(2, 2 * scale))
        let maximumWidth = maximumTemplateTextWidth(
            in: canvasSize,
            baseWidth: baseWidth
        )
        return max(baseWidth, min(desiredWidth, maximumWidth))
    }

    private func templateTextHeight(
        in canvasSize: CGSize,
        width: CGFloat,
        baseHeight: CGFloat
    ) -> CGFloat {
        guard textOverflow == .wrap,
              canvasSize.width > 0,
              width > 0 else {
            return baseHeight
        }

        let fontSize = max(1, (textFontSizeRatio ?? 0.053) * canvasSize.width * scale)
        let font = textFont.uiFont(
            size: fontSize,
            isBold: isTextBold,
            isItalic: isTextItalic
        )
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = max(
            0,
            fontSize * ((textLineHeightMultiple ?? 1) - 1)
        )
        let measuredHeight = ceil(
            (text as NSString).boundingRect(
                with: CGSize(width: width, height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                attributes: [
                    .font: font,
                    .paragraphStyle: paragraphStyle
                ],
                context: nil
            ).height
        )
        let maximumLines = max(1, textMaximumLines ?? Int.max)
        let lineHeight = font.lineHeight + paragraphStyle.lineSpacing
        let maximumHeight: CGFloat
        if maximumLines == Int.max {
            maximumHeight = measuredHeight
        } else {
            maximumHeight = CGFloat(maximumLines) * lineHeight
        }
        return max(baseHeight, min(measuredHeight, maximumHeight))
    }

    private func maximumTemplateTextWidth(
        in canvasSize: CGSize,
        baseWidth: CGFloat
    ) -> CGFloat {
        let centerX = center.x * canvasSize.width
        let leadingEdge = centerX - baseWidth / 2
        let trailingEdge = centerX + baseWidth / 2

        switch textAlignment {
        case .leading:
            return max(baseWidth, canvasSize.width - leadingEdge)
        case .trailing:
            return max(baseWidth, trailingEdge)
        case .center:
            return max(baseWidth, 2 * min(centerX, canvasSize.width - centerX))
        }
    }
}

@Observable
@MainActor
final class CollageEditorModel {
    private static let editorWorkingImageMaxPixelSize = 1_206
    private static let editorBackgroundMaxPixelSize = 1_608
    private static let editorBackgroundThumbnailMaxPixelSize = 320

    let period: JournalCollagePeriod

    var isLoading = true
    var openingPreview: UIImage?
    var loadFailureMessage: String?
    var selectedTemplateCode: String?
    var generationReason: String?
    var inputFingerprint: String?
    var periodIntervalStart: Date?
    var availableBackgrounds: [CollageBackgroundOption] = []
    var stickerOptions: [CollageStickerOption] = []
    var backgroundSlots: [CollageBackgroundSlot] = []
    var isSplitBackground = false
    var splitFraction: CGFloat = 0.5
    var activeBackgroundIndex = 0
    var layers: [CollageLayer] = []
    var selectedLayerID: UUID?
    var cropEditingLayerID: UUID?
    var isEditingBackgroundComposition = false
    var presentedPanel: CollageEditorPanel?
    var isDraggingLayer = false
    var isOverTrash = false
    var reorderFeedbackCounter = 0

    private var undoHistory: [EditorSnapshot] = []
    private var withdrawnUndoHistory: [EditorSnapshot] = []
    private var pendingHistorySnapshot: EditorSnapshot?

    private var hasPrepared = false
    private var backgroundDraft: BackgroundDraft?
    private var backgroundCompositionDraft: BackgroundDraft?
    private var textDraft: TextDraft?
    private var newlyCreatedTextID: UUID?
    private var dragStart: DragStart?
    private var lastDragLocation: CGPoint?
    private var lastSelectionPoint: CGPoint?
    private var lastSelectionCandidates: [UUID] = []
    private var lastSelectionIndex = 0

    var canUndo: Bool { !undoHistory.isEmpty }
    var canWithdrawUndo: Bool { !withdrawnUndoHistory.isEmpty }

    init(period: JournalCollagePeriod) {
        self.period = period
    }

    var orderedLayers: [CollageLayer] {
        layers.sorted {
            if $0.zIndex == $1.zIndex {
                $0.id.uuidString < $1.id.uuidString
            } else {
                $0.zIndex < $1.zIndex
            }
        }
    }

    var selectedLayer: CollageLayer? {
        guard let selectedLayerID else { return nil }
        return layers.first { $0.id == selectedLayerID }
    }

    var canAdjustOpacity: Bool {
        selectedLayer != nil
    }

    var selectedLayerCanCrop: Bool {
        guard let selectedLayer else { return false }
        return selectedLayer.image != nil
            && selectedLayer.isEditable
            && selectedLayer.kind != .outline
            && selectedLayer.kind != .text
    }

    var isEditingCrop: Bool {
        cropEditingLayerID != nil
    }

    var canAdjustBackgroundComposition: Bool {
        let requiredCount = isSplitBackground ? 2 : 1
        guard backgroundSlots.count >= requiredCount else { return false }
        return backgroundSlots.prefix(requiredCount).allSatisfy { $0.image != nil }
    }

    func prepare(
        repository: (any DishRepository)?,
        imageStore: (any ImageFileStoring)?,
        generationPlanner: CollageGenerationPlanner?,
        artifactStore: CollageArtifactStore? = nil
    ) async {
        guard !hasPrepared else { return }
        hasPrepared = true
        isLoading = true
        defer { isLoading = false }

        loadBundledBackgrounds()
        loadBundledStickers()

        guard let repository, let imageStore, let interval = period.dateInterval() else {
            return
        }
        periodIntervalStart = interval.start

        do {
            let tastings = try repository.fetchTastings(
                from: interval.start,
                to: interval.end
            )
            guard !tastings.isEmpty else {
                loadFailureMessage = "\(period.displayName)还没有可生成的菜品。"
                return
            }
            guard tastings.count <= 7 else {
                loadFailureMessage = "\(period.displayName)共有 \(tastings.count) 道菜，当前模板先支持到 7 道。"
                return
            }

            let lightweightInput = CollageCompositionInput(
                period: period,
                periodStart: interval.start,
                periodEnd: interval.end,
                foods: tastings.map { tasting in
                    CollageFoodInput(
                        id: tasting.id,
                        dishName: tasting.dishDisplayName,
                        cutoutAssetReference: tasting.composedPNGPath,
                        recordedAt: tasting.recordedAt,
                        plateID: tasting.plateID,
                        plateVersion: tasting.plateVersion,
                        analysisImage: nil
                    )
                },
                backgroundCandidates: availableBackgrounds.map { option in
                    CollageBackgroundCandidate(
                        id: option.id,
                        assetReference: "editor-assets/backgrounds/\(option.id).png",
                        tags: CollageEditorAssetLibrary.backgroundTags(for: option.id),
                        analysisImage: nil
                    )
                },
                localeIdentifier: Locale.current.identifier,
                templateCatalogVersion: CollageRuntimeRevision.templateFingerprint
            )
            let fingerprint = CollageInputFingerprint.make(for: lightweightInput)
            inputFingerprint = fingerprint

            if let artifactStore,
               let storedPreview = await artifactStore.loadPreview(
                   period: period,
                   intervalStart: interval.start
               ),
               storedPreview.inputFingerprint == fingerprint {
                openingPreview = UIImage(data: storedPreview.data)
            }

            if let artifactStore,
               let storedScene = await artifactStore.loadScene(
                   period: period,
                   intervalStart: interval.start,
                   inputFingerprint: fingerprint
               ),
               await restore(storedScene, imageStore: imageStore) {
                openingPreview = nil
                return
            }

            var loadedFoods: [(tasting: TastingSnapshot, image: UIImage)] = []
            for tasting in tastings {
                try Task.checkCancellation()
                guard let data = try? await imageStore.data(
                    relativePath: tasting.composedPNGPath
                ), let workingData = ImageDownsampler.pngData(
                    from: data,
                    maxPixelSize: Self.editorWorkingImageMaxPixelSize
                ), let image = UIImage(data: workingData) else {
                    continue
                }
                loadedFoods.append((tasting, image))
            }

            guard !loadedFoods.isEmpty else {
                loadFailureMessage = "暂时无法读取\(period.displayName)的餐盘图。"
                return
            }

            if let generationPlanner {
                let input = CollageCompositionInput(
                    period: period,
                    periodStart: interval.start,
                    periodEnd: interval.end,
                    foods: loadedFoods.map { item in
                        CollageFoodInput(
                            id: item.tasting.id,
                            dishName: item.tasting.dishDisplayName,
                            cutoutAssetReference: item.tasting.composedPNGPath,
                            recordedAt: item.tasting.recordedAt,
                            plateID: item.tasting.plateID,
                            plateVersion: item.tasting.plateVersion,
                            analysisImage: Self.analysisImage(from: item.image)
                        )
                    },
                    backgroundCandidates: availableBackgrounds.map { option in
                        CollageBackgroundCandidate(
                            id: option.id,
                            assetReference: "editor-assets/backgrounds/\(option.id).png",
                            tags: CollageEditorAssetLibrary.backgroundTags(for: option.id),
                            analysisImage: Self.analysisImage(from: option.image)
                        )
                    },
                    localeIdentifier: Locale.current.identifier,
                    templateCatalogVersion: CollageRuntimeRevision.templateFingerprint
                )
                inputFingerprint = CollageInputFingerprint.make(for: input)

                let plan = try await generationPlanner.makePlan(for: input)
                try apply(plan: plan, loadedFoods: loadedFoods)
#if DEBUG
                print("[Collage] scope=\(period.rawValue) template=\(plan.template.code) source=\(plan.intent.reason ?? "remote-ai")")
#endif
            } else {
                applyFallbackLayout(images: loadedFoods.map(\.image))
            }

            openingPreview = nil
            if let artifactStore, let scene = storedSceneSnapshot() {
                try? await artifactStore.saveScene(
                    scene,
                    period: period,
                    intervalStart: interval.start
                )
            }
        } catch is CancellationError {
            return
        } catch {
            loadFailureMessage = "智能拼贴暂时未完成，已保留编辑器。"
        }
    }

    private func apply(
        plan: CollageGenerationPlan,
        loadedFoods: [(tasting: TastingSnapshot, image: UIImage)]
    ) throws {
        selectedTemplateCode = plan.template.code
        generationReason = plan.intent.reason

        if let selectedBackground = availableBackgrounds.first(where: {
            $0.id == plan.intent.backgroundID
        }) {
            backgroundSlots = [
                CollageBackgroundSlot(
                    sourceID: selectedBackground.id,
                    image: loadBundledBackgroundImage(
                        named: selectedBackground.id,
                        maxPixelSize: Self.editorBackgroundMaxPixelSize
                    ) ?? selectedBackground.image
                )
            ]
        }

        let manifestLoader = BundledCollageTemplateManifestLoader()
        let placements = try manifestLoader.subjectPlacements(
            for: plan.template,
            foodCount: loadedFoods.count
        )
        let layerZIndexes = try manifestLoader.layerZIndexes(for: plan.template)
        let subjectLayerIDs = try manifestLoader.subjectLayerIDs(for: plan.template)
        layers = zip(loadedFoods, placements).enumerated().map { index, pair in
            CollageLayer(
                kind: .subject,
                image: pair.0.image,
                assetReference: pair.0.tasting.composedPNGPath,
                center: pair.1.center,
                normalizedWidth: pair.1.width,
                normalizedHeight: pair.1.normalizedHeight,
                rotation: .degrees(pair.1.rotationDegrees),
                zIndex: subjectLayerIDs.indices.contains(index)
                    ? (layerZIndexes[subjectLayerIDs[index]] ?? index + 2)
                    : index + 2
            )
        }

        let fixedDecorations = try manifestLoader.fixedDecorations(
            for: plan.template,
            accentColorHex: plan.intent.mood.accentColor
        )
        layers.append(contentsOf: fixedDecorations.compactMap(Self.templateDecorationLayer))

        let textPlacements = try BundledCollageTemplateTextLayoutLoader()
            .textPlacements(for: plan.template)
        layers.append(
            contentsOf: Self.templateTextLayers(
                from: textPlacements,
                period: period,
                foods: loadedFoods.map(\.tasting),
                caption: plan.intent.copy.caption,
                layerZIndexes: layerZIndexes
            )
        )
    }

    private func applyFallbackLayout(images: [UIImage]) {
        layers = images.enumerated().map { index, image in
            let placement = Self.subjectPlacement(index: index, count: images.count)
            return CollageLayer(
                kind: .subject,
                image: image,
                center: placement.center,
                normalizedWidth: placement.width,
                rotation: .degrees(placement.rotation),
                zIndex: index + 1
            )
        }
    }

    func storedSceneSnapshot() -> StoredCollageScene? {
        guard let inputFingerprint else { return nil }
        let bundledBackgroundIDs = Set(availableBackgrounds.map(\.id))
        return StoredCollageScene(
            version: StoredCollageScene.currentVersion,
            inputFingerprint: inputFingerprint,
            templateCode: selectedTemplateCode,
            generationReason: generationReason,
            isSplitBackground: isSplitBackground,
            splitFraction: Double(splitFraction),
            backgrounds: backgroundSlots.map { slot in
                StoredCollageScene.Background(
                    id: slot.id,
                    sourceID: slot.sourceID,
                    embeddedPNGData: slot.sourceID.map(bundledBackgroundIDs.contains) == true
                        ? nil
                        : slot.image?.pngData(),
                    offsetX: Double(slot.offset.width),
                    offsetY: Double(slot.offset.height),
                    scale: Double(slot.scale),
                    opacity: slot.opacity
                )
            },
            layers: layers.map { layer in
                StoredCollageScene.Layer(
                    id: layer.id,
                    kind: layer.kind.rawValue,
                    assetReference: layer.assetReference,
                    embeddedPNGData: layer.assetReference == nil
                        || layer.assetReference?.hasPrefix("template-decoration://") == true
                        ? layer.image?.pngData()
                        : nil,
                    text: layer.text,
                    centerX: Double(layer.center.x),
                    centerY: Double(layer.center.y),
                    normalizedWidth: Double(layer.normalizedWidth),
                    normalizedHeight: layer.normalizedHeight.map(Double.init),
                    scale: Double(layer.scale),
                    contentScale: Double(layer.contentScale),
                    contentOffsetX: Double(layer.contentOffset.width),
                    contentOffsetY: Double(layer.contentOffset.height),
                    rotationDegrees: layer.rotation.degrees,
                    opacity: layer.opacity,
                    zIndex: layer.zIndex,
                    isEditable: layer.isEditable,
                    isDeletable: layer.isDeletable,
                    textFont: layer.textFont.rawValue,
                    isTextBold: layer.isTextBold,
                    isTextItalic: layer.isTextItalic,
                    textAlignment: layer.textAlignment.rawValue,
                    textColor: Self.storedColor(layer.textColor),
                    textBackground: layer.textBackground.map(Self.storedColor),
                    textFrameHeight: layer.textFrameHeight.map(Double.init),
                    textFontSizeRatio: layer.textFontSizeRatio.map(Double.init),
                    textLineHeightMultiple: layer.textLineHeightMultiple.map(Double.init),
                    textMaximumLines: layer.textMaximumLines,
                    textOverflow: layer.textOverflow?.rawValue
                )
            },
            savedAt: .now
        )
    }

    private func restore(
        _ scene: StoredCollageScene,
        imageStore: any ImageFileStoring
    ) async -> Bool {
        var restoredBackgrounds: [CollageBackgroundSlot] = []
        for stored in scene.backgrounds {
            let image: UIImage?
            if let sourceID = stored.sourceID,
               availableBackgrounds.contains(where: { $0.id == sourceID }) {
                image = loadBundledBackgroundImage(
                    named: sourceID,
                    maxPixelSize: Self.editorBackgroundMaxPixelSize
                )
            } else {
                image = stored.embeddedPNGData.flatMap(UIImage.init(data:))
            }
            let restoresTransform = scene.isSplitBackground
            restoredBackgrounds.append(
                CollageBackgroundSlot(
                    id: stored.id,
                    sourceID: stored.sourceID,
                    image: image,
                    offset: restoresTransform
                        ? CGSize(width: stored.offsetX, height: stored.offsetY)
                        : .zero,
                    scale: restoresTransform ? CGFloat(stored.scale) : 1,
                    opacity: stored.opacity ?? 1
                )
            )
        }

        var restoredLayers: [CollageLayer] = []
        for stored in scene.layers {
            guard let kind = CollageLayerKind(rawValue: stored.kind) else { return false }
            let image: UIImage?
            if stored.assetReference?.hasPrefix("template-decoration://") == true {
                image = stored.embeddedPNGData.flatMap(UIImage.init(data:))
            } else if let assetReference = stored.assetReference,
               let data = try? await imageStore.data(relativePath: assetReference),
               let workingData = ImageDownsampler.pngData(
                   from: data,
                   maxPixelSize: Self.editorWorkingImageMaxPixelSize
               ) {
                image = UIImage(data: workingData)
            } else {
                image = stored.embeddedPNGData.flatMap(UIImage.init(data:))
            }
            if kind != .text, image == nil { return false }

            restoredLayers.append(
                CollageLayer(
                    id: stored.id,
                    kind: kind,
                    image: image,
                    assetReference: stored.assetReference,
                    text: stored.text,
                    center: CGPoint(x: stored.centerX, y: stored.centerY),
                    normalizedWidth: CGFloat(stored.normalizedWidth),
                    normalizedHeight: stored.normalizedHeight.map { CGFloat($0) },
                    scale: CGFloat(stored.scale),
                    contentScale: CGFloat(stored.contentScale),
                    contentOffset: CGSize(
                        width: stored.contentOffsetX,
                        height: stored.contentOffsetY
                    ),
                    rotation: .degrees(stored.rotationDegrees),
                    opacity: stored.opacity,
                    zIndex: stored.zIndex,
                    isEditable: stored.isEditable ?? true,
                    isDeletable: stored.isDeletable ?? true,
                    textFont: CollageTextFont(rawValue: stored.textFont) ?? .lingHui,
                    isTextBold: stored.isTextBold,
                    isTextItalic: stored.isTextItalic ?? false,
                    textAlignment: CollageTextAlignment(rawValue: stored.textAlignment) ?? .center,
                    textColor: Self.colorValue(stored.textColor),
                    textBackground: stored.textBackground.map(Self.colorValue),
                    textFrameHeight: stored.textFrameHeight.map { CGFloat($0) },
                    textFontSizeRatio: stored.textFontSizeRatio.map { CGFloat($0) },
                    textLineHeightMultiple: stored.textLineHeightMultiple.map { CGFloat($0) },
                    textMaximumLines: stored.textMaximumLines,
                    textOverflow: stored.textOverflow.flatMap(CollageTextOverflow.init(rawValue:))
                )
            )
        }

        selectedTemplateCode = scene.templateCode
        generationReason = scene.generationReason
        isSplitBackground = scene.isSplitBackground
        splitFraction = CGFloat(scene.splitFraction)
        backgroundSlots = restoredBackgrounds
        layers = restoredLayers
        selectedLayerID = nil
        cropEditingLayerID = nil
        return !layers.isEmpty
    }

    private static func storedColor(_ color: CollageColorValue) -> StoredCollageScene.Color {
        StoredCollageScene.Color(
            name: color.name,
            red: color.red,
            green: color.green,
            blue: color.blue,
            opacity: color.opacity
        )
    }

    private static func colorValue(_ color: StoredCollageScene.Color) -> CollageColorValue {
        CollageColorValue(
            name: color.name,
            red: color.red,
            green: color.green,
            blue: color.blue,
            opacity: color.opacity
        )
    }

    private static func analysisImage(from image: UIImage) -> CollageAnalysisImage? {
        let maximumDimension: CGFloat = 512
        let sourceSize = image.size
        guard sourceSize.width > 0, sourceSize.height > 0 else { return nil }
        let ratio = min(1, maximumDimension / max(sourceSize.width, sourceSize.height))
        let targetSize = CGSize(
            width: max(1, (sourceSize.width * ratio).rounded()),
            height: max(1, (sourceSize.height * ratio).rounded())
        )
        let renderer = UIGraphicsImageRenderer(size: targetSize)
        let flattened = renderer.image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: targetSize))
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }
        guard let data = flattened.jpegData(compressionQuality: 0.68) else { return nil }
        return CollageAnalysisImage(
            mimeType: "image/jpeg",
            imageBase64: data.base64EncodedString()
        )
    }

    private static func templateTextLayers(
        from placements: [CollageTemplateTextPlacement],
        period: JournalCollagePeriod,
        foods: [TastingSnapshot],
        caption: String?,
        layerZIndexes: [String: Int]
    ) -> [CollageLayer] {
        placements.map { placement in
            CollageLayer(
                kind: .text,
                text: resolvedText(
                    for: placement,
                    period: period,
                    foods: foods,
                    caption: caption
                ),
                center: placement.center,
                normalizedWidth: placement.normalizedWidth,
                rotation: .degrees(placement.rotationDegrees),
                zIndex: layerZIndexes[placement.id] ?? placement.zIndex,
                textFont: templateFont(named: placement.fontFamily),
                isTextBold: placement.isBold,
                isTextItalic: placement.fontStyle.localizedCaseInsensitiveContains("italic"),
                textAlignment: templateTextAlignment(named: placement.alignment),
                textColor: colorValue(hex: placement.colorHex) ?? .black,
                textFrameHeight: placement.normalizedHeight,
                textFontSizeRatio: placement.fontSizeRatio,
                textLineHeightMultiple: placement.lineHeightMultiple,
                textMaximumLines: placement.maximumLines,
                textOverflow: CollageTextOverflow(rawValue: placement.overflow) ?? .clip
            )
        }
    }

    private static func templateDecorationLayer(
        _ decoration: CollageTemplateFixedDecoration
    ) -> CollageLayer? {
        guard decoration.kind != "subject_clip_window" else { return nil }
        guard let color = colorValue(hex: decoration.colorHex),
              let image = templateDecorationImage(decoration, color: color) else {
            return nil
        }
        return CollageLayer(
            kind: decoration.kind == "outline" ? .outline : .sticker,
            image: image,
            assetReference: "template-decoration://\(decoration.id)",
            center: decoration.center,
            normalizedWidth: decoration.normalizedWidth,
            normalizedHeight: decoration.normalizedHeight,
            rotation: .degrees(decoration.rotationDegrees),
            opacity: decoration.opacity,
            zIndex: decoration.zIndex,
            isEditable: decoration.editable,
            isDeletable: decoration.deletable
        )
    }

    private static func templateDecorationImage(
        _ decoration: CollageTemplateFixedDecoration,
        color: CollageColorValue
    ) -> UIImage? {
        let pixelWidth: CGFloat = 804
        let aspect = decoration.normalizedHeight
            / max(decoration.normalizedWidth, 0.001)
            * (4.0 / 3.0)
        let size = CGSize(width: pixelWidth, height: max(1, pixelWidth * aspect))
        let renderer = UIGraphicsImageRenderer(size: size)
        if decoration.id == "s-curve-dash-01",
           let source = UIImage(named: "sticker.s-curve-dash-01") {
            return source.withTintColor(color.uiColor, renderingMode: .alwaysOriginal)
        }
        if decoration.id == "food-spark-01" {
            return renderer.image { context in
                let scaleX = size.width / 96
                let scaleY = size.height / 64
                context.cgContext.scaleBy(x: scaleX, y: scaleY)
                color.uiColor.setFill()
                UIBezierPath(
                    polygon: [
                        .init(x: 31, y: 8), .init(x: 35, y: 21), .init(x: 48, y: 25),
                        .init(x: 35, y: 29), .init(x: 31, y: 42), .init(x: 27, y: 29),
                        .init(x: 14, y: 25), .init(x: 27, y: 21)
                    ]
                ).fill()
                UIBezierPath(
                    polygon: [
                        .init(x: 67, y: 20), .init(x: 70, y: 29), .init(x: 79, y: 32),
                        .init(x: 70, y: 35), .init(x: 67, y: 44), .init(x: 64, y: 35),
                        .init(x: 55, y: 32), .init(x: 64, y: 29)
                    ]
                ).fill()
                UIColor(red: 244 / 255, green: 161 / 255, blue: 93 / 255, alpha: 1).setFill()
                let orange = UIBezierPath()
                orange.move(to: .init(x: 63, y: 47))
                orange.addCurve(to: .init(x: 86, y: 52), controlPoint1: .init(x: 71, y: 40), controlPoint2: .init(x: 81, y: 42))
                orange.addCurve(to: .init(x: 63, y: 47), controlPoint1: .init(x: 77, y: 56), controlPoint2: .init(x: 68, y: 54))
                orange.fill()
                UIColor(red: 144 / 255, green: 188 / 255, blue: 121 / 255, alpha: 1).setFill()
                let green = UIBezierPath()
                green.move(to: .init(x: 63, y: 47))
                green.addCurve(to: .init(x: 43, y: 48), controlPoint1: .init(x: 57, y: 39), controlPoint2: .init(x: 48, y: 40))
                green.addCurve(to: .init(x: 63, y: 47), controlPoint1: .init(x: 50, y: 54), controlPoint2: .init(x: 58, y: 53))
                green.fill()
            }
        }
        if let path = decoration.assetFilePath,
           let image = UIImage(contentsOfFile: path) {
            return image
        }
        if let image = decoration.assetReference
            .flatMap(Self.templateAssetName)
            .flatMap(UIImage.init(named:)) {
            return image
        }
        if let drawable = decoration.drawable {
            return templateDrawableImage(
                drawable,
                decoration: decoration,
                defaultColor: color,
                size: size,
                renderer: renderer
            )
        }
        if decoration.kind == "outline" {
            return renderer.image { context in
                let lineWidth = max(
                    1,
                    (decoration.strokeWidthRatio ?? 0.01) / decoration.normalizedWidth * size.width
                )
                context.cgContext.setStrokeColor(color.uiColor.cgColor)
                context.cgContext.setLineWidth(lineWidth)
                context.cgContext.strokeEllipse(
                    in: CGRect(origin: .zero, size: size).insetBy(dx: lineWidth / 2, dy: lineWidth / 2)
                )
            }
        }
        return nil
    }

    private static func templateDrawableImage(
        _ drawable: CollageTemplateDrawable,
        decoration: CollageTemplateFixedDecoration,
        defaultColor: CollageColorValue,
        size: CGSize,
        renderer: UIGraphicsImageRenderer
    ) -> UIImage {
        renderer.image { context in
            let bounds = CGRect(origin: .zero, size: size)
            let shape = drawable.shape ?? ""
            let fillColor = drawable.fillHex.flatMap { Self.uiColor(hex: $0) }
                ?? defaultColor.uiColor
            let path: UIBezierPath
            switch shape {
            case "ellipse", "rough_circle":
                path = UIBezierPath(ovalIn: bounds)
            case "rounded_rectangle":
                path = UIBezierPath(
                    roundedRect: bounds,
                    cornerRadius: drawable.cornerRadiusRatio * size.width
                )
            case "four_point_spark":
                path = UIBezierPath(
                    polygon: [
                        CGPoint(x: size.width * 0.5, y: 0),
                        CGPoint(x: size.width * 0.62, y: size.height * 0.38),
                        CGPoint(x: size.width, y: size.height * 0.5),
                        CGPoint(x: size.width * 0.62, y: size.height * 0.62),
                        CGPoint(x: size.width * 0.5, y: size.height),
                        CGPoint(x: size.width * 0.38, y: size.height * 0.62),
                        CGPoint(x: 0, y: size.height * 0.5),
                        CGPoint(x: size.width * 0.38, y: size.height * 0.38)
                    ]
                )
            default:
                path = UIBezierPath(rect: bounds)
            }

            if drawable.fillHex != nil, drawable.fillHex != "transparent" {
                fillColor.setFill()
                path.fill()
            }

            if shape == "polaroid_square" || shape == "polaroid_wide" {
                fillColor.setFill()
                UIBezierPath(rect: bounds).fill()
                if let backer = drawable.innerBacker,
                   let backerColor = uiColor(hex: backer.colorHex) {
                    backerColor.setFill()
                    UIBezierPath(
                        rect: CGRect(
                            x: backer.frame.minX * size.width,
                            y: backer.frame.minY * size.height,
                            width: backer.frame.width * size.width,
                            height: backer.frame.height * size.height
                        )
                    ).fill()
                }
            }

            if !drawable.strokeLayers.isEmpty {
                for layer in drawable.strokeLayers {
                    let width = max(
                        1,
                        layer.widthRatio / max(decoration.normalizedWidth, 0.001) * size.width
                    )
                    let strokePath = UIBezierPath(
                        ovalIn: bounds.insetBy(dx: width / 2, dy: width / 2)
                    )
                    strokePath.lineWidth = width
                    (uiColor(hex: layer.colorHex) ?? defaultColor.uiColor)
                        .withAlphaComponent(layer.opacity)
                        .setStroke()
                    strokePath.stroke()
                }
            }

            if let stroke = drawable.stroke {
                let lineWidth = max(
                    1,
                    stroke.widthRatio / max(decoration.normalizedWidth, 0.001) * size.width
                )
                path.lineWidth = lineWidth
                if !stroke.dashPattern.isEmpty {
                    let dash = stroke.dashPattern.map {
                        $0 / max(decoration.normalizedWidth, 0.001) * size.width
                    }
                    path.setLineDash(dash, count: dash.count, phase: 0)
                }
                (stroke.colorHex.flatMap { Self.uiColor(hex: $0) } ?? defaultColor.uiColor)
                    .setStroke()
                path.stroke()
            }

            if drawable.shape == nil, drawable.curve != nil {
                let lineWidth = max(
                    1,
                    (drawable.stroke?.widthRatio ?? 0.004)
                        / max(decoration.normalizedWidth, 0.001) * size.width
                )
                let curve = UIBezierPath()
                curve.move(to: CGPoint(x: lineWidth, y: size.height * 0.5))
                curve.addCurve(
                    to: CGPoint(x: size.width - lineWidth, y: size.height * 0.5),
                    controlPoint1: CGPoint(x: size.width * 0.28, y: 0),
                    controlPoint2: CGPoint(x: size.width * 0.72, y: size.height)
                )
                curve.lineWidth = lineWidth
                (drawable.stroke?.colorHex.flatMap { Self.uiColor(hex: $0) } ?? defaultColor.uiColor)
                    .setStroke()
                curve.stroke()
            }

            if decoration.kind == "connector_path", drawable.shape == nil, drawable.curve == nil {
                let lineWidth = max(
                    1,
                    (drawable.stroke?.widthRatio ?? 0.004)
                        / max(decoration.normalizedWidth, 0.001) * size.width
                )
                let connector = UIBezierPath()
                connector.move(to: CGPoint(x: 0, y: 0))
                connector.addLine(to: CGPoint(x: size.width * 0.5, y: size.height * 0.5))
                connector.addLine(to: CGPoint(x: size.width, y: size.height))
                connector.lineWidth = lineWidth
                connector.lineCapStyle = .round
                (drawable.stroke?.colorHex.flatMap { Self.uiColor(hex: $0) } ?? defaultColor.uiColor)
                    .setStroke()
                connector.stroke()
            }

            context.cgContext.setBlendMode(.normal)
        }
    }

    private static func uiColor(hex: String) -> UIColor? {
        colorValue(hex: hex)?.uiColor
    }

    private static func templateAssetName(_ reference: String) -> String? {
        let name = URL(fileURLWithPath: reference).deletingPathExtension().lastPathComponent
        return name.isEmpty ? nil : "sticker.\(name)"
    }

    private static func resolvedText(
        for placement: CollageTemplateTextPlacement,
        period: JournalCollagePeriod,
        foods: [TastingSnapshot],
        caption: String?
    ) -> String {
        let trimmedCaption = caption?.trimmingCharacters(in: .whitespacesAndNewlines)
        switch placement.binding {
        case "period":
            return placement.periodValues[period.rawValue] ?? placement.defaultText ?? ""
        case "caption", "user_caption":
            return (trimmedCaption?.isEmpty == false ? trimmedCaption : placement.defaultText) ?? ""
        case "dish_name_a", "dish_name_b", "dish_name_c", "dish_name_d", "dish_name_e":
            let index = placement.binding.last.flatMap { suffix in
                ["a", "b", "c", "d", "e"].firstIndex(of: String(suffix))
            }
            return index.flatMap { foods.indices.contains($0) ? foods[$0].dishDisplayName : nil }
                ?? placement.defaultText
                ?? ""
        case "time":
            guard let date = foods.last?.recordedAt else { return placement.defaultText ?? "" }
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "HH:mm a"
            return formatter.string(from: date).lowercased()
        case "date_label":
            guard let date = foods.last?.recordedAt else { return placement.defaultText ?? "" }
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "yyyy\nMMMM"
            return formatter.string(from: date)
        default:
            guard let defaultText = placement.defaultText else { return "" }
            guard let repeatedLineCount = placement.repeatedLineCount else { return defaultText }
            return Array(repeating: defaultText, count: repeatedLineCount).joined(separator: "\n")
        }
    }

    private static func templateFont(named family: String) -> CollageTextFont {
        switch family {
        case "黑体-简": .heiti
        case "American Typewriter": .americanTypewriter
        case "BM Yeonsung": .bmYeonsung
        case "Georgia": .georgia
        case "Coming Soon": .comingSoon
        default: .heiti
        }
    }

    private static func templateTextAlignment(named alignment: String) -> CollageTextAlignment {
        switch alignment.uppercased() {
        case "CENTER": .center
        case "RIGHT", "TRAILING": .trailing
        default: .leading
        }
    }

    private static func colorValue(hex: String) -> CollageColorValue? {
        let value = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard value.count == 6, let integer = Int(value, radix: 16) else { return nil }
        return CollageColorValue(
            name: "AI 点缀色",
            red: Double((integer >> 16) & 0xFF) / 255,
            green: Double((integer >> 8) & 0xFF) / 255,
            blue: Double(integer & 0xFF) / 255
        )
    }

    func beginHistoryTransaction() {
        guard pendingHistorySnapshot == nil else { return }
        pendingHistorySnapshot = makeEditorSnapshot()
    }

    func commitHistoryTransaction() {
        guard let before = pendingHistorySnapshot else { return }
        pendingHistorySnapshot = nil
        guard !before.isEquivalent(to: makeEditorSnapshot()) else { return }
        undoHistory.append(before)
        if undoHistory.count > 20 {
            undoHistory.removeFirst(undoHistory.count - 20)
        }
        withdrawnUndoHistory.removeAll()
    }

    func cancelHistoryTransaction() {
        pendingHistorySnapshot = nil
    }

    func performHistoryEdit(_ edit: () -> Void) {
        beginHistoryTransaction()
        edit()
        commitHistoryTransaction()
    }

    func undo() {
        guard let previous = undoHistory.popLast() else { return }
        let current = makeEditorSnapshot()
        previous.restore(into: self)
        withdrawnUndoHistory.append(current)
        if withdrawnUndoHistory.count > 20 {
            withdrawnUndoHistory.removeFirst(withdrawnUndoHistory.count - 20)
        }
        pendingHistorySnapshot = nil
    }

    /// Withdraws the latest undo. This is intentionally named “撤回” in the UI.
    func withdrawUndo() {
        guard let next = withdrawnUndoHistory.popLast() else { return }
        let current = makeEditorSnapshot()
        next.restore(into: self)
        undoHistory.append(current)
        if undoHistory.count > 20 {
            undoHistory.removeFirst(undoHistory.count - 20)
        }
        pendingHistorySnapshot = nil
    }

    private func makeEditorSnapshot() -> EditorSnapshot {
        EditorSnapshot(
            backgrounds: backgroundSlots.map(BackgroundSlotDraft.init),
            isSplitBackground: isSplitBackground,
            splitFraction: splitFraction,
            activeBackgroundIndex: activeBackgroundIndex,
            layers: layers.map(LayerDraft.init),
            selectedLayerID: selectedLayerID
        )
    }

    func selectLayer(_ id: UUID?) {
        if cropEditingLayerID != id {
            cropEditingLayerID = nil
        }
        selectedLayerID = id
        if id != nil {
            activeBackgroundIndex = 0
        }
    }

    func selectLayer(at location: CGPoint, canvasSize: CGSize) {
        let candidates = orderedLayers
            .reversed()
            .filter { layer in
                layer.isEditable
                    && layer.interactionFrame(in: canvasSize)
                        .insetBy(dx: -10, dy: -10)
                        .contains(location)
            }
            .map(\.id)

        guard !candidates.isEmpty else {
            selectLayer(nil)
            lastSelectionPoint = nil
            lastSelectionCandidates = []
            lastSelectionIndex = 0
            return
        }

        let repeatsSamePoint = lastSelectionPoint.map {
            hypot($0.x - location.x, $0.y - location.y) <= 18
        } ?? false
        if repeatsSamePoint, candidates == lastSelectionCandidates {
            lastSelectionIndex = (lastSelectionIndex + 1) % candidates.count
        } else {
            lastSelectionIndex = 0
        }
        lastSelectionPoint = location
        lastSelectionCandidates = candidates
        selectLayer(candidates[lastSelectionIndex])
    }

    func beginCropEditing(_ id: UUID) {
        guard let layer = layer(for: id),
              layer.image != nil,
              layer.isEditable,
              layer.kind != .outline,
              layer.kind != .text else { return }
        beginHistoryTransaction()
        if layer.normalizedHeight == nil {
            setCropAspectRatio(nil, for: layer)
        }
        selectedLayerID = id
        cropEditingLayerID = id
        presentedPanel = nil
    }

    func setSelectedCropAspectRatio(_ widthToHeight: CGFloat?) {
        guard let layer = selectedLayer, cropEditingLayerID == layer.id else { return }
        setCropAspectRatio(widthToHeight, for: layer)
        layer.contentOffset = .zero
    }

    private func setCropAspectRatio(_ widthToHeight: CGFloat?, for layer: CollageLayer) {
        guard let image = layer.image, image.size.width > 0, image.size.height > 0 else { return }
        let ratio = widthToHeight ?? (image.size.width / image.size.height)
        guard ratio > 0 else { return }
        // Width is normalized to canvas width and height to canvas height.
        // The working canvas is 3:4, so W/H contributes a factor of 3/4.
        layer.normalizedHeight = layer.normalizedWidth * 0.75 / ratio
        layer.contentScale = 1
    }

    func finishCropEditing() {
        cropEditingLayerID = nil
        commitHistoryTransaction()
    }

    func resetCrop() {
        guard let layer = selectedLayer, layer.normalizedHeight != nil else { return }
        layer.contentScale = 1
        layer.contentOffset = .zero
    }

    func selectBackgroundSlot(_ index: Int) {
        guard backgroundSlots.indices.contains(index) else { return }
        activeBackgroundIndex = index
        selectedLayerID = nil
    }

    func toggleBackgroundMode() {
        beginHistoryTransaction()
        if isSplitBackground {
            isSplitBackground = false
            if backgroundSlots.count > 1 {
                backgroundSlots.removeSubrange(1...)
            }
            activeBackgroundIndex = 0
            splitFraction = 0.5
            resetSingleBackgroundTransform()
        } else {
            isSplitBackground = true
            if backgroundSlots.count < 2 {
                backgroundSlots.append(CollageBackgroundSlot())
            }
            activeBackgroundIndex = 1
        }
        selectedLayerID = nil
        commitHistoryTransaction()
    }

    func updateSplitFraction(_ value: CGFloat) {
        splitFraction = min(max(value, 0.22), 0.78)
    }

    func openBackgroundPanel() {
        beginHistoryTransaction()
        backgroundDraft = BackgroundDraft(
            slots: backgroundSlots.map(BackgroundSlotDraft.init),
            isSplit: isSplitBackground,
            splitFraction: splitFraction,
            activeIndex: activeBackgroundIndex
        )
        presentedPanel = .background
        selectedLayerID = nil
    }

    func beginBackgroundCompositionEditing() {
        guard canAdjustBackgroundComposition else { return }
        backgroundCompositionDraft = BackgroundDraft(
            slots: backgroundSlots.map(BackgroundSlotDraft.init),
            isSplit: isSplitBackground,
            splitFraction: splitFraction,
            activeIndex: activeBackgroundIndex
        )
        backgroundDraft = nil
        presentedPanel = nil
        selectedLayerID = nil
        cropEditingLayerID = nil
        isEditingBackgroundComposition = true
    }

    func cancelBackgroundCompositionEditing() {
        if let backgroundCompositionDraft {
            isSplitBackground = backgroundCompositionDraft.isSplit
            splitFraction = backgroundCompositionDraft.splitFraction
            activeBackgroundIndex = backgroundCompositionDraft.activeIndex
            backgroundSlots = backgroundCompositionDraft.slots.map { $0.restoredSlot }
        }
        backgroundCompositionDraft = nil
        isEditingBackgroundComposition = false
        cancelHistoryTransaction()
    }

    func confirmBackgroundCompositionEditing() {
        backgroundCompositionDraft = nil
        isEditingBackgroundComposition = false
        commitHistoryTransaction()
    }

    func applyBackground(_ option: CollageBackgroundOption) {
        guard backgroundSlots.indices.contains(activeBackgroundIndex) else { return }
        let slot = backgroundSlots[activeBackgroundIndex]
        slot.sourceID = option.id
        slot.image = loadBundledBackgroundImage(
            named: option.id,
            maxPixelSize: Self.editorBackgroundMaxPixelSize
        ) ?? option.image
        slot.offset = .zero
        slot.scale = 1
    }

    func applyCustomBackground(_ image: UIImage) {
        guard backgroundSlots.indices.contains(activeBackgroundIndex) else { return }
        let slot = backgroundSlots[activeBackgroundIndex]
        slot.sourceID = "custom-\(UUID().uuidString)"
        slot.image = image
        slot.offset = .zero
        slot.scale = 1
    }

    func cancelBackgroundPanel() {
        if let backgroundDraft {
            isSplitBackground = backgroundDraft.isSplit
            splitFraction = backgroundDraft.splitFraction
            activeBackgroundIndex = backgroundDraft.activeIndex
            backgroundSlots = backgroundDraft.slots.map { $0.restoredSlot }
            if !isSplitBackground {
                resetSingleBackgroundTransform()
            }
        }
        backgroundDraft = nil
        presentedPanel = nil
        cancelHistoryTransaction()
    }

    func confirmBackgroundPanel() {
        if !isSplitBackground {
            resetSingleBackgroundTransform()
        }
        backgroundDraft = nil
        presentedPanel = nil
        commitHistoryTransaction()
    }

    private func resetSingleBackgroundTransform() {
        guard !isSplitBackground, let slot = backgroundSlots.first else { return }
        slot.offset = .zero
        slot.scale = 1
    }

    func openStickerPanel() {
        presentedPanel = .sticker
    }

    func addSticker(_ option: CollageStickerOption) {
        beginHistoryTransaction()
        let layer = CollageLayer(
            kind: .sticker,
            image: option.image,
            center: CGPoint(x: 0.5, y: 0.5),
            normalizedWidth: 0.28,
            rotation: .degrees(-4),
            zIndex: nextZIndex
        )
        layers.append(layer)
        selectedLayerID = layer.id
        presentedPanel = nil
        commitHistoryTransaction()
    }

    func closeTransientPanel() {
        presentedPanel = nil
    }

    func addOverlay(_ image: UIImage) {
        beginHistoryTransaction()
        let layer = CollageLayer(
            kind: .overlay,
            image: image,
            center: CGPoint(x: 0.5, y: 0.5),
            normalizedWidth: 0.46,
            zIndex: nextZIndex
        )
        layers.append(layer)
        selectedLayerID = layer.id
        commitHistoryTransaction()
    }

    func beginTextEditing() -> UUID {
        beginHistoryTransaction()
        let layer: CollageLayer
        if let selectedLayer, selectedLayer.kind == .text {
            layer = selectedLayer
            newlyCreatedTextID = nil
        } else {
            layer = CollageLayer(
                kind: .text,
                text: "输入文字",
                center: CGPoint(x: 0.5, y: 0.72),
                normalizedWidth: 0.72,
                zIndex: nextZIndex,
                textFont: .lingHui,
                textAlignment: .center,
                textColor: .brown
            )
            layers.append(layer)
            selectedLayerID = layer.id
            newlyCreatedTextID = layer.id
        }
        textDraft = TextDraft(layer: layer)
        return layer.id
    }

    func cancelTextEditing(_ id: UUID) {
        if newlyCreatedTextID == id {
            layers.removeAll { $0.id == id }
            selectedLayerID = nil
        } else if let textDraft, let layer = layers.first(where: { $0.id == id }) {
            textDraft.restore(into: layer)
        }
        newlyCreatedTextID = nil
        textDraft = nil
        cancelHistoryTransaction()
    }

    func confirmTextEditing(_ id: UUID) {
        if let layer = layers.first(where: { $0.id == id }),
           layer.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            layers.removeAll { $0.id == id }
            selectedLayerID = nil
        }
        newlyCreatedTextID = nil
        textDraft = nil
        commitHistoryTransaction()
    }

    func layer(for id: UUID) -> CollageLayer? {
        layers.first { $0.id == id }
    }

    func beginLayerDrag(_ id: UUID, location: CGPoint) {
        guard let layer = layer(for: id) else { return }
        beginHistoryTransaction()
        selectedLayerID = id
        presentedPanel = nil
        isDraggingLayer = true
        isOverTrash = false
        dragStart = DragStart(finger: location, center: layer.center)
        lastDragLocation = location
    }

    func updateLayerDrag(_ id: UUID, location: CGPoint, canvasSize: CGSize) {
        guard let layer = layer(for: id), let dragStart else { return }

        isOverTrash = Self.isTrashLocation(location, canvasSize: canvasSize)
        if !isOverTrash {
            let translation = CGSize(
                width: location.x - dragStart.finger.x,
                height: location.y - dragStart.finger.y
            )
            layer.center = CGPoint(
                x: min(max(dragStart.center.x + translation.width / canvasSize.width, 0), 1),
                y: min(max(dragStart.center.y + translation.height / canvasSize.height, 0), 1)
            )

        }
        lastDragLocation = location
    }

    func endLayerDrag(_ id: UUID) {
        if isOverTrash {
            deleteLayer(id)
        }
        isDraggingLayer = false
        isOverTrash = false
        dragStart = nil
        lastDragLocation = nil
        commitHistoryTransaction()
    }

    enum LayerStepDirection {
        case up
        case down
    }

    func moveLayerOneStep(_ id: UUID, direction: LayerStepDirection) {
        let ordered = orderedLayers
        guard let index = ordered.firstIndex(where: { $0.id == id }) else { return }
        let targetIndex: Int
        switch direction {
        case .up:
            targetIndex = index + 1
        case .down:
            targetIndex = index - 1
        }
        guard ordered.indices.contains(targetIndex) else { return }
        performHistoryEdit {
            let sourceZ = ordered[index].zIndex
            ordered[index].zIndex = ordered[targetIndex].zIndex
            ordered[targetIndex].zIndex = sourceZ
        }
        reorderFeedbackCounter += 1
    }

    func deleteLayer(_ id: UUID) {
        layers.removeAll { $0.id == id && $0.isDeletable }
        if selectedLayerID == id {
            selectedLayerID = nil
        }
    }

    private var nextZIndex: Int {
        (layers.map { $0.zIndex }.max() ?? 0) + 1
    }

    private func loadBundledBackgrounds() {
        var loaded: [CollageBackgroundOption] = []
        for name in CollageEditorAssetLibrary.backgroundNames {
            guard let image = loadBundledBackgroundImage(
                named: name,
                maxPixelSize: Self.editorBackgroundThumbnailMaxPixelSize
            ) else {
                continue
            }
            loaded.append(CollageBackgroundOption(id: name, image: image))
        }
        availableBackgrounds = loaded

        if let first = availableBackgrounds.first {
            backgroundSlots = [
                CollageBackgroundSlot(
                    sourceID: first.id,
                    image: loadBundledBackgroundImage(
                        named: first.id,
                        maxPixelSize: Self.editorBackgroundMaxPixelSize
                    ) ?? first.image
                )
            ]
        } else {
            backgroundSlots = [CollageBackgroundSlot()]
        }
    }

    private func loadBundledBackgroundImage(
        named name: String,
        maxPixelSize: Int
    ) -> UIImage? {
        guard let url = Bundle.main.url(
            forResource: name,
            withExtension: "png",
            subdirectory: "editor-assets/backgrounds"
        ), let sourceData = try? Data(contentsOf: url),
          let workingData = ImageDownsampler.pngData(
            from: sourceData,
            maxPixelSize: maxPixelSize
          ) else {
            return nil
        }
        return UIImage(data: workingData)
    }

    private func loadBundledStickers() {
        guard let url = Bundle.main.url(
            forResource: "sticker-catalog.v1",
            withExtension: "json",
            subdirectory: "app-contract"
        ), let data = try? Data(contentsOf: url),
          let catalog = try? JSONDecoder().decode(StickerCatalog.self, from: data) else {
            stickerOptions = []
            return
        }
        stickerOptions = catalog.stickers.compactMap { sticker in
            guard let image = UIImage(named: sticker.assetName) else { return nil }
            return CollageStickerOption(
                id: sticker.id,
                image: image
            )
        }
    }

    private static func isTrashLocation(_ location: CGPoint, canvasSize: CGSize) -> Bool {
        location.y >= canvasSize.height - 4
            && abs(location.x - canvasSize.width / 2) <= 72
    }


    private static func subjectPlacement(index: Int, count: Int) -> SubjectPlacement {
        switch count {
        case 0:
            return SubjectPlacement(center: CGPoint(x: 0.5, y: 0.48), width: 0.55, rotation: 0)
        case 1:
            return SubjectPlacement(center: CGPoint(x: 0.5, y: 0.48), width: 0.62, rotation: -2)
        case 2:
            return index == 0
                ? SubjectPlacement(center: CGPoint(x: 0.43, y: 0.43), width: 0.56, rotation: -4)
                : SubjectPlacement(center: CGPoint(x: 0.67, y: 0.63), width: 0.4, rotation: 5)
        case 3:
            return [
                SubjectPlacement(center: CGPoint(x: 0.43, y: 0.39), width: 0.52, rotation: -3),
                SubjectPlacement(center: CGPoint(x: 0.7, y: 0.6), width: 0.34, rotation: 6),
                SubjectPlacement(center: CGPoint(x: 0.27, y: 0.68), width: 0.31, rotation: -7)
            ][min(index, 2)]
        default:
            if index == 0 {
                return SubjectPlacement(
                    center: CGPoint(x: 0.48, y: 0.47),
                    width: 0.48,
                    rotation: -2
                )
            }
            let angle = Double(index - 1) / Double(max(1, count - 1)) * .pi * 2 - .pi / 2
            let radiusX = 0.3
            let radiusY = 0.27
            return SubjectPlacement(
                center: CGPoint(
                    x: 0.5 + CGFloat(cos(angle)) * radiusX,
                    y: 0.5 + CGFloat(sin(angle)) * radiusY
                ),
                width: 0.24 + CGFloat(index % 3) * 0.025,
                rotation: Double((index % 5) * 4 - 8)
            )
        }
    }
}


private extension UIBezierPath {
    convenience init(polygon points: [CGPoint]) {
        self.init()
        guard let first = points.first else { return }
        move(to: first)
        for point in points.dropFirst() {
            addLine(to: point)
        }
        close()
    }
}

private extension CollageEditorModel {
    struct SubjectPlacement {
        let center: CGPoint
        let width: CGFloat
        let rotation: Double
    }

    struct DragStart {
        let finger: CGPoint
        let center: CGPoint
    }

    struct BackgroundSlotDraft {
        let id: UUID
        let sourceID: String?
        let image: UIImage?
        let offset: CGSize
        let scale: CGFloat
        let opacity: Double

        init(_ slot: CollageBackgroundSlot) {
            id = slot.id
            sourceID = slot.sourceID
            image = slot.image
            offset = slot.offset
            scale = slot.scale
            opacity = slot.opacity
        }

        var restoredSlot: CollageBackgroundSlot {
            CollageBackgroundSlot(
                id: id,
                sourceID: sourceID,
                image: image,
                offset: offset,
                scale: scale,
                opacity: opacity
            )
        }

        func isEquivalent(to other: Self) -> Bool {
            id == other.id
                && sourceID == other.sourceID
                && image === other.image
                && offset == other.offset
                && scale == other.scale
                && opacity == other.opacity
        }
    }

    struct LayerDraft {
        let id: UUID
        let kind: CollageLayerKind
        let image: UIImage?
        let assetReference: String?
        let text: String
        let center: CGPoint
        let normalizedWidth: CGFloat
        let normalizedHeight: CGFloat?
        let scale: CGFloat
        let contentScale: CGFloat
        let contentOffset: CGSize
        let rotationDegrees: Double
        let opacity: Double
        let zIndex: Int
        let isEditable: Bool
        let isDeletable: Bool
        let textFont: CollageTextFont
        let isTextBold: Bool
        let isTextItalic: Bool
        let textAlignment: CollageTextAlignment
        let textColor: CollageColorValue
        let textBackground: CollageColorValue?
        let textFrameHeight: CGFloat?
        let textFontSizeRatio: CGFloat?
        let textLineHeightMultiple: CGFloat?
        let textMaximumLines: Int?
        let textOverflow: CollageTextOverflow?

        init(_ layer: CollageLayer) {
            id = layer.id
            kind = layer.kind
            image = layer.image
            assetReference = layer.assetReference
            text = layer.text
            center = layer.center
            normalizedWidth = layer.normalizedWidth
            normalizedHeight = layer.normalizedHeight
            scale = layer.scale
            contentScale = layer.contentScale
            contentOffset = layer.contentOffset
            rotationDegrees = layer.rotation.degrees
            opacity = layer.opacity
            zIndex = layer.zIndex
            isEditable = layer.isEditable
            isDeletable = layer.isDeletable
            textFont = layer.textFont
            isTextBold = layer.isTextBold
            isTextItalic = layer.isTextItalic
            textAlignment = layer.textAlignment
            textColor = layer.textColor
            textBackground = layer.textBackground
            textFrameHeight = layer.textFrameHeight
            textFontSizeRatio = layer.textFontSizeRatio
            textLineHeightMultiple = layer.textLineHeightMultiple
            textMaximumLines = layer.textMaximumLines
            textOverflow = layer.textOverflow
        }

        var restoredLayer: CollageLayer {
            CollageLayer(
                id: id,
                kind: kind,
                image: image,
                assetReference: assetReference,
                text: text,
                center: center,
                normalizedWidth: normalizedWidth,
                normalizedHeight: normalizedHeight,
                scale: scale,
                contentScale: contentScale,
                contentOffset: contentOffset,
                rotation: .degrees(rotationDegrees),
                opacity: opacity,
                zIndex: zIndex,
                isEditable: isEditable,
                isDeletable: isDeletable,
                textFont: textFont,
                isTextBold: isTextBold,
                isTextItalic: isTextItalic,
                textAlignment: textAlignment,
                textColor: textColor,
                textBackground: textBackground,
                textFrameHeight: textFrameHeight,
                textFontSizeRatio: textFontSizeRatio,
                textLineHeightMultiple: textLineHeightMultiple,
                textMaximumLines: textMaximumLines,
                textOverflow: textOverflow
            )
        }

        func isEquivalent(to other: Self) -> Bool {
            id == other.id
                && kind == other.kind
                && image === other.image
                && assetReference == other.assetReference
                && text == other.text
                && center == other.center
                && normalizedWidth == other.normalizedWidth
                && normalizedHeight == other.normalizedHeight
                && scale == other.scale
                && contentScale == other.contentScale
                && contentOffset == other.contentOffset
                && rotationDegrees == other.rotationDegrees
                && opacity == other.opacity
                && zIndex == other.zIndex
                && isEditable == other.isEditable
                && isDeletable == other.isDeletable
                && textFont == other.textFont
                && isTextBold == other.isTextBold
                && isTextItalic == other.isTextItalic
                && textAlignment == other.textAlignment
                && textColor == other.textColor
                && textBackground == other.textBackground
                && textFrameHeight == other.textFrameHeight
                && textFontSizeRatio == other.textFontSizeRatio
                && textLineHeightMultiple == other.textLineHeightMultiple
                && textMaximumLines == other.textMaximumLines
                && textOverflow == other.textOverflow
        }
    }

    struct EditorSnapshot {
        let backgrounds: [BackgroundSlotDraft]
        let isSplitBackground: Bool
        let splitFraction: CGFloat
        let activeBackgroundIndex: Int
        let layers: [LayerDraft]
        let selectedLayerID: UUID?

        func isEquivalent(to other: Self) -> Bool {
            backgrounds.count == other.backgrounds.count
                && zip(backgrounds, other.backgrounds).allSatisfy { pair in
                    pair.0.isEquivalent(to: pair.1)
                }
                && isSplitBackground == other.isSplitBackground
                && splitFraction == other.splitFraction
                && activeBackgroundIndex == other.activeBackgroundIndex
                && layers.count == other.layers.count
                && zip(layers, other.layers).allSatisfy { pair in
                    pair.0.isEquivalent(to: pair.1)
                }
        }

        func restore(into model: CollageEditorModel) {
            model.backgroundSlots = backgrounds.map(\.restoredSlot)
            model.isSplitBackground = isSplitBackground
            model.splitFraction = splitFraction
            model.activeBackgroundIndex = min(
                max(activeBackgroundIndex, 0),
                max(0, backgrounds.count - 1)
            )
            model.layers = layers.map(\.restoredLayer)
            model.selectedLayerID = selectedLayerID.flatMap { id in
                model.layers.contains(where: { $0.id == id }) ? id : nil
            }
            model.cropEditingLayerID = nil
            model.isDraggingLayer = false
            model.isOverTrash = false
        }
    }

    struct BackgroundDraft {
        let slots: [BackgroundSlotDraft]
        let isSplit: Bool
        let splitFraction: CGFloat
        let activeIndex: Int
    }

    struct TextDraft {
        let text: String
        let font: CollageTextFont
        let isBold: Bool
        let isItalic: Bool
        let alignment: CollageTextAlignment
        let color: CollageColorValue
        let background: CollageColorValue?

        init(layer: CollageLayer) {
            text = layer.text
            font = layer.textFont
            isBold = layer.isTextBold
            isItalic = layer.isTextItalic
            alignment = layer.textAlignment
            color = layer.textColor
            background = layer.textBackground
        }

        func restore(into layer: CollageLayer) {
            layer.text = text
            layer.textFont = font
            layer.isTextBold = isBold
            layer.isTextItalic = isItalic
            layer.textAlignment = alignment
            layer.textColor = color
            layer.textBackground = background
        }
    }

    struct StickerCatalog: Decodable {
        let stickers: [Sticker]

        struct Sticker: Decodable {
            let id: String
            let assetName: String

            enum CodingKeys: String, CodingKey {
                case id
                case assetName = "asset_name"
            }
        }
    }
}
